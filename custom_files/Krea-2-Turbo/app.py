# Krea 2 is licensed under the Krea 2 Community License Agreement.

import os
import json
import shutil
import random
from datetime import datetime
import numpy as np
import torch
from torch.nn.attention import sdpa_kernel, SDPBackend
import gradio as gr
from PIL import Image
from safetensors.torch import load_file as _st_load, save_file as _st_save
from huggingface_hub import hf_hub_download

try:
    import spaces
except ImportError:
    spaces = type('', (), {'GPU': lambda *a, **kw: lambda f: f})()

from diffusers import Krea2Pipeline, Krea2Transformer2DModel, BitsAndBytesConfig
from diffusers.pipelines.krea2.pipeline_krea2 import retrieve_timesteps
from diffusers.pipelines.stable_diffusion.safety_checker import StableDiffusionSafetyChecker
from transformers import CLIPImageProcessor, AutoProcessor

DTYPE = torch.bfloat16

VRAM_HEADROOM_BYTES = int(os.environ.get("KREA_VRAM_HEADROOM_MB", "0")) * 1024 ** 2

if VRAM_HEADROOM_BYTES > 0 and torch.cuda.is_available():
    _total = torch.cuda.get_device_properties(0).total_memory
    _fraction = max(0.05, (_total - VRAM_HEADROOM_BYTES) / _total)
    torch.cuda.set_per_process_memory_fraction(_fraction)
    print(
        f"VRAM cap: {_fraction * _total / 1024 ** 3:.2f} GiB of "
        f"{_total / 1024 ** 3:.2f} GiB "
        f"({VRAM_HEADROOM_BYTES // 1024 ** 2} MiB left for the driver)",
        flush=True,
    )
TURBO_REPO = "krea/Krea-2-Turbo"
MAX_SEED = 2**31 - 1
CUSTOM_LORA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "loras")
CUSTOM_METADATA_FILE = os.path.join(CUSTOM_LORA_DIR, "metadata.json")
IMAGES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "images")
os.makedirs(IMAGES_DIR, exist_ok=True)

# or endorsed by Krea.ai. Distributed under the Krea 2 Community License.
EDIT_LORA_REPO = "conradlocke/krea2-identity-edit"
EDIT_LORA_WEIGHT = "krea2_identity_edit_v1_2.safetensors"
EDIT_ADAPTER = "identity_edit"
STYLE_ADAPTER = "active"

EDIT_DEFAULT_STEPS = 8          # card: Turbo, 8-12 steps
EDIT_DEFAULT_GUIDANCE = 0.0     # card: CFG 1.0 == guidance disabled (Krea convention)
EDIT_DEFAULT_GROUNDING_PX = 768  # card: v1.1 trained range 384-768
EDIT_MAX_MEGAPIXELS = 1.0       # card: <=2MP; two-ref prefers 1-1.5MP. The edit path



_GROUNDED_SYSTEM = (
    "<|im_start|>system\nDescribe the image by detailing the color, shape, size, "
    "texture, quantity, text, spatial relationships of the objects and background:"
    "<|im_end|>\n<|im_start|>user\n"
)
_VISION_BLOCK = "<|vision_start|><|image_pad|><|vision_end|>"
GROUNDED_TEMPLATE = _GROUNDED_SYSTEM + _VISION_BLOCK + "{}<|im_end|>\n<|im_start|>assistant\n"
GROUNDED_TEMPLATE_2REF = (
    _GROUNDED_SYSTEM + _VISION_BLOCK + _VISION_BLOCK + "{}<|im_end|>\n<|im_start|>assistant\n"
)

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

try:
    processor = AutoProcessor.from_pretrained("Qwen/Qwen3-VL-4B-Instruct")
except Exception as e:
    print(f"[warn] could not load Qwen3-VL processor, Identity Edit will be text-only: {e}")
    processor = None

_LATENTS_MEAN = torch.tensor(pipe.vae.config.latents_mean).view(1, pipe.vae.config.z_dim, 1, 1, 1)
_LATENTS_STD = torch.tensor(pipe.vae.config.latents_std).view(1, pipe.vae.config.z_dim, 1, 1, 1)

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
        if not f.endswith(".safetensors") or f.startswith("."):
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


_current_lora = None


