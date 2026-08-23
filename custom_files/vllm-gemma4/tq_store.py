"""
TurboQuant compressed KV store — owns the quantized historical segment.

Design rules:
  - With a known capacity the quantized history lives in one preallocated
    buffer written in place, so a read is a view and never a copy.
  - Without one the store falls back to chunk lists with a lazy flatten.
  - No per-token overhead; all writes are chunk-based.
"""

from __future__ import annotations

import os

import torch
from typing import Optional, NamedTuple

from turboquant.quantizer import TurboQuantProd, ProdQuantized
from turboquant.kv_cache import quantize_values, ValueQuantized


class FlatCache(NamedTuple):
    """Flattened view of compressed KV for fast read access."""
    prod_q: ProdQuantized       # (num_kv_heads, total_tokens, ...)
    value_q: ValueQuantized     # (num_kv_heads, total_tokens, ...)
    num_tokens: int


class CompressedKVStore:
    """Chunked compressed KV store with lazy flattening.

    Keys are quantized via TurboQuantProd (unbiased inner-product estimator).
    Values use symmetric group quantization.
    Chunks are kept in lists until a flat view is requested.
    """

    def __init__(
        self,
        head_dim: int,
        num_kv_heads: int,
        key_bits: int = 3,
        value_bits: int = 2,
        value_group_size: int = 32,
        device: torch.device = None,
        layer_idx: int = 0,
        capacity: Optional[int] = None,
    ):
        self.head_dim = head_dim
        self.num_kv_heads = num_kv_heads
        self.key_bits = key_bits
        self.value_bits = value_bits
        self.value_group_size = min(value_group_size, head_dim)
        self.device = device or torch.device("cuda")
        self.layer_idx = layer_idx

        self.quantizer = TurboQuantProd(
            dim=head_dim,
            bits=key_bits,
            device=self.device,
            seed=42 + layer_idx * 7,
        )

        self._key_chunks: list[ProdQuantized] = []
        self._value_chunks: list[ValueQuantized] = []
        self._chunk_lengths: list[int] = []

        # None until the first chunk decides it; True means values are the same
        # tensor as keys for this layer and are not stored at all.
        self._kv_shared: Optional[bool] = None

        if capacity is None:
            capacity = int(os.environ.get("TQ_CAPACITY", "0") or 0)
        self.capacity = max(0, int(capacity))
        self._buf_key: Optional[ProdQuantized] = None
        self._buf_val: Optional[ValueQuantized] = None
        self._len = 0

        # Set by the plugin for Gemma 4 full-attention layers under TQ_KV_SHARE:
        # K and V come from one projection there (those layers have no v_proj),
        # so only the raw one is stored and keys are rebuilt on read.
        self.share_kv: bool = False

        self._flat: Optional[FlatCache] = None

    @property
    def num_tokens(self) -> int:
        if self.capacity > 0:
            return self._len
        return sum(self._chunk_lengths)

    @property
    def num_chunks(self) -> int:
        return len(self._chunk_lengths)

    def append_chunk(self, key: torch.Tensor, value: torch.Tensor):
        """Quantize and store a chunk of KV pairs.

        key/value: (chunk_len, num_kv_heads, head_dim)
        """
        chunk_len = key.shape[0]

        # Reshape to (1, num_kv_heads, chunk_len, head_dim) for quantizer
        k = key.transpose(0, 1).unsqueeze(0)  # (1, H, T, D)
        v = value.transpose(0, 1).unsqueeze(0)

        if self._kv_shared is None:
            # Decided once per layer, on real data. torch.equal is exact - a
            # near-match must not enable this, since the values would then be
            # silently wrong rather than merely imprecise.
            self._kv_shared = bool(torch.equal(key, value))

        key_q = None if self.share_kv else self.quantizer.quantize(k)
        val_q = (
            None
            if self._kv_shared
            else quantize_values(
                v, bits=self.value_bits, group_size=self.value_group_size
            )
        )

        if self.capacity > 0:
            self._append_preallocated(key_q, val_q, chunk_len)
            return

        self._key_chunks.append(key_q)
        self._value_chunks.append(val_q)
        self._chunk_lengths.append(chunk_len)
        self._flat = None  # invalidate

    def _append_preallocated(self, key_q, val_q, chunk_len: int):
        if self._len + chunk_len > self.capacity:
            raise RuntimeError(
                f"TurboQuant store for layer {self.layer_idx} is full: "
                f"{self._len} + {chunk_len} exceeds the {self.capacity} token "
                f"capacity (raise TQ_CAPACITY to at least max_model_len)"
            )

        if key_q is not None:
            flat_key = _flatten_prod_q(key_q)
            if self._buf_key is None:
                self._buf_key = _alloc_prod_q(flat_key, self.capacity)
            _copy_prod_q(self._buf_key, flat_key, self._len, chunk_len)

        if val_q is not None:
            flat_val = _flatten_value_q(val_q)
            if self._buf_val is None:
                self._buf_val = _alloc_value_q(flat_val, self.capacity)
            _copy_value_q(self._buf_val, flat_val, self._len, chunk_len)

        self._len += chunk_len
        self._chunk_lengths[:] = [self._len]

    def get_flat_cache(self) -> Optional[FlatCache]:
        """Return a flattened view of all compressed tokens. Cached until next write."""
        if self.capacity > 0:
            if self._len == 0:
                return None
            return FlatCache(
                prod_q=(None if self._buf_key is None
                        else _view_prod_q(self._buf_key, self._len)),
                value_q=(None if self._buf_val is None
                         else _view_value_q(self._buf_val, self._len)),
                num_tokens=self._len,
            )

        if not self._key_chunks:
            return None

        if self._flat is not None:
            return self._flat

        if self.share_kv:
            # Keys were never quantised for this layer; the caller rebuilds them
            # from the values, which hold the shared pre-norm projection.
            flat_kq = None
            flat_vq = (
                _flatten_value_q(self._value_chunks[0])
                if len(self._value_chunks) == 1
                else _concat_value_q(
                    [_flatten_value_q(c) for c in self._value_chunks]
                )
            )
        elif len(self._key_chunks) == 1:
            flat_kq = _flatten_prod_q(self._key_chunks[0])
            flat_vq = (
                None if self._kv_shared
                else _flatten_value_q(self._value_chunks[0])
            )
        else:
            flat_kq = _concat_prod_q([_flatten_prod_q(c) for c in self._key_chunks])
            flat_vq = (
                None if self._kv_shared
                else _concat_value_q(
                    [_flatten_value_q(c) for c in self._value_chunks]
                )
            )

        total = self.num_tokens

        # The concatenated copy used to be cached *alongside* the chunks it was
        # built from, so the entire compressed history lived in GPU memory
        # twice - and because append invalidates the cache, every decoded token
        # rebuilt it, re-allocating a multi-hundred-megabyte tensor per token.
        # Collapse the chunk list onto the flattened tensors instead: same data,
        # one copy, and the next call finds a single chunk and does no work.
        # Safe now that the flatteners are idempotent.
        self._key_chunks[:] = [flat_kq]
        self._value_chunks[:] = [flat_vq]
        self._chunk_lengths[:] = [total]

        self._flat = FlatCache(
            prod_q=flat_kq,
            value_q=flat_vq,
            num_tokens=total,
        )
        return self._flat

    def memory_bytes(self) -> int:
        """Estimate GPU memory used by compressed data."""
        total = 0
        if self.capacity > 0:
            for buf in (self._buf_key, self._buf_val):
                if buf is None:
                    continue
                for field in buf[:-1]:
                    total += field.nelement() * field.element_size()
            return total
        for kq in self._key_chunks:
            if kq is None:
                continue
            total += kq.mse_indices.nelement()
            total += kq.qjl_signs.nelement()
            total += kq.residual_norms.nelement() * 2
            total += kq.norms.nelement() * 2
        for vq in self._value_chunks:
            if vq is None:
                continue
            total += vq.data.nelement()
            total += vq.scales.nelement() * 2
            total += vq.zeros.nelement() * 2
        return total

    def reset(self):
        self._kv_shared = None
        self._buf_key = None
        self._buf_val = None
        self._len = 0
        self._key_chunks.clear()
        self._value_chunks.clear()
        self._chunk_lengths.clear()
        self._flat = None


