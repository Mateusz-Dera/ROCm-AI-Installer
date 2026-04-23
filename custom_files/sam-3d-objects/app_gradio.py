import os
import sys
import tempfile
import numpy as np
import gradio as gr

os.environ.setdefault("CUDA_HOME", os.environ.get("ROCM_PATH", "/opt/rocm"))
os.environ["LIDRA_SKIP_INIT"] = "true"

sys.path.append("notebook")
from inference import Inference

CHECKPOINTS_DIR = "checkpoints/hf"
PIPELINE_YAML = f"{CHECKPOINTS_DIR}/pipeline.yaml"

if not os.path.exists(PIPELINE_YAML):
    raise FileNotFoundError(
        f"Checkpoints not found at {CHECKPOINTS_DIR}. "
        "Request access at https://huggingface.co/facebook/sam-3d-objects then download with:\n"
        "  huggingface-cli download --repo-type model --local-dir checkpoints/hf-dl "
        "--max-workers 1 facebook/sam-3d-objects && "
        "mv checkpoints/hf-dl/checkpoints checkpoints/hf && rm -rf checkpoints/hf-dl"
    )

model = Inference(PIPELINE_YAML, compile=False)


def generate(editor, seed):
    if editor is None or editor.get("background") is None:
        raise gr.Error("Upload an image and paint the object with the brush.")

    bg = np.array(editor["background"]).astype(np.uint8)
    image_rgb = bg[..., :3]

    layers = editor.get("layers", [])
    if not layers:
        raise gr.Error("Paint the object mask over the image using the brush tool.")

    layer = np.array(layers[0])
    if layer.ndim == 3 and layer.shape[-1] == 4:
        mask = layer[..., 3] > 0
    else:
        mask = layer.max(axis=-1) > 0

    if not mask.any():
        raise gr.Error("Mask is empty — paint over the object you want to reconstruct.")

    seed_val = int(seed) if seed is not None else None
    output = model(image_rgb, mask, seed=seed_val)

    out_path = tempfile.NamedTemporaryFile(suffix=".ply", delete=False, dir="/tmp").name
    output["gs"].save_ply(out_path)
    return out_path, out_path


with gr.Blocks(title="SAM 3D Objects") as demo:
    gr.Markdown(
        "## SAM 3D Objects — Single-Image 3D Reconstruction\n"
        "1. Upload an image  "
        "2. Paint over the object with the brush  "
        "3. Click **Generate**"
    )
    with gr.Row():
        with gr.Column(scale=1):
            editor = gr.ImageEditor(
                label="Image + mask (paint the object)",
                type="numpy",
                brush=gr.Brush(colors=["#ff0000"], color_mode="fixed"),
                eraser=gr.Eraser(),
                layers=True,
                transforms=[],
            )
            seed = gr.Number(label="Seed", value=42, precision=0)
            btn = gr.Button("Generate 3D Model", variant="primary")
        with gr.Column(scale=1):
            model_3d = gr.Model3D(label="3D Gaussian Splat (.ply)")
            ply_file = gr.File(label="Download .ply")

    btn.click(generate, inputs=[editor, seed], outputs=[model_3d, ply_file])

demo.launch(server_name="0.0.0.0")
