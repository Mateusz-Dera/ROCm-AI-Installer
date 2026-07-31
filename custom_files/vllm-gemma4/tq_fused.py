"""Fused dequantise + RMSNorm + RoPE for the compressed KV store.

Profiling the decode step attributed 39 ms/step to the plugin, of which 23 ms
was rebuilding keys from the shared projection and 8 ms was dequantising the
values - against 3 ms for the actual bmm. The cost is not arithmetic, it is
handing full-size intermediates between phases: unpack to a temporary, scale
into another, permute for the norm, permute back for the matmul.

This does all of it in one pass and writes both tensors straight into the
layout the attention wants, so nothing is permuted and nothing intermediate is
materialised.

Contracts read off the live model rather than assumed (see tq_probe_shapes.py):
  - k_norm is a plain RMSNorm, eps 1e-6, scaling by w (NOT Gemma's 1+w)
  - rotary is NeoX-style with rotary_dim == head_size == 512, so the halves
    split evenly and cos_sin_cache rows are [cos(256) | sin(256)]
  - values are 2-bit, group size 32, stored as [H, N, D/4] uint8
"""
import torch
import triton
import triton.language as tl


@triton.jit
def _dequant_norm_rope(
    data_ptr, scale_ptr, zero_ptr,          # packed store
    gamma_ptr, cos_sin_ptr,                 # norm weight, rope table
    v_out_ptr, k_out_ptr,
    N, start_pos,
    s_d_h, s_d_n,                           # strides of data   [H, N, D/4]
    s_s_h, s_s_n,                           # strides of scales [H, N, D/32]
    s_o_h, s_o_n,                           # strides of outputs[H, N, D]
    s_cs,                                   # stride of cos_sin rows
    eps,
    HALF: tl.constexpr,                     # D // 2
    GROUP: tl.constexpr,                    # quantisation group size
    BITS: tl.constexpr,
):
    n = tl.program_id(0)
    h = tl.program_id(1)
    if n >= N:
        return

    per_byte = 8 // BITS
    mask_bits = (1 << BITS) - 1

    d1 = tl.arange(0, HALF)                 # [0, 256)
    d2 = d1 + HALF                          # [256, 512)

    base_d = data_ptr + h * s_d_h + n * s_d_n
    base_s = scale_ptr + h * s_s_h + n * s_s_n
    base_z = zero_ptr + h * s_s_h + n * s_s_n

    # Unpack: byte index and shift derived from the element index, so the same
    # byte is read by the per_byte elements that live in it - cheap, it stays
    # in cache.
    b1 = tl.load(base_d + d1 // per_byte).to(tl.int32)
    b2 = tl.load(base_d + d2 // per_byte).to(tl.int32)
    q1 = (b1 >> ((d1 % per_byte) * BITS)) & mask_bits
    q2 = (b2 >> ((d2 % per_byte) * BITS)) & mask_bits

    sc1 = tl.load(base_s + d1 // GROUP).to(tl.float32)
    sc2 = tl.load(base_s + d2 // GROUP).to(tl.float32)
    z1 = tl.load(base_z + d1 // GROUP).to(tl.float32)
    z2 = tl.load(base_z + d2 // GROUP).to(tl.float32)

    v1 = q1.to(tl.float32) * sc1 + z1
    v2 = q2.to(tl.float32) * sc2 + z2

    out_base = h * s_o_h + n * s_o_n
    tl.store(v_out_ptr + out_base + d1, v1.to(tl.float16))
    tl.store(v_out_ptr + out_base + d2, v2.to(tl.float16))

    # RMSNorm over the whole head dim, then the per-element weight.
    ssq = tl.sum(v1 * v1, axis=0) + tl.sum(v2 * v2, axis=0)
    inv = 1.0 / tl.sqrt(ssq / (2 * HALF) + eps)
    g1 = tl.load(gamma_ptr + d1).to(tl.float32)
    g2 = tl.load(gamma_ptr + d2).to(tl.float32)
    n1 = v1 * inv * g1
    n2 = v2 * inv * g2

    # NeoX rotation: the table row holds cos in the first half, sin in the
    # second, both of length HALF.
    row = cos_sin_ptr + (start_pos + n) * s_cs
    cos = tl.load(row + d1).to(tl.float32)
    sin = tl.load(row + HALF + d1).to(tl.float32)

    k1 = n1 * cos - n2 * sin
    k2 = n2 * cos + n1 * sin
    tl.store(k_out_ptr + out_base + d1, k1.to(tl.float16))
    tl.store(k_out_ptr + out_base + d2, k2.to(tl.float16))


def dequant_norm_rope(value_q, gamma, cos_sin_cache, start_pos,
                      group_size=32, eps=1e-6):
    """Return (k, v), both [H, N, D] fp16, from the packed store.

    Replaces dequantize_values() followed by _k_from_v() and produces the
    result already in the layout the attention bmm consumes.
    """
    data, scales, zeros = value_q.data, value_q.scales, value_q.zeros
    bits = getattr(value_q, "bits", 2)
    H, N, packed_d = data.shape
    D = packed_d * (8 // bits)
    assert D % 2 == 0 and D == gamma.shape[0], (D, gamma.shape)

    v_out = torch.empty((H, N, D), dtype=torch.float16, device=data.device)
    k_out = torch.empty((H, N, D), dtype=torch.float16, device=data.device)

    _dequant_norm_rope[(N, H)](
        data, scales, zeros, gamma, cos_sin_cache, v_out, k_out,
        N, start_pos,
        data.stride(0), data.stride(1),
        scales.stride(0), scales.stride(1),
        v_out.stride(0), v_out.stride(1),
        cos_sin_cache.stride(0),
        eps,
        HALF=D // 2, GROUP=group_size, BITS=bits,
        num_warps=4,
    )
    return k_out, v_out