def _loaded_adapters():
    try:
        return set(pipe.get_list_adapters().get("transformer", []))
    except Exception:
        return set()


def _set_active_adapters(names, weights=None):
    """Select which loaded adapters are live. Empty list disables all of them.

    The Generate and Identity Edit tabs keep separate adapters loaded at the same
    time, so each call must claim the ones it wants rather than assume.
    """
    if not names:
        if _loaded_adapters():
            try:
                pipe.transformer.disable_adapters()
            except (ValueError, RuntimeError):
                pass
        return
    pipe.transformer.enable_adapters()
    pipe.set_adapters(names, adapter_weights=weights)


def _apply_lora(lora_name, lora_strength):
    global _current_lora

    if lora_name == "None":
        if _current_lora is not None:
            pipe.delete_adapters(STYLE_ADAPTER)
            _current_lora = None
        _set_active_adapters([])
        return

    all_loras = {**BUILTIN_LORAS, **_load_custom_loras()}
    if lora_name not in all_loras:
        raise gr.Error(f"Unknown LoRA: {lora_name}")

    source, weight_name, _ = all_loras[lora_name]
    if _current_lora != lora_name:
        if _current_lora is not None:
            pipe.delete_adapters(STYLE_ADAPTER)
            _current_lora = None
        try:
            if source.startswith("/") or source.startswith("."):
                pipe.load_lora_weights(
                    os.path.dirname(source),
                    weight_name=os.path.basename(source),
                    adapter_name=STYLE_ADAPTER,
                )
            else:
                pipe.load_lora_weights(source, weight_name=weight_name, adapter_name=STYLE_ADAPTER)
        except RuntimeError as e:
            if "size mismatch" in str(e):
                raise gr.Error(
                    f"LoRA '{lora_name}' is incompatible with Krea 2 Turbo (architecture mismatch). "
                    "Only LoRAs trained on Krea 2 or Krea 2 Turbo are supported."
                ) from e
            raise gr.Error(f"Failed to load LoRA '{lora_name}': {e}") from e
        _current_lora = lora_name
    _set_active_adapters([STYLE_ADAPTER], [float(lora_strength)])


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

    gr.Info(f"Saved '{new_name}'.")
    return gr.update(choices=_all_lora_choices(), value=new_name)


def delete_custom_lora(lora_name):
    custom = _load_custom_loras()
    if lora_name not in custom:
        raise gr.Error(f"LoRA '{lora_name}' not found.")

    path, weight_name, _ = custom[lora_name]

    global _current_lora
    if _current_lora == lora_name:
        pipe.delete_adapters(STYLE_ADAPTER)
        _set_active_adapters([])
        _current_lora = None

    os.remove(path)
    meta = _load_custom_metadata()
    if meta.pop(weight_name, None) is not None:
        _save_custom_metadata(meta)

    gr.Info(f"Deleted '{lora_name}'.")
    return gr.update(choices=_all_lora_choices(), value="None")


def _ensure_on_device(module):
    """Fire accelerate's cpu-offload hook by hand.

    enable_model_cpu_offload() hooks the module's `forward`, but the edit path
    calls the transformer's submodules directly, so `forward` never runs and the
    weights would stay on CPU. This mirrors diffusers' own @apply_forward_hook.
    """
    hook = getattr(module, "_hf_hook", None)
    if hook is not None and hasattr(hook, "pre_forward"):
        hook.pre_forward(module)


def _ensure_identity_lora():
    """Load the identity-edit LoRA on first use (kept alongside the style adapter)."""
    if EDIT_ADAPTER in _loaded_adapters():
        return
    print(f"[Identity Edit] Downloading {EDIT_LORA_REPO}/{EDIT_LORA_WEIGHT} ...")
    src = hf_hub_download(EDIT_LORA_REPO, EDIT_LORA_WEIGHT)
    dst = os.path.join(CUSTOM_LORA_DIR, ".identity_edit_diffusers.safetensors")
    if not os.path.exists(dst):
        _convert_krea2_native_to_diffusers(src, dst)
    pipe.load_lora_weights(
        os.path.dirname(dst), weight_name=os.path.basename(dst), adapter_name=EDIT_ADAPTER
    )
    print("[Identity Edit] LoRA ready.")


