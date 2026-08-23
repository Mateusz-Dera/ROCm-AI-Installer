#!/usr/bin/env python3
import json
import sys
import uuid

import httpx

BASE = f"http://localhost:{sys.argv[1]}"
ENDPOINT = sys.argv[2]
TIMEOUT = float(sys.argv[3])
PAYLOAD = json.loads(sys.argv[4])
SESSION = uuid.uuid4().hex


def upload(path):
    with open(path, "rb") as handle:
        response = httpx.post(f"{BASE}/gradio_api/upload",
                              files={"files": handle}, timeout=60)
    response.raise_for_status()
    return {"path": response.json()[0], "meta": {"_type": "gradio.FileData"}}


def resolve(item):
    if isinstance(item, dict) and "__file__" in item:
        return upload(item["__file__"])
    return item


def stream(event_id):
    url = f"{BASE}/gradio_api/queue/data?session_hash={SESSION}"
    with httpx.stream("GET", url, timeout=httpx.Timeout(TIMEOUT + 30)) as response:
        response.raise_for_status()
        for raw in response.iter_lines():
            line = raw.strip()
            if not line.startswith("data:"):
                continue
            try:
                message = json.loads(line[5:].strip())
            except ValueError:
                continue
            if message.get("event_id") and message["event_id"] != event_id:
                continue
            kind = message.get("msg", "")
            if kind == "process_completed":
                if message.get("success"):
                    return message.get("output", {}).get("data", [])
                raise RuntimeError(f"call failed: {message.get('output')}")
            if kind == "unexpected_error":
                raise RuntimeError(f"unexpected_error: {message.get('message')}")
    raise RuntimeError("the queue/data stream ended without a result")


def main():
    data = [resolve(item) for item in PAYLOAD]
    response = httpx.post(f"{BASE}/gradio_api/call/{ENDPOINT}",
                          json={"data": data, "session_hash": SESSION}, timeout=60)
    response.raise_for_status()
    print(json.dumps(stream(response.json()["event_id"])))


main()
