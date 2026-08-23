#!/usr/bin/env python3

import json
import re
import sys


def normalize(text):
    text = text.lower().replace("’", "'")
    text = re.sub(r"[^a-z0-9' ]", " ", text)
    return text.split()


def word_error_rate(reference, hypothesis):
    ref = normalize(reference)
    hyp = normalize(hypothesis)
    if not ref:
        return 1.0, 0, 0

    prev = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, 1):
        cur = [i]
        for j, h in enumerate(hyp, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r != h)))
        prev = cur
    return prev[-1] / len(ref), prev[-1], len(ref)


def main():
    with open(sys.argv[1], encoding="utf-8") as handle:
        reference = handle.read()
    hypothesis = sys.stdin.read()

    rate, edits, words = word_error_rate(reference, hypothesis)
    print(json.dumps({
        "wer": round(rate, 4),
        "edits": edits,
        "reference_words": words,
        "hypothesis_words": len(normalize(hypothesis)),
    }))


if __name__ == "__main__":
    main()
