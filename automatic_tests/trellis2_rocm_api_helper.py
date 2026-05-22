#!/usr/bin/env python3
"""
TRELLIS.2_rocm Gradio 6.x API test helper.

/call/{name}/{event_id} SSE keying: Gradio stores messages under session_hash when
session_hash is provided in POST body, but SSE GET /call/{name}/{event_id} looks
messages up by event_id — causing 404 for non-v2 API with custom session_hash.

Fix: use /queue/data?session_hash=HASH for SSE when session_hash is provided.
The queue/data endpoint keys by session_hash (correct), filters by event_id in client.

Workflow: start_session → upload → preprocess_image_1 → image_to_3d → extract_glb
"""
import sys, os, json, shutil, uuid
import requests

BASE_URL   = "http://localhost:7860"
IMAGE_PATH = "/AI/TRELLIS.2_rocm/assets/example_image/T.png"
OUT_GLB    = "/tmp/trellis2_rocm_test.glb"

SESSION_HASH = uuid.uuid4().hex


def log(msg):
    print(f"[trellis2] {msg}", file=sys.stderr, flush=True)


def _stream_queue_data(event_id, timeout):
    """Stream /queue/data?session_hash SSE, filter by event_id. Returns output data list."""
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


def _stream_sse(name, event_id, timeout):
    """Stream /call/{name}/{event_id} SSE — only valid for v2 (session_hash=None path)."""
    url = f"{BASE_URL}/gradio_api/call/{name}/{event_id}"
    resp = requests.get(url, stream=True, timeout=timeout + 10)
    resp.raise_for_status()
    current_event = None
    try:
        for raw in resp.iter_lines(decode_unicode=True):
            line = raw.strip()
            if line.startswith("event:"):
                current_event = line[6:].strip()
            elif line.startswith("data:"):
                if current_event == "heartbeat":
                    continue
                try:
                    result = json.loads(line[5:].strip())
                except Exception:
                    continue
                if current_event == "complete":
                    return result if isinstance(result, list) else []
                elif current_event == "error":
                    raise RuntimeError(f"{name} failed: {result}")
                elif current_event == "generating":
                    log(f"  {name}: {str(result)[:80]}")
    finally:
        resp.close()
    raise RuntimeError(f"{name} SSE ended unexpectedly")


def call_v2(name, payload, timeout=3600):
    """Named v2 API — stateless (no gr.State dependency). session_hash stays None."""
    r = requests.post(
        f"{BASE_URL}/gradio_api/call/v2/{name}",
        json=payload,
        timeout=30,
    )
    r.raise_for_status()
    event_id = r.json()["event_id"]
    log(f"{name} (v2) -> event_id={event_id}")
    return _stream_sse(name, event_id, timeout)


def call_positional(name, data, timeout=3600):
    """Non-v2 positional API with session_hash — gr.State persists across calls.

    Uses /queue/data?session_hash SSE because messages are keyed by session_hash,
    not event_id, so /call/{name}/{event_id} would return 404.
    """
    r = requests.post(
        f"{BASE_URL}/gradio_api/call/{name}",
        json={"data": data, "session_hash": SESSION_HASH},
        timeout=30,
    )
    r.raise_for_status()
    event_id = r.json()["event_id"]
    log(f"{name} (positional, session={SESSION_HASH[:8]}) -> event_id={event_id}")
    return _stream_queue_data(event_id, timeout)


def main():
    log(f"Session hash: {SESSION_HASH}")

    # 1. start_session — stateless demo.load event, v2 API fine
    log("Starting session...")
    call_v2("start_session", {}, timeout=30)

    # 2. Upload image
    log(f"Uploading {IMAGE_PATH}...")
    with open(IMAGE_PATH, "rb") as f:
        r = requests.post(f"{BASE_URL}/gradio_api/upload", files={"files": f}, timeout=30)
    r.raise_for_status()
    uploaded_path = r.json()[0]
    log(f"Uploaded: {uploaded_path}")
    image_fd = {"path": uploaded_path, "meta": {"_type": "gradio.FileData"}}

    # 3. Preprocess image — stateless, v2 API
    log("Preprocessing image...")
    pre_data = call_v2("preprocess_image_1", {"image": image_fd}, timeout=180)
    preprocessed = pre_data[0] if pre_data else image_fd
    log(f"Preprocessed: {str(preprocessed)[:120]}")

    # 4. Generate 3D via non-v2 + session_hash so gr.State (output_buf) is stored
    # inputs: [image, seed, resolution, ss_guidance_strength, ss_guidance_rescale,
    #          ss_sampling_steps, ss_rescale_t, shape_slat_guidance_strength,
    #          shape_slat_guidance_rescale, shape_slat_sampling_steps, shape_slat_rescale_t,
    #          tex_slat_guidance_strength, tex_slat_guidance_rescale,
    #          tex_slat_sampling_steps, tex_slat_rescale_t]
    log("Generating 3D (resolution=512, 4 steps per phase)...")
    gen_data = call_positional("image_to_3d", [
        preprocessed,
        42,       # seed
        "512",    # resolution
        7.5,      # ss_guidance_strength
        0.7,      # ss_guidance_rescale
        4,        # ss_sampling_steps
        5.0,      # ss_rescale_t
        7.5,      # shape_slat_guidance_strength
        0.5,      # shape_slat_guidance_rescale
        4,        # shape_slat_sampling_steps
        3.0,      # shape_slat_rescale_t
        1.0,      # tex_slat_guidance_strength
        0.0,      # tex_slat_guidance_rescale
        4,        # tex_slat_sampling_steps
        3.0,      # tex_slat_rescale_t
    ], timeout=3600)
    log(f"Generation complete: {str(gen_data)[:120]}")
    print("GENERATE_OK", flush=True)

    # 5. Extract GLB via non-v2 + same session_hash so Gradio injects gr.State
    # inputs: [output_buf (gr.State), decimation_target, texture_size]
    # Gradio ignores None for State and reads from session_state[block._id] instead
    log("Extracting GLB (decimation=100000, texture=1024)...")
    glb_data = call_positional("extract_glb", [
        None,    # output_buf (gr.State) — Gradio reads from session, not this value
        100000,  # decimation_target
        1024,    # texture_size
    ], timeout=1800)

    # Response: [Model3d FileData, Downloadbutton FileData]
    glb_path = None
    for item in glb_data:
        if isinstance(item, dict) and item.get("path"):
            glb_path = item["path"]
            break

    if not glb_path:
        raise RuntimeError(f"No GLB path in response: {glb_data}")
    if not os.path.exists(glb_path):
        raise RuntimeError(f"GLB file not found at: {glb_path}")

    size = os.path.getsize(glb_path)
    if size == 0:
        raise RuntimeError(f"GLB file is empty: {glb_path}")

    shutil.copy(glb_path, OUT_GLB)
    print(f"GLB_OK:{glb_path}:{size}", flush=True)
    log(f"GLB saved to {OUT_GLB} ({size} bytes)")


if __name__ == "__main__":
    main()
