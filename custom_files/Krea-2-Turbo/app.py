# Krea 2 is licensed under the Krea 2 Community License Agreement.
# For more information, visit https://krea.ai/krea-2-licensing.

import os
import shutil
import random
import numpy as np
import torch
import gradio as gr
from PIL import Image

try:
    import spaces
except ImportError:
    spaces = type('', (), {'GPU': lambda *a, **kw: lambda f: f})()

from diffusers import Krea2Pipeline, Krea2Transformer2DModel, BitsAndBytesConfig
from diffusers.pipelines.stable_diffusion.safety_checker import StableDiffusionSafetyChecker
from transformers import CLIPImageProcessor

DTYPE = torch.bfloat16
TURBO_REPO = "krea/Krea-2-Turbo"
MAX_SEED = 2**31 - 1
CUSTOM_LORA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "loras")

print("Loading Krea 2 Turbo with 4-bit NF4 quantization...")

quantization_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_compute_dtype=DTYPE,
    bnb_4bit_quant_type="nf4",
)

transformer = Krea2Transformer2DModel.from_pretrained(
    TURBO_REPO,
    subfolder="transformer",
    quantization_config=quantization_config,
    torch_dtype=DTYPE,
)

pipe = Krea2Pipeline.from_pretrained(
    TURBO_REPO,
    transformer=transformer,
    torch_dtype=DTYPE,
)
pipe.enable_model_cpu_offload()

print("Krea 2 Turbo loaded successfully.")

print("Loading safety checker...")
safety_checker = StableDiffusionSafetyChecker.from_pretrained(
    "CompVis/stable-diffusion-safety-checker", torch_dtype=torch.float32
)
safety_feature_extractor = CLIPImageProcessor.from_pretrained(
    "openai/clip-vit-large-patch14"
)
print("Safety checker loaded.")


def _check_nsfw(image):
    safety_input = safety_feature_extractor(images=image, return_tensors="pt")
    np_images = [np.array(image)]
    _, has_nsfw = safety_checker(
        images=np_images,
        clip_input=safety_input.pixel_values.to(torch.float32),
    )
    return has_nsfw[0]

RESOLUTIONS = {
    "Square 1024": (1024, 1024),
    "Portrait 1024": (832, 1216),
    "Landscape 1024": (1216, 832),
    "Square 2K": (2048, 2048),
}

BUILTIN_LORAS = {
    "Retro Anime": ("krea/Krea-2-LoRA-retroanime", "retroanime.safetensors", "Purple retro anime style"),
    "Dark Brush": ("krea/Krea-2-LoRA-darkbrush", "darkbrush.safetensors", "monochrome ink wash style"),
    "Dot Matrix": ("krea/Krea-2-LoRA-dotmatrix", "dotmatrix.safetensors", "Monochrome stippling style"),
    "Kids Drawing": ("krea/Krea-2-LoRA-kidsdrawing", "kidsdrawing.safetensors", "naive expressive sketch style"),
    "Neon Drip": ("krea/Krea-2-LoRA-neondrip", "neondrip.safetensors", "Textured abstract style"),
    "Rainy Window": ("krea/Krea-2-LoRA-rainywindow", "rainywindow.safetensors", "rainy window style"),
    "Soft Watercolor": ("krea/Krea-2-LoRA-softwatercolor", "softwatercolor.safetensors", "Art Deco watercolor style"),
    "Sunset Blur": ("krea/Krea-2-LoRA-sunsetblur", "sunsetblur.safetensors", "ethereal motion blur style"),
    "Vintage Tarot": ("krea/Krea-2-LoRA-vintagetarot", "vintagetarot.safetensors", "vintage tarot style"),
}

os.makedirs(CUSTOM_LORA_DIR, exist_ok=True)


def _load_custom_loras():
    custom = {}
    for f in sorted(os.listdir(CUSTOM_LORA_DIR)):
        if f.endswith(".safetensors"):
            name = f.removesuffix(".safetensors")
            custom[f"Custom: {name}"] = (os.path.join(CUSTOM_LORA_DIR, f), f, "")
    return custom


def _all_lora_choices():
    choices = ["None"] + list(BUILTIN_LORAS.keys())
    for name in _load_custom_loras():
        choices.append(name)
    return choices


_current_lora = None


def _apply_lora(lora_name, lora_strength):
    global _current_lora

    if lora_name == "None":
        if _current_lora is not None:
            pipe.unload_lora_weights()
            _current_lora = None
        return

    all_loras = {**BUILTIN_LORAS, **_load_custom_loras()}
    if lora_name not in all_loras:
        raise gr.Error(f"Unknown LoRA: {lora_name}")

    source, weight_name, _ = all_loras[lora_name]
    if _current_lora != lora_name:
        if _current_lora is not None:
            pipe.unload_lora_weights()
        if source.startswith("/") or source.startswith("."):
            pipe.transformer.load_lora_adapter(
                os.path.dirname(source), weight_name=os.path.basename(source)
            )
        else:
            pipe.transformer.load_lora_adapter(source, weight_name=weight_name)
        _current_lora = lora_name
    pipe.transformer.set_adapters("default", weights=float(lora_strength))


