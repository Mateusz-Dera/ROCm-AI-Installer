#!/usr/bin/env python3
# trellis.cpp

import argparse
import os
import signal
import subprocess
import time

import gradio as gr
import requests

APP_DIR = os.environ.get("TRELLIS_DIR", "/AI/trellis.cpp")
MODELS_DIR = os.path.join(APP_DIR, "models")
OUTPUT_DIR = os.path.join(APP_DIR, "output")
EXAMPLE = os.path.join(APP_DIR, "examples", "bottle.png")
PORT = int(os.environ.get("TRELLIS_PORT", "8081"))
SERVER = f"http://localhost:{PORT}"
TIMEOUT = 3600
SERVER_START_TIMEOUT = 600
MARKER = "ss_flow.gguf"

WEIGHTS = {
    "q8 (10.0 GB)": "q8",
    "full (16.5 GB)": "full",
    "q4 (6.5 GB)": "q4",
}
RESOLUTIONS = ["512", "1024", "1536"]
BG_REMOVAL = ["auto", "threshold", "birefnet"]
UV_MODES = ["xatlas", "box"]
TEXTURE_FORMATS = ["off", "auto", "on"]

_server = None
_variant = None


def build_dir():
    path = os.path.join(APP_DIR, os.environ.get("TRELLIS_BUILD_DIR", "build"))
    if not os.path.exists(os.path.join(path, "trellis-server")):
        raise gr.Error(f"No trellis-server build in {path} - reinstall the application.")
    return path


def variant_dir(variant):
    return os.path.join(MODELS_DIR, variant)


def have_weights(variant):
    return os.path.exists(os.path.join(variant_dir(variant), MARKER))


def server_alive():
    try:
        return requests.get(f"{SERVER}/health", timeout=3).status_code == 200
    except requests.RequestException:
        return False


def stop_server():
    global _server, _variant
    if _server and _server.poll() is None:
        os.killpg(os.getpgid(_server.pid), signal.SIGTERM)
        try:
            _server.wait(timeout=30)
        except subprocess.TimeoutExpired:
            os.killpg(os.getpgid(_server.pid), signal.SIGKILL)
            _server.wait(timeout=10)
    _server, _variant = None, None


def start_server(variant, progress):
    global _server, _variant
    progress(0.2, desc=f"Starting the engine with the {variant} weights...")

    log = open(os.path.join(APP_DIR, "server.log"), "ab", buffering=0)
    _server = subprocess.Popen(
        [os.path.join(build_dir(), "trellis-server"),
         "--models", variant_dir(variant),
         "--host", "0.0.0.0", "--port", str(PORT)],
        cwd=APP_DIR, stdout=log, stderr=log, start_new_session=True,
    )

    deadline = time.time() + SERVER_START_TIMEOUT
    while time.time() < deadline:
        if _server.poll() is not None:
            raise gr.Error(f"The engine exited with code {_server.returncode}.")
        if server_alive():
            _variant = variant
            return
        time.sleep(2)

    stop_server()
    raise gr.Error(f"The engine did not become ready within {SERVER_START_TIMEOUT} s.")


def ensure_ready(variant, progress):
    if _variant == variant and server_alive():
        return
    if not have_weights(variant):
        raise gr.Error(f"The {variant} weights are missing from {variant_dir(variant)}.")
    stop_server()
    start_server(variant, progress)


def status_text():
    if _variant and server_alive():
        return f"Engine running with the {_variant} weights on port {PORT}"
    present = [name for name in WEIGHTS.values() if have_weights(name)]
    return f"Engine stopped. Weights on disk: {', '.join(present) or 'none'}"


def generate(image_path, weights, resolution, bg_removal, uv, seed, texture_format,
             progress=gr.Progress()):
    if not image_path:
        raise gr.Error("Upload an image first.")

    variant = WEIGHTS.get(weights, weights)
    ensure_ready(variant, progress)

    with open(image_path, "rb") as handle:
        payload = {"image": (os.path.basename(image_path), handle.read())}

    fields = {
        "resolution": resolution,
        "uv": uv,
        "seed": str(int(seed)),
        "webp": texture_format,
    }
    if bg_removal != "auto":
        fields["bg_removal"] = bg_removal
    payload.update({name: (None, value) for name, value in fields.items()})

    progress(0.5, desc="Generating the model...")
    started = time.perf_counter()
    try:
        reply = requests.post(f"{SERVER}/generate", files=payload, timeout=TIMEOUT)
    except requests.RequestException as error:
        raise gr.Error(f"Could not reach the engine: {error}")
    elapsed = time.perf_counter() - started

    if reply.status_code != 200:
        raise gr.Error(f"Generation failed (HTTP {reply.status_code}): {reply.text[:300]}")

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    out_path = os.path.join(OUTPUT_DIR, f"trellis_{variant}_{int(time.time())}_{int(seed)}.glb")
    with open(out_path, "wb") as handle:
        handle.write(reply.content)

    stats = (
        f"{os.path.basename(out_path)} | "
        f"{len(reply.content) / 1e6:.2f} MB | "
        f"{elapsed:.1f} s | "
        f"weights {variant}, resolution {resolution}, seed {int(seed)}, uv {uv}"
    )
    return out_path, stats, status_text()


def build_ui():
    with gr.Blocks(title="trellis.cpp") as demo:
        gr.Markdown("# trellis.cpp\nImage to textured 3D model.")

        with gr.Row():
            with gr.Column(scale=4):
                image = gr.Image(label="Image", type="filepath",
                                 sources=["upload", "clipboard"])
                weights = gr.Dropdown(list(WEIGHTS), value=list(WEIGHTS)[0],
                                      label="Weights")
                resolution = gr.Dropdown(RESOLUTIONS, value="512", label="Resolution")
                bg_removal = gr.Dropdown(BG_REMOVAL, value="auto", label="Background removal")
                uv = gr.Dropdown(UV_MODES, value="xatlas", label="UV unwrap")
                seed = gr.Number(value=42, precision=0, label="Seed")
                texture_format = gr.Dropdown(TEXTURE_FORMATS, value="off",
                                             label="WebP textures")
                run = gr.Button("Generate 3D", variant="primary")
                if os.path.exists(EXAMPLE):
                    gr.Examples([[EXAMPLE]], inputs=[image], label="Example")
            with gr.Column(scale=6):
                model = gr.Model3D(label="Model", height=600)
                stats = gr.Textbox(label="Stats", interactive=False)
                status = gr.Textbox(label="Engine", interactive=False)

        run.click(
            generate,
            [image, weights, resolution, bg_removal, uv, seed, texture_format],
            [model, stats, status],
            api_name="generate",
        )
        demo.load(status_text, None, status)
    return demo


def main():
    parser = argparse.ArgumentParser(description="trellis.cpp")
    parser.add_argument("--ip", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=7860)
    args = parser.parse_args()

    try:
        build_ui().launch(server_name=args.ip, server_port=args.port,
                          allowed_paths=[OUTPUT_DIR])
    finally:
        stop_server()


if __name__ == "__main__":
    main()
