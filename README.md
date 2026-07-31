# ROCm-AI-Installer
Installation scripts for an AI applications using ROCm on Linux.

## Info:
[![Version](https://img.shields.io/badge/Version-17-orange.svg)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)

![ROCm](https://img.shields.io/badge/ROCm-7.2.4-red.svg)

> [!Note]
> From version 10.0, the script is distribution-independent thanks to the use of Podman.<br>
> All you need is a correctly configured <b>Podman</b> and <b>amdgpu</b>.

> [!Important]
> All models and applications are tested on a GPU with 24GB of VRAM.<br>
> Some applications may not work on GPUs with less VRAM.

### Test platform:
|Name|Info|
|:---|:---|
|CPU|AMD Ryzen 9 9950X3D|
|GPU|AMD Radeon 7900XTX|
|RAM|64GB DDR5 6600MHz|
|Motherboard|Gigabyte X870 AORUS ELITE WIFI7 (BIOS F8)|
|OS|Debian 13.6|
|Kernel|6.12.96+deb13-amd64|

###  Text generation:
|Name|Links|Additional information|
|:---|:---|:---|
|SillyTavern|https://github.com/SillyTavern/SillyTavern||
|llama.cpp|https://github.com/ggml-org/llama.cpp<br> https://huggingface.co/unsloth/gemma-4-12b-it-GGUF|1. Runs in <b>router mode</b> - <b>pick/switch models from the WebUI</b> without restarting (see <i>Switching models</i> below).<br> 2. By default downloads the <b>gemma-4-12b-it Q8_0</b> model into <b>user-models/</b>.<br> 3. A Vulkan version is also available.|
|turboquant-rocm-llamacpp|https://github.com/jagsan-cyber/turboquant-rocm-llamacpp<br> https://huggingface.co/unsloth/gemma-4-12b-it-GGUF|1. TurboQuant 4-bit KV-cache compression (q4_0).<br> 2. <b>Router mode</b> - pick/switch models from the WebUI (see <i>Switching models</i> below).<br> 3. By default downloads the <b>gemma-4-12b-it Q8_0</b> model into <b>user-models/</b>.<br> 4. ROCm only.|
|Colibri|https://justvugg.github.io/colibri/<br> https://github.com/noobdev-ph/colibri<br> https://huggingface.co/mateogrgic/GLM-5.2-colibri-int4-with-int8-mtp|1. Runs <b>GLM-5.2 (744B MoE)</b> on consumer hardware by streaming expert weights from disk (tiered RAM/disk/VRAM).<br> 2. Pure C engine with a <b>ROCm/HIP</b> GPU backend (built by default).<br> 3. Launches the <b>web dashboard</b> (live metrics, expert-routing viz, 3D expert atlas) on <b>port 8000</b>.<br> 4. Downloads a <b>~372 GB</b> int4 model (no HuggingFace token). Needs <b>~372 GB free disk + 25 GB RAM</b>.<br> 5. gfx1100/RDNA3 builds and runs (no WMMA), disk-bound - throughput is a few tok/s at best.|
|vLLM Gemma 4|https://github.com/vllm-project/vllm<br> https://github.com/0xSero/turboquant<br> https://huggingface.co/google/gemma-4-31B-it|1. Serves <b>Gemma 4 31B</b> over an OpenAI-compatible API on <b>port 8000</b>, with a two-pane chat UI on <b>port 8080</b> - vLLM itself has no WebUI, only <code>/docs</code>.<br> 2. The model is quantized <b>during installation</b> to <b>symmetric 4-bit W4A16, group 128</b> (17.9 GB; see <code>custom_files/gemma4-quant/</code>) - no published 4-bit Gemma 4 has that combination, and every alternative costs context.<br> 3. <b>Compressed KV cache</b> (4-bit keys, 2-bit values) applied only to the ten full-attention layers - the 50 sliding ones are capped by a 1024-token window, so compressing them saves nothing and breaks the window. Those ten have no <code>v_proj</code> at all, so K is rebuilt from the shared projection instead of stored: <b>7.5 KB/token</b> against fp8's 51.6.<br> 4. On 24 GB: <b>150 000 tokens</b> in one session, or <b>two concurrent sessions of 150 000</b> each, both with full needle recall at five depths. Plain fp8 fits 111k.<br> 5. A fused Triton kernel (dequantise + RMSNorm + RoPE in one pass) nearly doubles generation: <b>22.7 / 12.2 / 7.5 tok/s</b> at 2k / 32k / 128k of context.<br> 6. <b>Prefix caching must stay off</b> - a cache hit skips the forward pass, so the compressed store is never filled and the model answers with no context at all. The run script already disables it.<br> 7. Long prompts take a while before the first token (~57 s at 32k, ~6 min at 128k); that is prefill, not a hang. Full write-up in <code>.images/VLLM.md</code>.|

#### Switching models (llama.cpp / llama.cpp Vulkan / turboquant-rocm-llamacpp)

These three run `llama-server` in **router mode**, so you can keep several models side by side and switch between them from the WebUI without restarting the server.

1. Drop your `.gguf` model files into the app's `user-models/` folder inside the container:
```bash
podman cp my-model.Q4_K_M.gguf rocm:/AI/llama.cpp/user-models/
```
(use `/AI/llama.cpp-vulkan/user-models/` or `/AI/turboquant-rocm-llamacpp/user-models/` for the other variants).

2. Open the WebUI (`http://localhost:8080`) and choose the model from the **model selector**, or send an OpenAI-style request with the `"model"` field set to the file name. `GET /v1/models` lists everything in the folder.

3. Only **one model stays loaded at a time** (`--models-max 1`): loading another automatically unloads the previous one and frees its VRAM. The conversation history is kept by the client and re-processed by the newly selected model.

#### SillyTavern Extensions:
|Name|Link|Additional information|
|:---|:---|:---|
|WhisperSpeech web UI|https://github.com/Mateusz-Dera/whisperspeech-webui|Install and run WhisperSpeech web UI first.|

###  Image & video generation:
|Name|Links|Additional information|
|:---|:---|:---|
|ComfyUI|https://github.com/comfyanonymous/ComfyUI<br> https://github.com/city96/ComfyUI-GGUF|Workflows templates are in the workflows folder.<br> Extension manager is installed by default.<br> <b>ComfyUI-GGUF</b> is installed by default.|
|Krea 2 Turbo + Edit|https://github.com/krea-ai/krea-2<br> https://huggingface.co/krea/Krea-2-Turbo<br> https://huggingface.co/collections/krea/krea-2-loras<br> https://huggingface.co/conradlocke/krea2-identity-edit<br> https://github.com/lbouaraba/comfyui-krea2edit|1. 4-bit NF4 quantized to fit 24 GB VRAM<br> 2. Turbo model (8 steps)<br> 3. 9 official style LoRAs available<br> 4. Custom LoRA upload supported (native Krea 2 LoRAs are auto-converted to diffusers format)<br> 5. <b>Identity Edit</b> tab: instruction-based, identity-preserving editing of a single photo, or combining two photos (scene + person)<br> 6. Identity Edit uses the <b>unofficial community LoRA</b> <a href="https://huggingface.co/conradlocke/krea2-identity-edit">conradlocke/krea2-identity-edit</a> <br> 7. Krea 2 and the LoRAs are licensed under the <a href="https://krea.ai/krea-2-licensing">Krea 2 Community License Agreement</a>.|

#### ComfyUI Addons:
|Name|Link|Additional information|
|:---|:---|:---|
|Qwen-Image-2512-GGUF|https://huggingface.co/Qwen/Qwen-Image-2512<br>https://huggingface.co/unsloth/Qwen-Image-2512-GGUF<br> https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI<br> https://huggingface.co/Wuli-art/Qwen-Image-2512-Turbo-LoRA-2-Steps|Uses <b>Q5_0</b> quant.<br> Uses <b>2-step turbo LoRA</b>.|
|Qwen-Image-2511-Edit-GGUF|https://huggingface.co/Qwen/Qwen-Image-Edit-2511<br> https://huggingface.co/unsloth/Qwen-Image-Edit-2511-GGUF<br> https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI<br> https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning|Uses <b>Q5_0</b> quant.<br> Uses <b>4-step Lightning LoRA</b>|
|Z-Image-Turbo|https://huggingface.co/Tongyi-MAI/Z-Image-Turbo<br> https://huggingface.co/Comfy-Org/z_image_turbo||
|Z-Anime|https://huggingface.co/SeeSee21/Z-Anime<br> https://huggingface.co/Comfy-Org/z_image_turbo||
|Wan2.2-TI2V-5B|https://huggingface.co/Wan-AI/Wan2.2-TI2V-5B<br> https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged||

###  Fine-tuning:
|Name|Links|Additional information|
|:---|:---|:---|
|Unsloth|https://github.com/unslothai/unsloth<br> https://unsloth.ai/docs/basics/amd|1. LoRA / QLoRA / full fine-tuning + RL for LLMs - <b>2x faster, 70% less VRAM</b>. Exports to GGUF / LoRA / safetensors.<br> 2. Production-ready <b>AMD/ROCm</b> support (full RDNA3 / gfx1100), runs fully <b>locally</b> on the GPU.<br> 3. Launches <b>Unsloth Studio</b> (web UI for training + inference) on <b>port 8888</b>.<br> 4. CLI also available: <b>unsloth train / inference / chat / export</b>.|

###  Music generation:
|Name|Links|Additional information|
|:---|:---|:---|
|ACE-Step-1.5|https://github.com/ace-step/ACE-Step-1.5||

###  Voice generation:
|Name|Links|Additional information|
|:---|:---|:---|
|WhisperSpeech web UI|https://github.com/Mateusz-Dera/whisperspeech-webui<br> https://github.com/collabora/WhisperSpeech||
|Soprano|https://github.com/ekwek1/soprano<br> https://github.com/Mateusz-Dera/soprano-rocm|1. Uses my experimental fork for ROCm with vLLM|
|OmniVoice|https://github.com/k2-fsa/OmniVoice||

###  3D generation:
|Name|Links|Additional information|
|:---|:---|:---|
|PartCrafter|https://github.com/wgsxm/PartCrafter|1. Added custom simple UI.<br> 2. Uses a modified version of PyTorch Cluster for ROCm https://github.com/Mateusz-Dera/pytorch_cluster_rocm.|
|trellis2.c|https://github.com/Wimacs/trellis2.c|1. Pure C port (ggml backend, no PyTorch). Two install variants: <b>ROCm</b> (HIP/rocBLAS) and <b>Vulkan</b> (Mesa RADV, ROCm-independent).<br> 2. Both launch a native <b>raylib GUI</b> (trellis-gui): pick an image in the window, generate, and preview the 3D result. Exported GLBs go to the <b>output/</b> folder.<br> 3. Uses public <b>camenduru</b> weight mirrors - no HuggingFace token required.<br> 4. Speed on a 7900XTX (same image, res 512): <b>ROCm ~81s</b>, <b>Vulkan ~104s</b> (ROCm ~22% faster). Both slower than the PyTorch <b>TRELLIS.2_rocm</b> (~46s), but self-contained.|
|Pixal3D Experimental|https://github.com/Wimacs/trellis2.c<br> https://huggingface.co/TencentARC/Pixal3D<br> https://github.com/valeoai/NAF|1. The <b>Pixal3D</b> image-to-3D model running through trellis2.c's <b>ROCm/HIP</b> backend - higher fidelity than TRELLIS.2 but much heavier.<br> 2. <b>CLI only</b> (no GUI): <b>./run.sh [input_image] [output.glb]</b> from the <b>/AI/Pixal3D</b> folder; GLBs default to trellis2.c's <b>output/</b>.<br> 3. Downloads <b>~24 GB</b> of public weights (TencentARC/Pixal3D) plus the Apache-2.0 NAF checkpoint (auto-converted). No HuggingFace token.<br> 4. Only fits in 24 GB via a custom OOM patch (chunked attention + lazy sparse-decoder temporaries) and preset runtime flags. 1024_cascade only, <b>~9-10 min/asset</b> on a 7900XTX.|
|ARDY|https://github.com/nv-tlabs/ardy<br> https://huggingface.co/meta-llama/Meta-Llama-3-8B-Instruct|1. NVIDIA autoregressive-diffusion <b>interactive human/robot motion generation</b> from text + kinematic constraints (successor to Kimodo).<br> 2. Interactive <b>viser web demo</b> on <b>port 2333</b> (run.sh); a headless CLI (<b>scripts/generate.py</b>) is also available.<br> 3. Set <b>HuggingFace Token</b> in Variables and request access to <a href="https://huggingface.co/meta-llama/Meta-Llama-3-8B-Instruct">meta-llama/Meta-Llama-3-8B-Instruct</a> (LLM2Vec text encoder, runs on CPU).<br> 4. Checkpoints download automatically on first use.|
|TripoSplat|https://github.com/VAST-AI-Research/TripoSplat||
|AutoRemesher|https://github.com/huxingyi/autoremesher|1. <b>Not an AI model</b> - a classical (CPU/TBB) automatic quad-remeshing tool, added as a helper.<br> 2. Retopologizes the triangle-soup meshes from the 3D-generation apps (TripoSplat, Pixal3D, TRELLIS, trellis2.c, PartCrafter) into clean quad topology for animation/modeling.<br> 3. Qt5 <b>GUI</b> (run.sh) for interactive remeshing; a headless CLI is also available (<b>--input/--output/--target-quads</b>).|

## Instalation:

1\. Install Podman.

> [!Note]
> If you are using Debian 13.5, you can use <b>sudo apt-get update && sudo apt-get -y install podman podman-compose qemu-system</b> (should also work on Ubuntu 26.04)

2\. Make sure that <b>/dev/dri</b> and <b>/dev/kfd</b> are accessible.
```bash
ls /dev/dri
ls /dev/kfd
```

> [!Important]
> Your distribution must have <b>amdgpu</b> configured.

3\. Make sure that your user has permissions for the <b>video</b> and render <b>groups</b>.

```bash
sudo usermod -aG video,render $USER
```

> [!Important]
> If not, you need reboot after this step.

4\. Clone repository.
```bash
git clone https://github.com/Mateusz-Dera/ROCm-AI-Installer.git
```

5\. Run installer. 
```bash
./install.sh
```
6\. Set variables

> [!NOTE]
> By default, the script is configured for AMD Radeon 7900XTX.<br>
> For other cards and architectures, edit <b>GFX</b> and <b>HSA_OVERRIDE_GFX_VERSION</b>.

7\. Create a container if you are upgrading or running the script for the first time.

8\. Install the applications of your choice.

9\. Go to the application folder and run:
```bash
./run.sh
```

> [!NOTE]
> Everything is configured to start from the host side (You don't need to enter the container).

## Container:

### Checking the container
To check if the container is running:
```bash
podman ps
```

### Starting the container
If the container is not running, start it with:
```bash
podman start rocm
```

### Accessing container bash
To enter the container's bash shell:
```bash
podman exec -it rocm bash
```

### Removing the container
To stop and remove the container:
```bash
podman stop rocm
podman rm rocm
```

Or force remove (stop and remove in one command):
```bash
podman rm -f rocm
```
