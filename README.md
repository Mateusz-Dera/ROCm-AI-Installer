# ROCm-AI-Installer
Installation scripts for an AI applications using ROCm on Linux.

## Info:
[![Version](https://img.shields.io/badge/Version-17-grey.svg?labelColor=white)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)
![ROCm](https://img.shields.io/badge/ROCm-10.0-grey.svg?labelColor=white)

[![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black)](#)
[![Podman](https://img.shields.io/badge/Podman-892CA0?logo=podman&logoColor=fff)](#)
[![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=fff)](#)
[![Python](https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=fff)](#)
[![Node.js](https://img.shields.io/badge/Node.js-6DA55F?logo=node.js&logoColor=white)](#)
[![Gradio](https://img.shields.io/badge/Gradio-F97316?logo=Gradio&logoColor=white)](#)
[![PyTorch](https://img.shields.io/badge/PyTorch-EE4C2C?logo=pytorch&logoColor=fff)](#)

> [!Warning]
> This is an <b>experimental branch</b>. Things here are work in progress:
> some applications may not work, pinned versions change often, and
> <b>not everything will necessarily be merged into the main branch</b>.<br>
> Use the main branch if you want a stable installer.

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
|Name|Links|API|GUI|Additional information|
|:---|:---|:---:|:---:|:---|
|SillyTavern|[SillyTavern/SillyTavern](https://github.com/SillyTavern/SillyTavern)|-|8000|1. Basic auth enabled, defaults: <b>user</b> / <b>password</b>.<br> 2. Change in <b>config.yaml</b>.|
|llama.cpp TurboQuant|[TheTom/llama-cpp-turboquant](https://github.com/TheTom/llama-cpp-turboquant)<br> [unsloth/gemma-4-26B-A4B-it-qat-GGUF](https://huggingface.co/unsloth/gemma-4-26B-A4B-it-qat-GGUF)|8080|8080|1. Available as <b>ROCm</b> or <b>Vulkan</b> build.<br> 2. <b>TurboQuant 3-bit KV cache</b>.<br> 3. Model: <b>gemma-4-26B-A4B-it-qat Q4_K_XL</b> with its <b>MTP</b> draft for speculative decoding, both downloaded as an example.<br> 4. Drop more GGUFs into the build's own <b>user-models/</b>, MTP drafts into its <b>drafts/</b>. The ROCm and Vulkan builds keep separate directories.<br> 5. Per-model configuration lives in <b>models.ini</b> - see below.<br> 6. Default 1 model loaded at a time.<br> 7. Model is picked in the WebUI.|
|KoboldCPP|[YellowRoseCx/koboldcpp-rocm](https://github.com/YellowRoseCx/koboldcpp-rocm)|5001|5001||
|vLLM Gemma 4|[vllm-project/vllm](https://github.com/vllm-project/vllm)<br> [0xSero/turboquant](https://github.com/0xSero/turboquant)<br> [google/gemma-4-31B-it-qat](https://huggingface.co/google/gemma-4-31B-it-qat-q4_0-unquantized)|8002|-|1. <b>TurboQuant 4-bit KV cache</b>.<br> 2. Model: <b>gemma-4-31B-it-qat</b>, quantized to W4A16 during install.<br> 3. <b>~59GB</b> download, <b>~50GB</b> RAM for the conversion.<br> 4. Tool calling and reasoning enabled.<br> 5. One session with the full <b>262144</b> token context on <b>24GB</b>.<br> 6. The KV pool holds about <b>337000</b> tokens, so editing <b>run.sh</b> to <b>--max-num-seqs 2 --max-model-len 130000</b> and <b>TQ_CAPACITY=130000</b> gives two concurrent sessions of <b>130k</b> each. Session isolation is verified by the test suite.|

#### llama.cpp per-model configuration:

`models.ini` in the application directory configures every model the router serves.
The `[*]` section applies to all of them, a section named after a model applies to
that one only, and command line arguments win over both.

```ini
version = 1

[*]
c = 262144
n-gpu-layers = 999
cache-type-k = turbo3
cache-type-v = turbo3

[gemma-4-26B-A4B-it-qat-UD-Q4_K_XL]
model-draft = /AI/llama.cpp-turboquant/drafts/mtp-gemma-4-26B-A4B-it-Q8_0.gguf
```

The section name is the model id as `/v1/models` reports it, which is the GGUF file
name without the extension. Keys are command line arguments without the leading
dashes.

A draft model has to be attached per model, never globally: llama.cpp refuses to
start a model whose vocabulary does not match the draft, and a draft belonging to a
different model of the same family is accepted but its guesses are rejected, which
is slower than no speculation at all.

Keep MTP drafts in `drafts/`, next to `user-models/` in the same application
directory. Anything placed in `user-models/` is offered as a model to serve, and a
subdirectory there is read as one multi-file model. Do not use llama.cpp's own
`models/` directory - it ships vocabulary fixtures the router would serve as models.

###  Image & video generation:
|Name|Links|API|GUI|Additional information|
|:---|:---|:---:|:---:|:---|
|ComfyUI|[Comfy-Org/ComfyUI](https://github.com/Comfy-Org/ComfyUI)<br> [city96/ComfyUI-GGUF](https://github.com/city96/ComfyUI-GGUF)|8188|8188|Workflows templates are in the workflows folder.<br> Extension manager is installed by default.<br> <b>ComfyUI-GGUF</b> is installed by default.|
|Krea 2 Turbo + Edit|[krea-ai/krea-2](https://github.com/krea-ai/krea-2)<br> [krea/Krea-2-Turbo](https://huggingface.co/krea/Krea-2-Turbo)<br> [krea/krea-2-loras](https://huggingface.co/collections/krea/krea-2-loras)<br> [conradlocke/krea2-identity-edit](https://huggingface.co/conradlocke/krea2-identity-edit)<br> [lbouaraba/comfyui-krea2edit](https://github.com/lbouaraba/comfyui-krea2edit)|-|7860|1. Custom UI gathering generation, LoRAs and editing in one place.<br> 2. 4-bit NF4 quantized to fit 24 GB VRAM.<br> 3. Turbo model (8 steps).<br> 4. 9 official style LoRAs available.<br> 5. Custom LoRA upload supported (native Krea 2 LoRAs are auto-converted to diffusers format).<br> 6. <b>Identity Edit</b> tab: instruction-based, identity-preserving editing of one photo, or combining two (scene + person).<br> 7. Identity Edit LoRA: <a href="https://huggingface.co/conradlocke/krea2-identity-edit">conradlocke/krea2-identity-edit</a> (unofficial community LoRA).<br> 8. Krea 2 and the LoRAs are licensed under the <a href="https://krea.ai/krea-2-licensing">Krea 2 Community License Agreement</a>: the weights are <b>gated</b>, so accept it on <a href="https://huggingface.co/krea/Krea-2-Turbo">the model page</a> and set <b>HuggingFace Token</b> in Variables.<br> 9. Commercial use only below <b>1,000,000USD</b> annual revenue; outputs are AI-generated and must be disclosed as such where required.|

#### ComfyUI Addons:
|Name|Link|Additional information|
|:---|:---|:---|
|Z-Image-Turbo|[Tongyi-MAI/Z-Image-Turbo](https://huggingface.co/Tongyi-MAI/Z-Image-Turbo)<br> [Comfy-Org/z_image_turbo](https://huggingface.co/Comfy-Org/z_image_turbo)|
|Z-Anime|[SeeSee21/Z-Anime](https://huggingface.co/SeeSee21/Z-Anime)<br> [Comfy-Org/z_image_turbo](https://huggingface.co/Comfy-Org/z_image_turbo)|
|Wan2.2-TI2V-5B|[Wan-AI/Wan2.2-TI2V-5B](https://huggingface.co/Wan-AI/Wan2.2-TI2V-5B)<br> [Comfy-Org/Wan_2.2_ComfyUI_Repackaged](https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged)|

###  Music generation:
|Name|Links|API|GUI|Additional information|
|:---|:---|:---:|:---:|:---|
|ACE-Step-1.5|[ace-step/ACE-Step-1.5](https://github.com/ace-step/ACE-Step-1.5)|-|7860||

###  Voice:
|Name|Links|API|GUI|Additional information|
|:---|:---|:---:|:---:|:---|
|Soprano|[ekwek1/soprano](https://github.com/ekwek1/soprano)<br> [Mateusz-Dera/soprano-rocm](https://github.com/Mateusz-Dera/soprano-rocm)|-|7860|1. Uses my experimental fork for ROCm with vLLM.|
|OmniVoice|[k2-fsa/OmniVoice](https://github.com/k2-fsa/OmniVoice)|-|7860||
|Parakeet|[nvidia/parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)|-|7860|1. Speech recognition, 25 European languages.<br> 2. Added custom simple UI.|

###  3D generation:
|Name|Links|API|GUI|Additional information|
|:---|:---|:---:|:---:|:---|
|PartCrafter|[wgsxm/PartCrafter](https://github.com/wgsxm/PartCrafter)<br>[Mateusz-Dera/pytorch_cluster_rocm](https://github.com/Mateusz-Dera/pytorch_cluster_rocm)|-|7860|1. Added custom simple UI.|
|trellis.cpp|[pwilkin/trellis.cpp](https://github.com/pwilkin/trellis.cpp)<br> [ilintar/trellis2-gguf](https://huggingface.co/ilintar/trellis2-gguf)|8081|7860|1. Available as <b>ROCm</b> or <b>Vulkan</b> build, each in its own directory (<b>trellis.cpp</b> and <b>trellis.cpp-vulkan</b>) with its own weights.<br> 2. TRELLIS.2-4B image-to-3D in <b>C++/GGML</b>, no Python at runtime.<br> 3. Web UI on <b>7860</b> with a textured 3D preview, talking to the server on <b>8081</b>.<br> 4. HTTP API: <b>GET /health</b>, <b>POST /generate</b> (image, seed, resolution, bg_removal, uv, webp) returns a GLB.<br> 5. Output is a <b>UV-textured</b> GLB with PBR materials.<br> 6. Weights: <b>q8</b> (10GB), <b>full</b> (16.5GB) and <b>q4</b> (6.5GB), all downloaded during installation (<b>33GB</b> total).<br> 7. The set is picked in the WebUI; the engine restarts itself when another one is chosen.|
|ARDY|[nv-tlabs/ardy](https://github.com/nv-tlabs/ardy)<br> [meta-llama/Meta-Llama-3-8B-Instruct](https://huggingface.co/meta-llama/Meta-Llama-3-8B-Instruct)|-|2333|1. NVIDIA autoregressive-diffusion <b>interactive human/robot motion generation</b> from text + kinematic constraints (successor to Kimodo).<br> 2. Interactive <b>viser web demo</b> on <b>port 2333</b> (run.sh); a headless CLI (<b>scripts/generate.py</b>) is also available.<br> 3. Set <b>HuggingFace Token</b> in Variables and request access to <a href="https://huggingface.co/meta-llama/Meta-Llama-3-8B-Instruct">meta-llama/Meta-Llama-3-8B-Instruct</a>.<br> 4. <b>Partially runs on the CPU</b>: the LLM2Vec text encoder (Llama-3-8B) is started as a separate process with <b>--device cpu</b> and encodes the prompt; the motion diffusion model runs on the GPU. On the GPU the encoder needs about <b>14 GB VRAM</b> on top of the rest.<br> 5. Checkpoints download automatically on first use.|
|TripoSplat|[VAST-AI-Research/TripoSplat](https://github.com/VAST-AI-Research/TripoSplat)|-|7860||
|AutoRemesher|[huxingyi/autoremesher](https://github.com/huxingyi/autoremesher)|-|-|1. Automatic (not AI) quad-remeshing tool, added as a helper.<br> 2. Retopologizes the triangle-soup meshes from the 3D-generation apps.|

## Instalation:

1\. Install Podman.

> [!Note]
> If you are using Debian 13.6, you can use <b>sudo apt-get update && sudo apt-get -y install podman podman-compose qemu-system</b> (should also work on Ubuntu 26.04)

> [!Note]
> The installer menus need <b>whiptail</b>. It is preinstalled on most systems; if it is missing the script says so and exits.

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

> [!Important]
> From version 17, ROCm packages are installed <b>per GPU architecture</b>. The installer reads the cards from the kernel and preselects them under <b>GFX</b>, and the container is built with the packages for those architectures only - not for every GPU AMD ships.<br>
> Selecting more than one architecture is supported, so a machine with, say, a <b>gfx1100</b> card and a <b>gfx1036</b> integrated GPU can have both. Changing the selection requires recreating the container.

> [!Note]
> <b>Using several cards at once has not been tested.</b> The installer can build for more than one architecture, and each application is pinned to a single card when it is installed, but everything here was only ever run on a single GPU.

7\. Create a container if you are upgrading or running the script for the first time.

8\. Install the applications of your choice.

> [!NOTE]
> With more than one usable card, each application asks which one it should run on while it is being installed. The answer is written into that application's <b>run.sh</b> as <b>HIP_VISIBLE_DEVICES</b>, so different applications can use different cards - image generation on the discrete GPU, something small on the integrated one.<br>
> There is no container-wide setting for this.<br>
> To change it later, edit <b>HIP_VISIBLE_DEVICES</b> in the application's <b>run.sh</b> or reinstall the application.

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
