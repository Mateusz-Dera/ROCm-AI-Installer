# Krea 2 is licensed under the Krea 2 Community License Agreement.
# For more information, visit https://krea.ai/krea-2-licensing.

import os
import json
import shutil
import random
import numpy as np
import torch
import gradio as gr
from PIL import Image
from safetensors.torch import load_file as _st_load, save_file as _st_save

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
CUSTOM_METADATA_FILE = os.path.join(CUSTOM_LORA_DIR, "metadata.json")
IMAGES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "images")
os.makedirs(IMAGES_DIR, exist_ok=True)

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


def _load_custom_metadata():
    if os.path.exists(CUSTOM_METADATA_FILE):
        with open(CUSTOM_METADATA_FILE) as f:
            return json.load(f)
    return {}


def _save_custom_metadata(meta):
    with open(CUSTOM_METADATA_FILE, "w") as f:
        json.dump(meta, f, indent=2)


def _load_custom_loras():
    meta = _load_custom_metadata()
    custom = {}
    for f in sorted(os.listdir(CUSTOM_LORA_DIR)):
        if not f.endswith(".safetensors"):
            continue
        file_meta = meta.get(f, {})
        display_name = file_meta.get("name") or f"Custom: {f.removesuffix('.safetensors')}"
        trigger = file_meta.get("trigger", "")
        custom[display_name] = (os.path.join(CUSTOM_LORA_DIR, f), f, trigger)
    return custom


def _all_lora_choices():
    choices = ["None"] + list(BUILTIN_LORAS.keys())
    for name in _load_custom_loras():
        choices.append(name)
    return choices


def _is_custom(lora_name):
    return lora_name not in ("None",) and lora_name not in BUILTIN_LORAS


# ── Native Krea 2 LoRA → diffusers format converter ──────────────────────────

_NATIVE_PREFIX_MAP = [
    ("diffusion_model.txtfusion.layerwise_blocks.", "transformer.text_fusion.layerwise_blocks."),
    ("diffusion_model.txtfusion.refiner_blocks.",   "transformer.text_fusion.refiner_blocks."),
    ("diffusion_model.txtfusion.projector.",        "transformer.text_fusion.projector."),
    ("diffusion_model.blocks.",                     "transformer.transformer_blocks."),
    ("diffusion_model.last.linear.",                "transformer.final_layer.linear."),
    ("diffusion_model.first.",                      "transformer.img_in."),
]

_NATIVE_SPECIAL_MAP = {
    "diffusion_model.tmlp.0.":    "transformer.time_embed.linear_1.",
    "diffusion_model.tmlp.2.":    "transformer.time_embed.linear_2.",
    "diffusion_model.tproj.1.":   "transformer.time_mod_proj.",
    "diffusion_model.txtmlp.1.":  "transformer.txt_in.linear_1.",
    "diffusion_model.txtmlp.3.":  "transformer.txt_in.linear_2.",
}

_ATTR_MAP = [
    (".attn.wq.",   ".attn.to_q."),
    (".attn.wk.",   ".attn.to_k."),
    (".attn.wv.",   ".attn.to_v."),
    (".attn.wo.",   ".attn.to_out.0."),
    (".attn.gate.", ".attn.to_gate."),
    (".mlp.up.",    ".ff.up."),
    (".mlp.down.",  ".ff.down."),
    (".mlp.gate.",  ".ff.gate."),
]


def _convert_native_key(key):
    """Map one native Krea 2 LoRA key to diffusers format; return None to skip."""
    if key.endswith(".diff_b"):
        return None

    k = key
    matched = False
    for native, diffusers in _NATIVE_SPECIAL_MAP.items():
        if k.startswith(native):
            k = diffusers + k[len(native):]
            matched = True
            break
    if not matched:
        for native, diffusers in _NATIVE_PREFIX_MAP:
            if k.startswith(native):
                k = diffusers + k[len(native):]
                break

    for old, new in _ATTR_MAP:
        if old in k:
            k = k.replace(old, new)
            break

    if k.endswith(".lora_down.weight"):
        k = k[:-len(".lora_down.weight")] + ".lora_A.weight"
    elif k.endswith(".lora_up.weight"):
        k = k[:-len(".lora_up.weight")] + ".lora_B.weight"

    return k


def _convert_krea2_native_to_diffusers(src_path, dst_path):
    print(f"[LoRA] Converting native Krea 2 format: {os.path.basename(src_path)}")
    state_dict = _st_load(src_path)
    out, skipped = {}, []
    for key, tensor in state_dict.items():
        new_key = _convert_native_key(key)
        if new_key is None:
            skipped.append(key)
        else:
            out[new_key] = tensor
    if skipped:
        print(f"[LoRA] Skipped {len(skipped)} DoRA/unsupported keys")
    _st_save(out, dst_path)
    print(f"[LoRA] Conversion done: {len(out)} keys written to {os.path.basename(dst_path)}")


