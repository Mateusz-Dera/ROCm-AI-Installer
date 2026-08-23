#!/usr/bin/env python3

import re
import sys

ESCAPABLE = '"\\$`'


def unescape(text):
    out, i = [], 0
    while i < len(text):
        if text[i] == "\\" and i + 1 < len(text) and text[i + 1] in ESCAPABLE:
            out.append(text[i + 1])
            i += 2
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def joined_lines(stream):
    buffer = ""
    for raw in stream:
        line = raw.rstrip("\n")
        if line.endswith("\\"):
            buffer += line[:-1]
            continue
        yield buffer + line
        buffer = ""
    if buffer:
        yield buffer


def main():
    for line in joined_lines(sys.stdin):
        if "podman exec -it" not in line:
            continue
        match = re.search(r"""bash -c "(.*)"\s*$""", line)
        if match:
            sys.stdout.write(unescape(match.group(1)))
            return
        match = re.search(r"""bash -c '(.*)'\s*$""", line)
        if match:
            sys.stdout.write(match.group(1))
            return
    raise SystemExit(1)


if __name__ == "__main__":
    main()