def _grounded_encode(instruction, images, grounding_px):
    """Encode the instruction grounded on the source image(s) through Qwen3-VL.

    Returns (prompt_embeds, prompt_embeds_mask) shaped like the diffusers Krea 2
    text conditioning: (1, seq, num_text_layers, dim) and (1, seq).
    """
    device = pipe._execution_device
    select_layers = pipe.text_encoder_select_layers
    prefix_idx = pipe.prompt_template_encode_start_idx  # drop the system prefix

    prepped = []
    for img in images:
        img = img.convert("RGB")
        if grounding_px and max(img.size) > grounding_px:
            s = grounding_px / max(img.size)
            img = img.resize(
                (max(16, round(img.size[0] * s)), max(16, round(img.size[1] * s))),
                Image.LANCZOS,
            )
        prepped.append(img)

    template = GROUNDED_TEMPLATE_2REF if len(prepped) > 1 else GROUNDED_TEMPLATE
    inputs = processor(
        text=[template.format(instruction or "")],
        images=prepped,
        padding=True,
        return_tensors="pt",
    ).to(device)

    te_kwargs = dict(
        input_ids=inputs["input_ids"],
        attention_mask=inputs.get("attention_mask"),
        pixel_values=inputs.get("pixel_values"),
        image_grid_thw=inputs.get("image_grid_thw"),
        output_hidden_states=True,
    )
    if inputs.get("mm_token_type_ids") is not None:
        te_kwargs["mm_token_type_ids"] = inputs["mm_token_type_ids"]

    outputs = pipe.text_encoder(**te_kwargs)
    hidden_states = torch.stack([outputs.hidden_states[i] for i in select_layers], dim=2)

    attention_mask = inputs.get("attention_mask")
    if attention_mask is None:
        attention_mask = torch.ones(hidden_states.shape[:2], device=device, dtype=torch.bool)
    else:
        attention_mask = attention_mask.bool()

    return hidden_states[:, prefix_idx:].to(DTYPE), attention_mask[:, prefix_idx:]


def _encode_source_latent(source, height, width):
    """VAE-encode a source image to a packed, normalized latent block matching the
    target grid, ready to prepend to the transformer sequence."""
    device = pipe._execution_device
    px = pipe.image_processor.preprocess(source.convert("RGB"), height=height, width=width)
    px = px.unsqueeze(2).to(device=device, dtype=pipe.vae.dtype)  # (B,C,1,H,W)

    latent = pipe.vae.encode(px).latent_dist.mode()  # unnormalized
    mean = _LATENTS_MEAN.to(latent.device, latent.dtype)
    std = _LATENTS_STD.to(latent.device, latent.dtype)
    latent = ((latent - mean) / std)[:, :, 0]  # normalized, (B, z, lh, lw)

    b, c, lh, lw = latent.shape
    return pipe._pack_latents(latent, b, c, lh, lw).to(DTYPE)


def _edit_position_ids(text_seq_len, grid_h, grid_w, n_src, device):
    """Build (text + n_src*grid + grid, 3) rotary coords:
    text @ (0,0,0); each source block @ frame=i+1 with (h,w); target @ frame=0."""
    text_ids = torch.zeros(text_seq_len, 3, device=device)

    def _img_ids(frame):
        ids = torch.zeros(grid_h, grid_w, 3, device=device)
        ids[..., 0] = frame
        ids[..., 1] = torch.arange(grid_h, device=device)[:, None]
        ids[..., 2] = torch.arange(grid_w, device=device)[None, :]
        return ids.reshape(grid_h * grid_w, 3)

    blocks = [text_ids]
    blocks += [_img_ids(i + 1) for i in range(n_src)]  # sources frame=1..N
    blocks += [_img_ids(0)]                            # target frame=0
    return torch.cat(blocks, dim=0)