def _flatten_prod_q(pq: ProdQuantized) -> ProdQuantized:
    """Collapse batch dim: (1, H, T, ...) -> (H, T, ...). Idempotent."""
    if pq.mse_indices.dim() == 3:
        return pq
    return ProdQuantized(
        mse_indices=pq.mse_indices.reshape(-1, pq.mse_indices.shape[-2], pq.mse_indices.shape[-1]).contiguous(),
        qjl_signs=pq.qjl_signs.reshape(-1, pq.qjl_signs.shape[-2], pq.qjl_signs.shape[-1]).contiguous(),
        residual_norms=pq.residual_norms.reshape(-1, pq.residual_norms.shape[-1]).contiguous(),
        norms=pq.norms.reshape(-1, pq.norms.shape[-1]).contiguous(),
        mse_bits=pq.mse_bits,
    )


def _flatten_value_q(vq: ValueQuantized) -> ValueQuantized:
    """Collapse batch dim: (1, H, T, ...) -> (H, T, ...). Idempotent."""
    if vq.data.dim() == 3:
        return vq
    v_bits = vq.bits if len(vq) > 3 else 2
    return ValueQuantized(
        data=vq.data.reshape(-1, vq.data.shape[-2], vq.data.shape[-1]).contiguous(),
        scales=vq.scales.reshape(-1, vq.scales.shape[-2], vq.scales.shape[-1]).contiguous(),
        zeros=vq.zeros.reshape(-1, vq.zeros.shape[-2], vq.zeros.shape[-1]).contiguous(),
        bits=v_bits,
    )


