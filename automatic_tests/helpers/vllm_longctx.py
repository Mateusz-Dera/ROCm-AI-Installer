#!/usr/bin/env python3

import argparse
import collections
import json
import re
import time
import urllib.request

FILLER = ("The archive room held rows of identical grey boxes, each labelled by "
          "year and quarter, and the ventilation hummed without pause. ")

ASK = ("\n\nTwo questions about the text above.\n"
       "1. What access code appeared at the very start? Give it exactly.\n"
       "2. In three plain sentences, describe what the repeated passage is about.\n")


def build_prompt(tokenizer, target, code):
    head = f"REMEMBER: the access code is {code}.\n\n"
    overhead = len(tokenizer(head + ASK)["input_ids"])
    unit = len(tokenizer(FILLER)["input_ids"])
    repeats = max(1, (target - overhead) // unit)
    return head + FILLER * repeats + ASK


def gibberish_report(text):
    """Cheap structural checks that separate prose from degenerate output."""
    stripped = text.strip()
    words = re.findall(r"[A-Za-z']+", stripped)
    metrics = {
        "chars": len(stripped),
        "words": len(words),
    }
    if not words:
        metrics.update(alpha_ratio=0.0, unique_ratio=0.0,
                       mean_word_len=0.0, repeat_ratio=1.0)
        return metrics

    letters = sum(c.isalpha() or c.isspace() or c in ".,;:'\"!?()-" for c in stripped)
    metrics["alpha_ratio"] = round(letters / len(stripped), 3)
    metrics["unique_ratio"] = round(len(set(w.lower() for w in words)) / len(words), 3)
    metrics["mean_word_len"] = round(sum(len(w) for w in words) / len(words), 2)

    lowered = [w.lower() for w in words]
    trigrams = collections.Counter(
        tuple(lowered[i:i + 3]) for i in range(max(0, len(lowered) - 2)))
    top = trigrams.most_common(1)[0][1] if trigrams else 0
    metrics["repeat_ratio"] = round(top / max(1, len(lowered) - 2), 3)
    return metrics


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://localhost:8002")
    ap.add_argument("--model", default="gemma-4-31b")
    ap.add_argument("--tokenizer", default="/AI/vllm-gemma4/models/gemma-4-31B-qat-W4A16-sym-g128")
    ap.add_argument("--target", type=int, default=250000)
    ap.add_argument("--code", default="DELTA-8842")
    ap.add_argument("--max-tokens", type=int, default=192)
    ap.add_argument("--timeout", type=int, default=7200)
    args = ap.parse_args()

    from transformers import AutoTokenizer

    tokenizer = AutoTokenizer.from_pretrained(args.tokenizer)
    prompt = build_prompt(tokenizer, args.target, args.code)

    body = json.dumps({
        "model": args.model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": args.max_tokens,
        "temperature": 0,
        "chat_template_kwargs": {"enable_thinking": False},
    }).encode()
    request = urllib.request.Request(
        args.url + "/v1/chat/completions", data=body,
        headers={"Content-Type": "application/json"})

    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=args.timeout) as response:
            payload = json.load(response)
    except Exception as error:
        print(json.dumps({"error": f"{type(error).__name__}: {error}"}))
        raise SystemExit(2)
    elapsed = time.perf_counter() - started

    message = payload["choices"][0]["message"]
    answer = (message.get("content") or message.get("reasoning_content") or "").strip()
    usage = payload.get("usage") or {}
    produced = usage.get("completion_tokens") or 0

    result = {
        "prompt_tokens": usage.get("prompt_tokens", 0),
        "completion_tokens": produced,
        "total_seconds": round(elapsed, 1),
        "tokens_per_second_end_to_end": round(produced / elapsed, 2) if elapsed else 0,
        "code_found": args.code in answer,
        "answer": answer[:400],
    }
    result.update(gibberish_report(answer))
    print(json.dumps(result))


if __name__ == "__main__":
    main()
