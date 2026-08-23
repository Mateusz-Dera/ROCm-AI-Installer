#!/usr/bin/env python3

import argparse
import json
import sys

import torch


def compare(reference, candidate, label, problems):
    if (reference is None) != (candidate is None):
        problems.append(f"{label}: one side is None, the other is not")
        return
    if reference is None:
        return
    for index, (a, b) in enumerate(zip(reference[:-1], candidate[:-1])):
        if a.shape != b.shape:
            problems.append(f"{label}[{index}]: shape {tuple(a.shape)} vs {tuple(b.shape)}")
        elif not torch.equal(a, b):
            problems.append(f"{label}[{index}]: values differ")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--heads", type=int, default=8)
    ap.add_argument("--head-dim", type=int, default=256)
    ap.add_argument("--prefill", type=int, default=2048)
    ap.add_argument("--decode-steps", type=int, default=64)
    ap.add_argument("--key-bits", type=int, default=4)
    ap.add_argument("--value-bits", type=int, default=4)
    ap.add_argument("--share-kv", action="store_true",
                    help="keys are rebuilt from values, as on Gemma 4 full-attention layers")
    ap.add_argument("--kv-identical", action="store_true",
                    help="feed identical K and V so the store drops the values")
    args = ap.parse_args()

    from turboquant.store import CompressedKVStore

    torch.manual_seed(1234)
    device = torch.device("cuda")
    capacity = args.prefill + args.decode_steps

    def make(capacity_value):
        store = CompressedKVStore(
            head_dim=args.head_dim, num_kv_heads=args.heads,
            key_bits=args.key_bits, value_bits=args.value_bits,
            device=device, layer_idx=0, capacity=capacity_value,
        )
        store.share_kv = args.share_kv
        return store

    chunked = make(0)
    prealloc = make(capacity)
    if prealloc.capacity != capacity:
        print(json.dumps({"error": "capacity was not honoured by the store"}))
        raise SystemExit(2)

    lengths = [args.prefill] + [1] * args.decode_steps
    problems = []
    torch.cuda.reset_peak_memory_stats()

    for step, length in enumerate(lengths):
        key = torch.randn(length, args.heads, args.head_dim, device=device, dtype=torch.bfloat16)
        value = key if args.kv_identical else torch.randn_like(key)
        chunked.append_chunk(key, value)
        prealloc.append_chunk(key, value)

        if step in (0, len(lengths) // 2, len(lengths) - 1):
            left, right = chunked.get_flat_cache(), prealloc.get_flat_cache()
            if left is None or right is None:
                problems.append(f"step {step}: one flat cache is None")
                continue
            if left.num_tokens != right.num_tokens:
                problems.append(f"step {step}: {left.num_tokens} vs {right.num_tokens} tokens")
            compare(left.prod_q, right.prod_q, f"step {step} prod_q", problems)
            compare(left.value_q, right.value_q, f"step {step} value_q", problems)

    print(json.dumps({
        "tokens": chunked.num_tokens,
        "equal": not problems,
        "problems": problems[:5],
        "chunked_store_mib": round(chunked.memory_bytes() / 2**20, 1),
        "prealloc_store_mib": round(prealloc.memory_bytes() / 2**20, 1),
    }))
    if problems:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
