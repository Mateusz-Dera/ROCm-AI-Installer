#!/usr/bin/env python3
"""
TRELLIS.2_rocm Gradio 6.x API test helper.
Uses gradio_client (installed in the venv) for correct SSE handling.

Outputs printed to stdout for the .sh wrapper to parse:
  GENERATE_OK:<preview_len>
  GLB_OK:<path>:<size_bytes>
  GLB_FAIL:<reason>
"""

import sys, os
from gradio_client import Client, handle_file

BASE_URL = "http://localhost:7860"
OUT_GLB  = "/tmp/trellis2_object.glb"


def log(msg):
    print(f"[trellis2] {msg}", file=sys.stderr, flush=True)


def main():
    # 0. Find an example image (already preprocessed RGBA .webp)
    img_dir = "/AI/TRELLIS.2_rocm/assets/example_image"
    images = sorted(f for f in os.listdir(img_dir)
                    if f.lower().endswith((".png", ".jpg", ".jpeg", ".webp")))
    if not images:
        print("NO_IMAGES", flush=True)
        sys.exit(1)
    image_path = os.path.join(img_dir, images[0])
    log(f"Using image: {image_path}")

    log("Connecting to Gradio server...")
    client = Client(BASE_URL)

    # 1. Start session
    log("Starting session...")
    client.predict(api_name="/start_session")
    log("Session started")

    # 2. Preprocess image (background removal + RGBA crop)
    log("Preprocessing image...")
    try:
        prep_path = client.predict(
            handle_file(image_path),
            api_name="/preprocess_image_1",
        )
        log(f"Preprocessed: {prep_path}")
        # Result is a server-side path string; wrap back into handle_file for next call
        preprocessed = handle_file(prep_path) if isinstance(prep_path, str) else prep_path
    except Exception as e:
        log(f"preprocess_image_1 failed ({e}), using raw upload")
        preprocessed = handle_file(image_path)

    # 3. Generate 3D model (reduced steps to keep test time reasonable)
    log("Generating 3D model (8 steps each stage)...")
    result = client.predict(
        preprocessed,   # image
        42,             # seed
        "512",          # resolution (reduced to fit 24 GB VRAM after model load)
        7.5,            # ss_guidance_strength
        0.7,            # ss_guidance_rescale
        8,              # ss_sampling_steps
        5.0,            # ss_rescale_t
        7.5,            # shape_slat_guidance_strength
        0.5,            # shape_slat_guidance_rescale
        8,              # shape_slat_sampling_steps
        3.0,            # shape_slat_rescale_t
        1.0,            # tex_slat_guidance_strength
        0.0,            # tex_slat_guidance_rescale
        8,              # tex_slat_sampling_steps
        3.0,            # tex_slat_rescale_t
        api_name="/image_to_3d",
    )

    # result may be a single value (preview HTML) or a tuple
    if isinstance(result, (list, tuple)):
        preview = result[1] if len(result) > 1 else result[0]
    else:
        preview = result
    prev_len = len(str(preview)) if preview else 0
    print(f"GENERATE_OK:{prev_len}", flush=True)
    log(f"Preview HTML length: {prev_len}")

    # 4. Extract GLB
    log("Extracting GLB (decimation=500000, texture=2048)...")
    try:
        glb_result = client.predict(
            500000,     # decimation_target
            2048,       # texture_size
            api_name="/extract_glb",
        )

        # extract_glb returns (glb_path, glb_path) — may be FileData dicts or strings
        def get_path(obj):
            if isinstance(obj, str):
                return obj
            if isinstance(obj, dict):
                return obj.get("path") or obj.get("value") or obj.get("name") or ""
            return ""

        if isinstance(glb_result, (list, tuple)):
            glb_path = get_path(glb_result[0])
            if not glb_path and len(glb_result) > 1:
                glb_path = get_path(glb_result[1])
        else:
            glb_path = get_path(glb_result)

        if glb_path and os.path.exists(glb_path):
            import shutil
            shutil.copy(glb_path, OUT_GLB)
            sz = os.path.getsize(OUT_GLB)
        else:
            sz = 0
        print(f"GLB_OK:{glb_path}:{sz}", flush=True)
        log(f"GLB: {glb_path} ({sz} bytes)")
    except Exception as e:
        print(f"GLB_FAIL:{e}", flush=True)
        log(f"GLB extraction failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