def _concat_prod_q(chunks: list[ProdQuantized]) -> ProdQuantized:
    """Concatenate multiple flattened ProdQuantized along the token dimension."""
    return ProdQuantized(
        mse_indices=torch.cat([c.mse_indices for c in chunks], dim=-2),
        qjl_signs=torch.cat([c.qjl_signs for c in chunks], dim=-2),
        residual_norms=torch.cat([c.residual_norms for c in chunks], dim=-1),
        norms=torch.cat([c.norms for c in chunks], dim=-1),
        mse_bits=chunks[0].mse_bits,
    )


def _concat_value_q(chunks: list[ValueQuantized]) -> ValueQuantized:
    """Concatenate multiple flattened ValueQuantized along the token dimension."""
    v_bits = chunks[0].bits if len(chunks[0]) > 3 else 2
    return ValueQuantized(
        data=torch.cat([c.data for c in chunks], dim=-2),
        scales=torch.cat([c.scales for c in chunks], dim=-2),
        zeros=torch.cat([c.zeros for c in chunks], dim=-2),
        bits=v_bits,
    )


def _empty_at_capacity(sample: torch.Tensor, capacity: int) -> torch.Tensor:
    shape = list(sample.shape)
    shape[1] = capacity
    return torch.empty(shape, dtype=sample.dtype, device=sample.device)


def _alloc_prod_q(sample: ProdQuantized, capacity: int) -> ProdQuantized:
    return ProdQuantized(
        mse_indices=_empty_at_capacity(sample.mse_indices, capacity),
        qjl_signs=_empty_at_capacity(sample.qjl_signs, capacity),
        residual_norms=_empty_at_capacity(sample.residual_norms, capacity),
        norms=_empty_at_capacity(sample.norms, capacity),
        mse_bits=sample.mse_bits,
    )


def _alloc_value_q(sample: ValueQuantized, capacity: int) -> ValueQuantized:
    return ValueQuantized(
        data=_empty_at_capacity(sample.data, capacity),
        scales=_empty_at_capacity(sample.scales, capacity),
        zeros=_empty_at_capacity(sample.zeros, capacity),
        bits=sample.bits if len(sample) > 3 else 2,
    )


def _copy_prod_q(dst: ProdQuantized, src: ProdQuantized, start: int, length: int):
    end = start + length
    dst.mse_indices[:, start:end].copy_(src.mse_indices)
    dst.qjl_signs[:, start:end].copy_(src.qjl_signs)
    dst.residual_norms[:, start:end].copy_(src.residual_norms)
    dst.norms[:, start:end].copy_(src.norms)


def _copy_value_q(dst: ValueQuantized, src: ValueQuantized, start: int, length: int):
    end = start + length
    dst.data[:, start:end].copy_(src.data)
    dst.scales[:, start:end].copy_(src.scales)
    dst.zeros[:, start:end].copy_(src.zeros)


def _view_prod_q(buf: ProdQuantized, length: int) -> ProdQuantized:
    return ProdQuantized(
        mse_indices=buf.mse_indices[:, :length],
        qjl_signs=buf.qjl_signs[:, :length],
        residual_norms=buf.residual_norms[:, :length],
        norms=buf.norms[:, :length],
        mse_bits=buf.mse_bits,
    )


def _view_value_q(buf: ValueQuantized, length: int) -> ValueQuantized:
    return ValueQuantized(
        data=buf.data[:, :length],
        scales=buf.scales[:, :length],
        zeros=buf.zeros[:, :length],
        bits=buf.bits,
    )
