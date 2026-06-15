#!/usr/bin/env python3
"""TripoSplat Gradio API test helper.

Uploads a sample image, calls generate (5 steps, 32768 gaussians for speed),
verifies PLY output exists and is non-empty.
Prints PLY_OK:<path>:<size> on success.
"""
import os, json, uuid, subprocess
import requests

BASE_URL   = "http://localhost:7860"
IMAGE_PATH = "/AI/TripoSplat/static/example_inputs/creature_butterfly.webp"
OUT_PLY    = "/tmp/triposplat_test.ply"
MARKER     = "/tmp/ts_triposplat_start"

SESSION_HASH = uuid.uuid4().hex


def log(msg):
    import sys
    print(f"[triposplat] {msg}", file=sys.stderr, flush=True)


def _stream_queue_data(event_id, timeout):
    url = f"{BASE_URL}/gradio_api/queue/data?session_hash={SESSION_HASH}"
    resp = requests.get(url, stream=True, timeout=timeout + 10)
    resp.raise_for_status()
    try:
        for raw in resp.iter_lines(decode_unicode=True):
            line = raw.strip()
            if not line.startswith("data:"):
                continue
            try:
                msg = json.loads(line[5:].strip())
            except Exception:
                continue
            if msg.get("event_id") and msg["event_id"] != event_id:
                continue
            kind = msg.get("msg", "")
            if kind == "heartbeat":
                continue
            if kind == "process_completed":
                if msg.get("success"):
                    return msg.get("output", {}).get("data", [])
                raise RuntimeError(f"call failed: {msg.get('output')}")
            if kind == "process_generating":
                data = msg.get("output", {}).get("data")
                log(f"  generating: {str(data)[:80]}")
            elif kind == "unexpected_error":
                raise RuntimeError(f"unexpected_error: {msg.get('message')}")
    finally:
        resp.close()
    raise RuntimeError("queue/data SSE stream ended unexpectedly")


def call(name, data, timeout=3600):
    r = requests.post(
        f"{BASE_URL}/gradio_api/call/{name}",
        json={"data": data, "session_hash": SESSION_HASH},
        timeout=30,
    )
    r.raise_for_status()
    event_id = r.json()["event_id"]
    log(f"{name} -> event_id={event_id}")
    return _stream_queue_data(event_id, timeout)


def main():
    log(f"Session hash: {SESSION_HASH}")
    open(MARKER, "w").close()

    # 1. Upload image
    log(f"Uploading {IMAGE_PATH}...")
    with open(IMAGE_PATH, "rb") as f:
        r = requests.post(f"{BASE_URL}/gradio_api/upload", files={"files": f}, timeout=30)
    r.raise_for_status()
    uploaded_path = r.json()[0]
    log(f"Uploaded: {uploaded_path}")
    image_fd = {"path": uploaded_path, "meta": {"_type": "gradio.FileData"}}

    # 2. Generate (5 steps, 32768 gaussians for speed)
    # inputs: image, seed, steps, guidance_scale, num_gaussians, output_format
    log("Generating (seed=42, steps=5, num_gaussians=32768)...")
    gen_data = call("generate", [
        image_fd,   # image
        42,         # seed
        5,          # inference steps (fast test)
        3.0,        # guidance_scale
        "32768",    # num_gaussians (smallest option)
        "ply",      # output_format
    ], timeout=1800)

    log(f"Response ({len(gen_data)} items): {str(gen_data)[:200]}")

    # 3. Extract info string and PLY path from response
    # Outputs: [preprocessed_image, viewer_html, download_button_filedata, info_str]
    info_str = ""
    ply_path = None

    for item in gen_data:
        if isinstance(item, str) and "gaussians" in item:
            info_str = item
        if isinstance(item, dict):
            p = item.get("path", "") or item.get("value", "")
            if isinstance(p, str) and ".ply" in p:
                ply_path = p

    if info_str:
        log(f"Info: {info_str}")

    # Fallback: find newest PLY in gradio_outputs (created after marker)
    if not ply_path:
        log("PLY path not in response — searching gradio_outputs/...")
        r2 = subprocess.run(
            ["find", "/AI/TripoSplat/gradio_outputs", "-name", "*.ply",
             "-newer", MARKER],
            capture_output=True, text=True,
        )
        candidates = [l for l in r2.stdout.strip().split("\n") if l.endswith(".ply")]
        if candidates:
            ply_path = candidates[0]
            log(f"Found via find: {ply_path}")

    if not ply_path:
        raise RuntimeError(f"No PLY file found. Response: {gen_data}")

    if not os.path.exists(ply_path):
        raise RuntimeError(f"PLY file not found at: {ply_path}")

    size = os.path.getsize(ply_path)
    if size == 0:
        raise RuntimeError(f"PLY file is empty: {ply_path}")

    import shutil
    shutil.copy(ply_path, OUT_PLY)
    print(f"PLY_OK:{ply_path}:{size}", flush=True)
    log(f"PLY saved to {OUT_PLY} ({size} bytes)")


if __name__ == "__main__":
    main()