def _edit_transformer_forward(latents, src_packed, prompt_embeds, prompt_mask,
                              timestep, position_ids):
    """Krea 2 transformer with the source latent block(s) prepended, keeping only
    the target tokens out."""
    m = pipe.transformer
    combined_img = torch.cat(src_packed + [latents], dim=1)  # [sources | target]

    temb = m.time_embed(timestep, dtype=latents.dtype)
    temb_mod = m.time_mod_proj(torch.nn.functional.gelu(temb, approximate="tanh"))

    text_attn_mask = prompt_mask[:, None, None, :] if prompt_mask is not None else None
    enc = m.txt_in(m.text_fusion(prompt_embeds, attention_mask=text_attn_mask))

    hidden = torch.cat([enc, m.img_in(combined_img)], dim=1)  # [text | sources | target]
    image_rotary_emb = m.rotary_emb(position_ids)

    with sdpa_kernel([SDPBackend.FLASH_ATTENTION, SDPBackend.EFFICIENT_ATTENTION]):
        for block in m.transformer_blocks:
            hidden = block(hidden, temb_mod, image_rotary_emb, None)

    tgt_len = latents.shape[1]
    hidden = hidden[:, enc.shape[1]:]  # drop text -> [sources | target]
    hidden = hidden[:, -tgt_len:]      # keep target tokens only
    return m.final_layer(hidden, temb)


