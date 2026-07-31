# ROCm-AI-Installer
Installation scripts for an AI applications using ROCm on Linux.

## Info:
[![Version](https://img.shields.io/badge/Version-17-grey.svg?labelColor=white)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)
![ROCm](https://img.shields.io/badge/ROCm-7.2.4-grey.svg?labelColor=white)

[![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black)](#)
[![Podman](https://img.shields.io/badge/Podman-892CA0?logo=podman&logoColor=fff)](#)
[![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=fff)](#)
[![Python](https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=fff)](#)
[![Node.js](https://img.shields.io/badge/Node.js-6DA55F?logo=node.js&logoColor=white)](#)
[![Gradio](https://img.shields.io/badge/Gradio-F97316?logo=Gradio&logoColor=white)](#)
[![PyTorch](https://img.shields.io/badge/PyTorch-EE4C2C?logo=pytorch&logoColor=fff)](#)

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
|Name|Links|Port|Additional information|
|:---|:---|:---:|:---|
|SillyTavern|[SillyTavern/SillyTavern](https://github.com/SillyTavern/SillyTavern)|8000||
|llama.cpp|[ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)<br> [unsloth/gemma-4-12b-it-GGUF](https://huggingface.co/unsloth/gemma-4-12b-it-GGUF)|8080|1. Runs in <b>router mode</b> - <b>pick/switch models from the WebUI</b> without restarting (see <i>Switching models</i> below).<br> 2. By default downloads the <b>gemma-4-12b-it Q8_0</b> model into <b>user-models/</b>.<br> 3. A Vulkan version is also available.|
|turboquant-rocm-llamacpp|[jagsan-cyber/turboquant-rocm-llamacpp](https://github.com/jagsan-cyber/turboquant-rocm-llamacpp)<br> [unsloth/gemma-4-12b-it-GGUF](https://huggingface.co/unsloth/gemma-4-12b-it-GGUF)|8080|1. TurboQuant 4-bit KV-cache compression (q4_0).<br> 2. <b>Router mode</b> - pick/switch models from the WebUI (see <i>Switching models</i> below).<br> 3. By default downloads the <b>gemma-4-12b-it Q8_0</b> model into <b>user-models/</b>.<br> 4. ROCm only.|
|vLLM Gemma 4|[vllm-project/vllm](https://github.com/vllm-project/vllm)<br> [0xSero/turboquant](https://github.com/0xSero/turboquant)<br> [google/gemma-4-31B-it](https://huggingface.co/google/gemma-4-31B-it)|8000<br>8080|TODO|

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
|WhisperSpeech web UI|[Mateusz-Dera/whisperspeech-webui](https://github.com/Mateusz-Dera/whisperspeech-webui)|Install and run WhisperSpeech web UI first.|

###  Image & video generation:
|Name|Links|Port|Additional information|
|:---|:---|:---:|:---|
|ComfyUI|[comfyanonymous/ComfyUI](https://github.com/comfyanonymous/ComfyUI)<br> [city96/ComfyUI-GGUF](https://github.com/city96/ComfyUI-GGUF)|8188|Workflows templates are in the workflows folder.<br> Extension manager is installed by default.<br> <b>ComfyUI-GGUF</b> is installed by default.|
|Krea 2 Turbo + Edit|[krea-ai/krea-2](https://github.com/krea-ai/krea-2)<br> [krea/Krea-2-Turbo](https://huggingface.co/krea/Krea-2-Turbo)<br> [krea/krea-2-loras](https://huggingface.co/collections/krea/krea-2-loras)<br> [conradlocke/krea2-identity-edit](https://huggingface.co/conradlocke/krea2-identity-edit)<br> [lbouaraba/comfyui-krea2edit](https://github.com/lbouaraba/comfyui-krea2edit)|7860|1. 4-bit NF4 quantized to fit 24 GB VRAM<br> 2. Turbo model (8 steps)<br> 3. 9 official style LoRAs available<br> 4. Custom LoRA upload supported (native Krea 2 LoRAs are auto-converted to diffusers format)<br> 5. <b>Identity Edit</b> tab: instruction-based, identity-preserving editing of a single photo, or combining two photos (scene + person)<br> 6. Identity Edit uses the <b>unofficial community LoRA</b> <a href="https://huggingface.co/conradlocke/krea2-identity-edit">conradlocke/krea2-identity-edit</a> <br> 7. Krea 2 and the LoRAs are licensed under the <a href="https://krea.ai/krea-2-licensing">Krea 2 Community License Agreement</a>.|

#### ComfyUI Addons:
|Name|Link|Additional information|
|:---|:---|:---|
|Qwen-Image-2512-GGUF|[Qwen/Qwen-Image-2512](https://huggingface.co/Qwen/Qwen-Image-2512)<br>[unsloth/Qwen-Image-2512-GGUF](https://huggingface.co/unsloth/Qwen-Image-2512-GGUF)<br> [Comfy-Org/Qwen-Image_ComfyUI](https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI)<br> [Wuli-art/Qwen-Image-2512-Turbo-LoRA-2-Steps](https://huggingface.co/Wuli-art/Qwen-Image-2512-Turbo-LoRA-2-Steps)|Uses <b>Q5_0</b> quant.<br> Uses <b>2-step turbo LoRA</b>.|
|Qwen-Image-2511-Edit-GGUF|[Qwen/Qwen-Image-Edit-2511](https://huggingface.co/Qwen/Qwen-Image-Edit-2511)<br> [unsloth/Qwen-Image-Edit-2511-GGUF](https://huggingface.co/unsloth/Qwen-Image-Edit-2511-GGUF)<br> [Comfy-Org/Qwen-Image_ComfyUI](https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI)<br> [lightx2v/Qwen-Image-Edit-2511-Lightning](https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning)|Uses <b>Q5_0</b> quant.<br> Uses <b>4-step Lightning LoRA</b>|
|Z-Image-Turbo|[Tongyi-MAI/Z-Image-Turbo](https://huggingface.co/Tongyi-MAI/Z-Image-Turbo)<br> [Comfy-Org/z_image_turbo](https://huggingface.co/Comfy-Org/z_image_turbo)|
|Z-Anime|[SeeSee21/Z-Anime](https://huggingface.co/SeeSee21/Z-Anime)<br> [Comfy-Org/z_image_turbo](https://huggingface.co/Comfy-Org/z_image_turbo)|
|Wan2.2-TI2V-5B|[Wan-AI/Wan2.2-TI2V-5B](https://huggingface.co/Wan-AI/Wan2.2-TI2V-5B)<br> [Comfy-Org/Wan_2.2_ComfyUI_Repackaged](https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged)|

###  Fine-tuning:
|Name|Links|Port|Additional information|
|:---|:---|:---:|:---|
|Unsloth|[unslothai/unsloth](https://github.com/unslothai/unsloth)<br> [unsloth.ai](https://unsloth.ai/docs/basics/amd)|8888|TODO|

###  Music generation:
|Name|Links|Port|Additional information|
|:---|:---|:---:|:---|
|ACE-Step-1.5|[ace-step/ACE-Step-1.5](https://github.com/ace-step/ACE-Step-1.5)|7860||

###  Voice generation:
|Name|Links|Port|Additional information|
|:---|:---|:---:|:---|
|WhisperSpeech web UI|[Mateusz-Dera/whisperspeech-webui](https://github.com/Mateusz-Dera/whisperspeech-webui)<br> [collabora/WhisperSpeech](https://github.com/collabora/WhisperSpeech)|7860||
|Soprano|[ekwek1/soprano](https://github.com/ekwek1/soprano)<br> [Mateusz-Dera/soprano-rocm](https://github.com/Mateusz-Dera/soprano-rocm)|7860|1. Uses my experimental fork for ROCm with vLLM|
|OmniVoice|[k2-fsa/OmniVoice](https://github.com/k2-fsa/OmniVoice)|7860||

###  3D generation:
|Name|Links|Port|Additional information|
|:---|:---|:---:|:---|
|PartCrafter|[wgsxm/PartCrafter](https://github.com/wgsxm/PartCrafter)<br>[Mateusz-Dera/pytorch_cluster_rocm](https://github.com/Mateusz-Dera/pytorch_cluster_rocm)|7860|1. Added custom simple UI.|
|trellis2.c|[Wimacs/trellis2.c](https://github.com/Wimacs/trellis2.c)|—|1. A Vulkan version is also available.|
|Pixal3D Experimental|[Wimacs/trellis2.c](https://github.com/Wimacs/trellis2.c)<br> [TencentARC/Pixal3D](https://huggingface.co/TencentARC/Pixal3D)<br> [valeoai/NAF](https://github.com/valeoai/NAF)|—|1. Fits in 24 GB via a custom OOM patch and preset runtime flags. <br> 2. TODO|
|ARDY|[nv-tlabs/ardy](https://github.com/nv-tlabs/ardy)<br> [meta-llama/Meta-Llama-3-8B-Instruct](https://huggingface.co/meta-llama/Meta-Llama-3-8B-Instruct)|2333|1. NVIDIA autoregressive-diffusion <b>interactive human/robot motion generation</b> from text + kinematic constraints (successor to Kimodo).<br> 2. Interactive <b>viser web demo</b> on <b>port 2333</b> (run.sh); a headless CLI (<b>scripts/generate.py</b>) is also available.<br> 3. Set <b>HuggingFace Token</b> in Variables and request access to <a href="https://huggingface.co/meta-llama/Meta-Llama-3-8B-Instruct">meta-llama/Meta-Llama-3-8B-Instruct</a> (LLM2Vec text encoder, runs on CPU).<br> 4. Checkpoints download automatically on first use.|
|TripoSplat|[VAST-AI-Research/TripoSplat](https://github.com/VAST-AI-Research/TripoSplat)|7860||
|AutoRemesher|[huxingyi/autoremesher](https://github.com/huxingyi/autoremesher)|7860|1. Automatic (not AI) quad-remeshing tool, added as a helper.<br> 2. Retopologizes the triangle-soup meshes from the 3D-generation apps.|

## Instalation:

1\. Install Podman.

> [!Note]
> If you are using Debian 13.6, you can use <b>sudo apt-get update && sudo apt-get -y install podman podman-compose qemu-system</b> (should also work on Ubuntu 26.04)

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
