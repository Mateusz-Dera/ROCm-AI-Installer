#!/usr/bin/env python3
"""
TRELLIS-AMD Gradio 4.44.1 API test helper.
Gradio 4.x uses: POST /upload, POST /queue/join, GET /queue/data (SSE).
gr.State (output_buf) is server-side – session_hash links generate → extract calls.

fn_index mapping (from /config):
  4  = start_session
  8  = preprocess_image_1
  11 = image_to_3d
  14 = extract_glb
  16 = extract_gaussian
"""
import sys, os, json, time
import requests

BASE_URL   = "http://localhost:7860"
IMAGE_PATH = "/AI/TRELLIS-AMD/assets/example_image/T.png"
SESSION    = "trellis_autotest_01"
OUT_VIDEO  = "/tmp/trellis_sample.mp4"
OUT_GLB    = "/tmp/trellis_object.glb"
OUT_PLY    = "/tmp/trellis_object.ply"

FN = {
    "start_session":      4,
    "preprocess_image_1": 8,
    "image_to_3d":       11,
    "extract_glb":       14,
    "extract_gaussian":  16,
}

def log(msg):
    print(f"[trellis] {msg}", file=sys.stderr, flush=True)

# ---------------------------------------------------------------------------
def queue_call(fn_index, data, timeout=1800):
    """Submit a job and wait for process_completed; return output data list."""
    # 1. Join queue
    r = requests.post(f"{BASE_URL}/queue/join",
        json={"data": data, "fn_index": fn_index,
              "session_hash": SESSION, "event_data": None},
        timeout=30)
    r.raise_for_status()
    event_id = r.json().get("event_id")
    if not event_id:
        raise RuntimeError(f"No event_id returned for fn_index={fn_index}")
    log(f"fn={fn_index} event_id={event_id}")

    # 2. Stream /queue/data until process_completed for this event
    url = f"{BASE_URL}/queue/data?session_hash={SESSION}"
    resp = requests.get(url, stream=True, timeout=timeout + 10)
    resp.raise_for_status()
    for raw in resp.iter_lines(decode_unicode=True):
        line = raw.strip()
        if not line.startswith("data:"):
            continue
        try:
            msg = json.loads(line[5:].strip())
        except Exception:
            continue
        mtype = msg.get("msg", "")
        if mtype == "process_completed":
            if msg.get("event_id") and msg["event_id"] != event_id:
                continue  # belongs to a different event
            if not msg.get("success", False):
                err = (msg.get("output") or {}).get("error") or "unknown error"
                raise RuntimeError(f"fn={fn_index} failed: {err}")
            return (msg.get("output") or {}).get("data", [])
        if mtype == "close_stream":
            raise RuntimeError(f"fn={fn_index} stream closed without completion")
    raise RuntimeError(f"fn={fn_index} SSE ended unexpectedly")

def get_path(obj):
    """Extract filesystem path from string, FileData dict, or VideoData dict."""
    if isinstance(obj, str):
        return obj
    if isinstance(obj, dict):
        # VideoData: {"video": {"path": "..."}, ...}
        if "video" in obj:
            return get_path(obj["video"])
        # FileData: {"path": "...", ...} or old {"name": "...", ...}
        return obj.get("path") or obj.get("name") or ""
    return ""

def copy_if_exists(src, dst):
    import shutil
    if src and os.path.exists(src):
        shutil.copy(src, dst)
        return os.path.getsize(dst)
    return 0