def _target_size(source, max_megapixels):
    """Match the output AR to the source (card requirement) and cap the pixel count,
    snapping each side to a multiple of vae_scale_factor * patch_size."""
    multiple = pipe.vae_scale_factor * pipe.patch_size
    w, h = source.size
    mp = (w * h) / 1e6
    if mp > max_megapixels:
        s = (max_megapixels / mp) ** 0.5
        w, h = round(w * s), round(h * s)
    w = max(multiple, (w // multiple) * multiple)
    h = max(multiple, (h // multiple) * multiple)
    return h, w


@torch.no_grad()
def edit(
    source_image,
    person_image=None,
    instruction="",
    grounding_px=EDIT_DEFAULT_GROUNDING_PX,
    steps=EDIT_DEFAULT_STEPS,
    guidance=EDIT_DEFAULT_GUIDANCE,
    seed=0,
    randomize=True,
    progress=gr.Progress(track_tqdm=True),
):
    if source_image is None:
        raise gr.Error("Upload a source image to edit.")
    if not instruction or not instruction.strip():
        raise gr.Error("Describe the edit you want.")
    if processor is None:
        raise gr.Error(
            "The Qwen3-VL processor failed to load, so the image-grounded encode "
            "is unavailable. Identity Edit needs it."
        )

    instruction = instruction.strip()
    if randomize:
        seed = random.randint(0, MAX_SEED)
    seed = int(seed)

    def _as_pil(img):
        return img if isinstance(img, Image.Image) else Image.fromarray(img)

    sources = [_as_pil(source_image).convert("RGB")]
    if person_image is not None:
        sources.append(_as_pil(person_image).convert("RGB"))

    device = pipe._execution_device
    _ensure_identity_lora()
    _set_active_adapters([EDIT_ADAPTER], [1.0])  # card: LoRA strength 1.0

    height, width = _target_size(sources[0], EDIT_MAX_MEGAPIXELS)

    prompt_embeds, prompt_mask = _grounded_encode(instruction, sources, int(grounding_px))
    do_cfg = float(guidance) > 0
    if do_cfg:
        neg_embeds, neg_mask = _grounded_encode("", sources, int(grounding_px))

    src_packed = [_encode_source_latent(s, height, width) for s in sources]

    num_channels_latents = pipe.transformer.config.in_channels // (pipe.patch_size ** 2)
    generator = torch.Generator(device=device).manual_seed(seed)
    latents = pipe.prepare_latents(
        1, num_channels_latents, height, width, DTYPE, device, generator, None
    )

    grid_h = height // (pipe.vae_scale_factor * pipe.patch_size)
    grid_w = width // (pipe.vae_scale_factor * pipe.patch_size)
    position_ids = _edit_position_ids(prompt_embeds.shape[1], grid_h, grid_w, len(sources), device)
    if do_cfg:
        neg_position_ids = _edit_position_ids(
            neg_embeds.shape[1], grid_h, grid_w, len(sources), device
        )

    sigmas = np.linspace(1.0, 1 / int(steps), int(steps))
    timesteps, _ = retrieve_timesteps(pipe.scheduler, int(steps), device, sigmas=sigmas, mu=1.15)

    _ensure_on_device(pipe.transformer)
    pipe.scheduler.set_begin_index(0)
    try:
        for t in progress.tqdm(timesteps, desc="Editing"):
            timestep = (t / pipe.scheduler.config.num_train_timesteps).expand(
                latents.shape[0]
            ).to(latents.dtype)

            noise_pred = _edit_transformer_forward(
                latents, src_packed, prompt_embeds, prompt_mask, timestep, position_ids
            )
            if do_cfg:
                neg_pred = _edit_transformer_forward(
                    latents, src_packed, neg_embeds, neg_mask, timestep, neg_position_ids
                )
                noise_pred = noise_pred + float(guidance) * (noise_pred - neg_pred)

            latents = pipe.scheduler.step(noise_pred, t, latents, return_dict=False)[0]

        latents = pipe._unpack_latents(latents, height, width).to(pipe.vae.dtype)
        mean = _LATENTS_MEAN.to(latents.device, latents.dtype)
        std = _LATENTS_STD.to(latents.device, latents.dtype)
        image = pipe.vae.decode(latents * std + mean, return_dict=False)[0][:, :, 0]
        image = pipe.image_processor.postprocess(image, output_type="pil")[0]
    except torch.OutOfMemoryError as exc:
        torch.cuda.empty_cache()
        raise gr.Error(
            f"Ran out of VRAM editing at {width}x{height}. Use a smaller source image"
            + (" or drop the second reference." if len(sources) > 1 else ".")
        ) from exc

    # Krea 2 Community License 4.2: deployments must moderate generated content.
    if _check_nsfw(image):
        raise gr.Error("Content blocked by safety filter (NSFW detected).")

    image.save(os.path.join(IMAGES_DIR, datetime.now().strftime("%Y-%m-%d_%H-%M-%S") + ".png"))
    return image, seed








def _encode_reference_latent(image):
    """VAE-encode the reference at its own size; returns packed tokens and grid."""
    unit = pipe.vae_scale_factor * pipe.patch_size
    w = max(unit, (image.width // unit) * unit)
    h = max(unit, (image.height // unit) * unit)
    packed = _encode_source_latent(image.resize((w, h), Image.LANCZOS), h, w)
    return packed, h // unit, w // unit


def _registered_position_ids(text_seq_len, grid_h, grid_w, ref_h, ref_w, bbox_norm, device):
    """Rotary coords with the reference registered onto the target grid.

    This is the whole difference from the identity-edit path: instead of the
    reference occupying its own grid starting at (0,0), its rows and columns are
    mapped onto the target grid cells its bounding box covers. It keeps frame
    axis 1, so it is still a reference rather than part of the target.
    """
    text_ids = torch.zeros(text_seq_len, 3, device=device)

    x0, y0, x1, y1 = (float(v) for v in bbox_norm)
    ref_ids = torch.zeros(ref_h, ref_w, 3, device=device)
    ref_ids[..., 0] = 1
    ys = y0 * grid_h + (torch.arange(ref_h, device=device) + 0.5) * ((y1 - y0) * grid_h / ref_h) - 0.5
    xs = x0 * grid_w + (torch.arange(ref_w, device=device) + 0.5) * ((x1 - x0) * grid_w / ref_w) - 0.5
    ref_ids[..., 1] = ys[:, None]
    ref_ids[..., 2] = xs[None, :]

    tgt_ids = torch.zeros(grid_h, grid_w, 3, device=device)
    tgt_ids[..., 1] = torch.arange(grid_h, device=device)[:, None]
    tgt_ids[..., 2] = torch.arange(grid_w, device=device)[None, :]

    return torch.cat([text_ids, ref_ids.reshape(-1, 3), tgt_ids.reshape(-1, 3)], dim=0)




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

    image.save(os.path.join(IMAGES_DIR, datetime.now().strftime("%Y-%m-%d_%H-%M-%S") + ".png"))

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
    )


with gr.Blocks(title="Krea 2 Turbo + Edit") as demo:
    gr.Markdown("# Krea 2 Turbo + Edit\nText-to-image generation and identity-preserving editing (4-bit NF4 quantized)")
    gr.Markdown(
        "Krea 2 and the included LoRAs are licensed under the "
        "[Krea 2 Community License Agreement](https://krea.ai/krea-2-licensing).\n\n"
        "As required by the license (Section 4.2), generated images are checked by a "
        "[safety filter](https://huggingface.co/CompVis/stable-diffusion-safety-checker) "
        "to prevent NSFW content.\n\n"
        "Images produced here are **generated by artificial intelligence**. Where law, "
        "regulation or platform policy requires it, disclose that when publishing them "
        "(Section 4.3).\n\n"
        "Commercial use is allowed only below **1,000,000 USD** of annual company-wide "
        "revenue; above that an Enterprise License from Krea is required (Section 2.3)."
    )

    with gr.Tab("Generate"):
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
                            delete_btn = gr.Button("Delete", size="sm", variant="stop")

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
                        width = gr.Slider(512, 1536, value=1024, step=16, label="Width")
                        height = gr.Slider(512, 1536, value=1024, step=16, label="Height")
                    with gr.Row():
                        seed = gr.Slider(0, MAX_SEED, value=0, step=1, label="Seed")
                        randomize = gr.Checkbox(value=True, label="Randomize seed")

            with gr.Column(scale=6):
                output = gr.Image(label="Result", format="png")

        resolution.change(on_resolution_change, resolution, [width, height])
        lora_name.change(
            on_lora_change, lora_name,
            [lora_trigger, custom_editor, custom_name_edit, custom_trigger_edit],
        )
        lora_upload.change(upload_lora, lora_upload, [lora_name, upload_status])
        save_btn.click(
            save_custom_lora,
            [lora_name, custom_name_edit, custom_trigger_edit],
            lora_name,
        )
        delete_btn.click(delete_custom_lora, lora_name, lora_name)

        inputs = [
            prompt, negative_prompt, lora_name, lora_strength,
            steps, guidance, width, height, seed, randomize,
        ]
        run_btn.click(generate, inputs, [output, seed])
        prompt.submit(generate, inputs, [output, seed])

    with gr.Tab("Identity Edit"):
        gr.Markdown(
            "Instruction-based, identity-preserving editing with the community LoRA "
            "[`conradlocke/krea2-identity-edit`](https://huggingface.co/conradlocke/krea2-identity-edit). "
            "Its dual-conditioning recipe is reimplemented in diffusers after the reference "
            "[ComfyUI-Krea2Edit](https://github.com/lbouaraba/comfyui-krea2edit) node pack.\n\n"
            "Leave the second image empty to edit a single photo."
        )

        with gr.Row(equal_height=False):
            with gr.Column(scale=5):
                edit_source = gr.Image(
                    label="Image 1 — source / scene", type="pil", height=280
                )
                edit_person = gr.Image(
                    label="Image 2 — person (optional, for combining two photos)",
                    type="pil",
                    height=280,
                )
                edit_instruction = gr.Textbox(
                    label="Edit instruction",
                    lines=3,
                    placeholder="e.g. create a photo of this person at a night market",
                )
                edit_btn = gr.Button("Edit", variant="primary")

                with gr.Accordion("Advanced", open=False):
                    edit_grounding_px = gr.Slider(
                        384, 1536, value=EDIT_DEFAULT_GROUNDING_PX, step=64,
                        label="Grounding resolution (px)",
                        info="Lower = stronger edit adherence; higher = stronger likeness. "
                             "Trained range is 384-768. Duplicated/split compositions mean "
                             "it is set too high.",
                    )
                    edit_steps = gr.Slider(
                        4, 28, value=EDIT_DEFAULT_STEPS, step=1, label="Steps",
                        info="8 favors composition, 12 favors face detail; ~10 balances.",
                    )
                    edit_guidance = gr.Slider(
                        0.0, 5.0, value=EDIT_DEFAULT_GUIDANCE, step=0.5,
                        label="Guidance scale",
                        info="0 disables guidance (Turbo default). Raise to ~3 for "
                             "removals and large deletions. Doubles the time per step.",
                    )
                    with gr.Row():
                        edit_seed = gr.Slider(0, MAX_SEED, value=0, step=1, label="Seed")
                        edit_randomize = gr.Checkbox(value=True, label="Randomize seed")

            with gr.Column(scale=6):
                edit_output = gr.Image(label="Edited image", format="png")

        edit_inputs = [
            edit_source, edit_person, edit_instruction, edit_grounding_px,
            edit_steps, edit_guidance, edit_seed, edit_randomize,
        ]
        edit_btn.click(edit, edit_inputs, [edit_output, edit_seed])
        edit_instruction.submit(edit, edit_inputs, [edit_output, edit_seed])


demo.launch(server_name="0.0.0.0")