def upload_lora(file):
    if file is None:
        return gr.update(), ""
    basename = os.path.basename(file)
    if not basename.endswith(".safetensors"):
        raise gr.Error("Only .safetensors files are supported.")
    dest = os.path.join(CUSTOM_LORA_DIR, basename)
    shutil.copy2(file, dest)
    name = f"Custom: {basename.removesuffix('.safetensors')}"
    choices = _all_lora_choices()
    return gr.update(choices=choices, value=name), f"Uploaded: {basename}"


def generate(
    prompt,
    negative_prompt="",
    lora_name="None",
    lora_strength=1.0,
    steps=8,
    guidance=0.0,
    width=1024,
    height=1024,
    seed=42,
    randomize=False,
    progress=gr.Progress(track_tqdm=True),
):
    if not prompt or not prompt.strip():
        raise gr.Error("Enter a prompt to generate an image.")

    if randomize:
        seed = random.randint(0, MAX_SEED)
    seed = int(seed)
    generator = torch.Generator("cuda").manual_seed(seed)

    _apply_lora(lora_name, lora_strength)

    try:
        image = pipe(
            prompt=prompt,
            negative_prompt=(negative_prompt or None) if guidance > 0 else None,
            height=int(height),
            width=int(width),
            num_inference_steps=int(steps),
            guidance_scale=float(guidance),
            generator=generator,
        ).images[0]
    except RuntimeError as exc:
        torch.cuda.empty_cache()
        raise gr.Error(
            f"Generation failed at {int(width)}x{int(height)}. "
            "Try a smaller resolution."
        ) from exc

    if _check_nsfw(image):
        image = Image.new("RGB", (int(width), int(height)), (0, 0, 0))
        raise gr.Error("Content blocked by safety filter (NSFW detected).")

    return image, seed


def on_resolution_change(label):
    w, h = RESOLUTIONS[label]
    return gr.update(value=w), gr.update(value=h)


def on_lora_change(lora_name):
    if lora_name == "None":
        return ""
    all_loras = {**BUILTIN_LORAS, **_load_custom_loras()}
    entry = all_loras.get(lora_name)
    if entry is None:
        return ""
    return entry[2]


with gr.Blocks(title="Krea 2 Turbo") as demo:
    gr.Markdown("# Krea 2 Turbo\nText-to-image generation (4-bit NF4 quantized)")
    gr.Markdown(
        "Krea 2 and the included LoRAs are licensed under the "
        "[Krea 2 Community License Agreement](https://krea.ai/krea-2-licensing).\n\n"
        "As required by the license (Section 4.2), generated images are checked by a "
        "[safety filter](https://huggingface.co/CompVis/stable-diffusion-safety-checker) "
        "to prevent NSFW content."
    )

    with gr.Row(equal_height=False):
        with gr.Column(scale=5):
            prompt = gr.Textbox(
                label="Prompt",
                lines=4,
                placeholder="Describe your image in natural language...",
            )
            run_btn = gr.Button("Generate", variant="primary")

            resolution = gr.Radio(
                list(RESOLUTIONS.keys()),
                value="Square 1024",
                label="Resolution",
            )

            with gr.Accordion("LoRA", open=False):
                lora_name = gr.Dropdown(
                    choices=_all_lora_choices(),
                    value="None",
                    label="Style LoRA",
                )
                lora_strength = gr.Slider(
                    0.0, 2.0, value=1.0, step=0.05, label="LoRA strength"
                )
                lora_trigger = gr.Textbox(
                    label="Trigger phrase (add to your prompt)",
                    interactive=False,
                )
                lora_upload = gr.File(
                    label="Upload custom LoRA (.safetensors)",
                    file_types=[".safetensors"],
                )
                upload_status = gr.Textbox(
                    label="Upload status", interactive=False,
                )

            with gr.Accordion("Advanced", open=False):
                negative_prompt = gr.Textbox(
                    label="Negative prompt",
                    lines=1,
                    info="Only used when guidance scale is above 0.",
                )
                steps = gr.Slider(1, 50, value=8, step=1, label="Steps")
                guidance = gr.Slider(
                    0.0, 10.0, value=0.0, step=0.1, label="Guidance scale"
                )
                with gr.Row():
                    width = gr.Slider(512, 2048, value=1024, step=16, label="Width")
                    height = gr.Slider(512, 2048, value=1024, step=16, label="Height")
                with gr.Row():
                    seed = gr.Slider(0, MAX_SEED, value=0, step=1, label="Seed")
                    randomize = gr.Checkbox(value=True, label="Randomize seed")

        with gr.Column(scale=6):
            output = gr.Image(label="Result", format="png")

    resolution.change(on_resolution_change, resolution, [width, height])
    lora_name.change(on_lora_change, lora_name, lora_trigger)
    lora_upload.change(upload_lora, lora_upload, [lora_name, upload_status])

    inputs = [
        prompt, negative_prompt, lora_name, lora_strength,
        steps, guidance, width, height, seed, randomize,
    ]
    run_btn.click(generate, inputs, [output, seed])
    prompt.submit(generate, inputs, [output, seed])

demo.launch(server_name="0.0.0.0")