# ---------------------------------------------------------------------------
def main():
    # 1. Start session (creates /AI/TRELLIS-AMD/tmp/SESSION/)
    log("Starting session...")
    queue_call(FN["start_session"], [], timeout=30)
    log("Session started")

    # 2. Upload image
    log(f"Uploading {IMAGE_PATH}...")
    with open(IMAGE_PATH, "rb") as f:
        r = requests.post(f"{BASE_URL}/upload", files={"files": f}, timeout=30)
    r.raise_for_status()
    uploaded_path = r.json()[0]
    log(f"Uploaded: {uploaded_path}")
    image_fd = {"path": uploaded_path, "meta": {"_type": "gradio.FileData"}}

    # 3. Preprocess image
    log("Preprocessing image...")
    preproc_data = queue_call(FN["preprocess_image_1"], [image_fd], timeout=120)
    preprocessed = preproc_data[0] if preproc_data else image_fd
    log(f"Preprocessed: {get_path(preprocessed)}")

    # 4. Generate 3D model
    # NOTE: fn_index calls require ALL inputs including gr.State components.
    # image_to_3d inputs: [image, multiimages, is_multiimage(State), seed,
    #                      ss_guidance_strength, ss_sampling_steps,
    #                      slat_guidance_strength, slat_sampling_steps, multiimage_algo]
    # image_to_3d outputs: [output_buf(State), video_output]
    log("Generating 3D model (ss_steps=12, slat_steps=12)...")
    gen_data = queue_call(FN["image_to_3d"], [
        preprocessed,   # image (FileData)
        [],             # multiimages (Gallery – empty for single-image mode)
        False,          # is_multiimage (gr.State) – must be passed explicitly
        42,             # seed
        7.5,            # ss_guidance_strength
        12,             # ss_sampling_steps
        3.0,            # slat_guidance_strength
        12,             # slat_sampling_steps
        "stochastic",   # multiimage_algo
    ], timeout=1800)

    # gen_data[0] = state (output_buf), gen_data[1] = VideoData
    state_3d  = gen_data[0] if gen_data else None
    video_obj = gen_data[1] if len(gen_data) > 1 else None
    video_path = get_path(video_obj) if video_obj else ""
    sz = copy_if_exists(video_path, OUT_VIDEO)
    print(f"GENERATE_OK:{video_path}:{sz}", flush=True)
    log(f"Video: {video_path} ({sz} bytes), state type: {type(state_3d)}")

    # NOTE: state_3d may be None – Gradio 4.44.1 does not serialize numpy arrays
    # over the API (returns null). The state is stored server-side in the session;
    # Gradio will use it automatically when extract_glb/extract_gaussian are called
    # with the same session_hash and None is passed for the State input.
    log(f"State returned as None={state_3d is None} – Gradio will use server-side session state")

    # 5. Extract GLB
    # extract_glb inputs: [output_buf(State), mesh_simplify, texture_size]
    # extract_glb outputs: [model_output, download_glb]
    log("Extracting GLB...")
    try:
        glb_data = queue_call(FN["extract_glb"], [
            state_3d,   # output_buf (State) – passed explicitly
            0.95,       # mesh_simplify
            1024,       # texture_size
        ], timeout=600)
        # download_glb is the cleaner path (data[1])
        glb_path = get_path(glb_data[1]) if len(glb_data) > 1 else get_path(glb_data[0])
        sz = copy_if_exists(glb_path, OUT_GLB)
        print(f"GLB_OK:{glb_path}:{sz}", flush=True)
        log(f"GLB: {glb_path} ({sz} bytes)")
    except Exception as e:
        print(f"GLB_FAIL:{e}", flush=True)
        log(f"GLB failed: {e}")

    # 6. Extract Gaussian
    # extract_gaussian inputs: [output_buf(State)]
    # extract_gaussian outputs: [model_output, download_gs]
    log("Extracting Gaussian PLY...")
    try:
        gs_data = queue_call(FN["extract_gaussian"], [
            state_3d,   # output_buf (State) – passed explicitly
        ], timeout=300)
        ply_path = get_path(gs_data[1]) if len(gs_data) > 1 else get_path(gs_data[0])
        sz = copy_if_exists(ply_path, OUT_PLY)
        print(f"GAUSSIAN_OK:{ply_path}:{sz}", flush=True)
        log(f"PLY: {ply_path} ({sz} bytes)")
    except Exception as e:
        print(f"GAUSSIAN_FAIL:{e}", flush=True)
        log(f"Gaussian failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