# ─────────────────────────────────────────────────────────────────────────────

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
        try:
            if source.startswith("/") or source.startswith("."):
                pipe.load_lora_weights(
                    os.path.dirname(source),
                    weight_name=os.path.basename(source),
                    adapter_name="active",
                )
            else:
                pipe.load_lora_weights(source, weight_name=weight_name, adapter_name="active")
        except RuntimeError as e:
            if "size mismatch" in str(e):
                raise gr.Error(
                    f"LoRA '{lora_name}' is incompatible with Krea 2 Turbo (architecture mismatch). "
                    "Only LoRAs trained on Krea 2 or Krea 2 Turbo are supported."
                ) from e
            raise gr.Error(f"Failed to load LoRA '{lora_name}': {e}") from e
        _current_lora = lora_name
    pipe.set_adapters(["active"], adapter_weights=[float(lora_strength)])


def upload_lora(file):
    if file is None:
        return gr.update(), ""
    basename = os.path.basename(file)
    if not basename.endswith(".safetensors"):
        raise gr.Error("Only .safetensors files are supported.")

    state_dict = _st_load(file)
    is_native = any(k.startswith("diffusion_model.") for k in state_dict.keys())
    del state_dict

    if is_native:
        converted_name = basename.removesuffix(".safetensors") + "_diffusers.safetensors"
        dest = os.path.join(CUSTOM_LORA_DIR, converted_name)
        try:
            _convert_krea2_native_to_diffusers(file, dest)
        except Exception as e:
            raise gr.Error(f"Conversion failed: {e}") from e
        basename = converted_name
    else:
        dest = os.path.join(CUSTOM_LORA_DIR, basename)
        shutil.copy2(file, dest)

    display_name = f"Custom: {basename.removesuffix('.safetensors')}"
    choices = _all_lora_choices()
    suffix = " (auto-converted from native format)" if is_native else ""
    return gr.update(choices=choices, value=display_name), f"Uploaded: {basename}{suffix}"


def save_custom_lora(lora_name, new_name, new_trigger):
    new_name = new_name.strip()
    new_trigger = new_trigger.strip()
    if not new_name:
        raise gr.Error("Name cannot be empty.")

    custom = _load_custom_loras()
    if lora_name not in custom:
        raise gr.Error(f"LoRA '{lora_name}' not found.")

    _, weight_name, _ = custom[lora_name]
    meta = _load_custom_metadata()
    meta[weight_name] = {"name": new_name, "trigger": new_trigger}
    _save_custom_metadata(meta)

    global _current_lora
    if _current_lora == lora_name:
        _current_lora = new_name

    choices = _all_lora_choices()
    return gr.update(choices=choices, value=new_name), "Saved."


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

    all_loras = {**BUILTIN_LORAS, **_load_custom_loras()}
    if lora_name != "None" and lora_name in all_loras:
        trigger = all_loras[lora_name][2]
        if trigger and trigger not in prompt:
            prompt = f"{trigger}, {prompt}"

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

    from datetime import datetime
    filename = os.path.join(IMAGES_DIR, datetime.now().strftime("%Y-%m-%d_%H-%M-%S") + ".png")
    image.save(filename)

    return image, seed


def on_resolution_change(label):
    w, h = RESOLUTIONS[label]
    return gr.update(value=w), gr.update(value=h)


def on_lora_change(lora_name):
    all_loras = {**BUILTIN_LORAS, **_load_custom_loras()}
    entry = all_loras.get(lora_name)
    trigger = entry[2] if entry else ""
    is_custom = _is_custom(lora_name) and lora_name in all_loras
    name_val = lora_name if is_custom else ""
    trigger_val = trigger if is_custom else ""
    return (
        trigger,
        gr.update(visible=is_custom),
        gr.update(value=name_val),
        gr.update(value=trigger_val),
        "",
    )


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
                    label="Trigger phrase (auto-added to prompt)",
                    interactive=False,
                )

                with gr.Group(visible=False) as custom_editor:
                    gr.Markdown("**Edit custom LoRA**")
                    custom_name_edit = gr.Textbox(label="Name", interactive=True)
                    custom_trigger_edit = gr.Textbox(label="Trigger phrase", interactive=True)
                    with gr.Row():
                        save_btn = gr.Button("Save", size="sm", variant="primary")
                        save_status = gr.Textbox(label="", interactive=False, scale=3)

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
    lora_name.change(
        on_lora_change, lora_name,
        [lora_trigger, custom_editor, custom_name_edit, custom_trigger_edit, save_status],
    )
    lora_upload.change(upload_lora, lora_upload, [lora_name, upload_status])
    save_btn.click(
        save_custom_lora,
        [lora_name, custom_name_edit, custom_trigger_edit],
        [lora_name, save_status],
    )

    inputs = [
        prompt, negative_prompt, lora_name, lora_strength,
        steps, guidance, width, height, seed, randomize,
    ]
    run_btn.click(generate, inputs, [output, seed])
    prompt.submit(generate, inputs, [output, seed])

demo.launch(server_name="0.0.0.0")
