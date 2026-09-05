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
|Kernel|6.12.107+deb13-amd64|

###  Text generation:
|Name|Links|API|GUI|Additional information|
|:---|:---|:---:|:---:|:---|
|SillyTavern|[SillyTavern/SillyTavern](https://github.com/SillyTavern/SillyTavern)|-|8000|1. Basic auth enabled, defaults: <b>user</b> / <b>password</b>.<br> 2. Change in <b>config.yaml</b>.|
|llama.cpp TurboQuant|[TheTom/llama-cpp-turboquant](https://github.com/TheTom/llama-cpp-turboquant)<br> [unsloth/gemma-4-26B-A4B-it-qat-GGUF](https://huggingface.co/unsloth/gemma-4-26B-A4B-it-qat-GGUF)|8080|8080|1. Available as <b>ROCm</b> or <b>Vulkan</b> build.<br> 2. <b>TurboQuant 3-bit KV cache</b>.<br> 3. Model: <b>gemma-4-26B-A4B-it-qat Q4_K_XL</b> with its <b>MTP</b> <br> 4. GGUF: <b>user-models/</b><br> 5. MTP: <b>drafts/</b>.<br> 6. Models: <b>models.ini</b>|
|KoboldCPP|[YellowRoseCx/koboldcpp-rocm](https://github.com/YellowRoseCx/koboldcpp-rocm)|5001|5001||
|vLLM Gemma 4|[vllm-project/vllm](https://github.com/vllm-project/vllm)<br> [0xSero/turboquant](https://github.com/0xSero/turboquant)<br> [google/gemma-4-31B-it-qat](https://huggingface.co/google/gemma-4-31B-it-qat-q4_0-unquantized)|8002|-|1. <b>TurboQuant 4-bit KV cache</b>.<br> 2. Model: <b>gemma-4-31B-it-qat</b>, quantized to W4A16 during install.<br> 3. <b>~59GB</b> download, <b>~50GB</b> RAM for the conversion.|

###  Image & video generation:
|Name|Links|API|GUI|Additional information|
|:---|:---|:---:|:---:|:---|
|ComfyUI|[Comfy-Org/ComfyUI](https://github.com/Comfy-Org/ComfyUI)<br> [city96/ComfyUI-GGUF](https://github.com/city96/ComfyUI-GGUF)|8188|8188|Workflows templates are in the workflows folder.<br> Extension manager is installed by default.<br> <b>ComfyUI-GGUF</b> is installed by default.|
|Krea 2 Turbo + Edit|[krea-ai/krea-2](https://github.com/krea-ai/krea-2)<br> [krea/Krea-2-Turbo](https://huggingface.co/krea/Krea-2-Turbo)<br> [krea/krea-2-loras](https://huggingface.co/collections/krea/krea-2-loras)<br> [conradlocke/krea2-identity-edit](https://huggingface.co/conradlocke/krea2-identity-edit)<br> [lbouaraba/comfyui-krea2edit](https://github.com/lbouaraba/comfyui-krea2edit)|-|7860|1. Custom UI.<br> 2. 4-bit NF4 quantization.<br> 3. Turbo model (8 steps).<br> 4. 9 official style LoRAs.<br> 5. Custom LoRA supported.<br> 6. Identity Edit LoRA<br> 7. Krea 2 and the LoRAs are licensed under the <a href="https://krea.ai/krea-2-licensing">Krea 2 Community License Agreement</a>: the weights are <b>gated</b>, so accept it on <a href="https://huggingface.co/krea/Krea-2-Turbo">the model page</a> and set <b>HuggingFace Token</b> in Variables.<br> 8. Commercial use only below <b>1,000,000USD</b> annual revenue; outputs are AI-generated and must be disclosed as such where required.|

#### ComfyUI Addons:
|Name|Link|
|:---|:---|
|Z-Image-Turbo|[Tongyi-MAI/Z-Image-Turbo](https://huggingface.co/Tongyi-MAI/Z-Image-Turbo)<br> [Comfy-Org/z_image_turbo](https://huggingface.co/Comfy-Org/z_image_turbo)|
|Z-Anime|[SeeSee21/Z-Anime](https://huggingface.co/SeeSee21/Z-Anime)<br> [Comfy-Org/z_image_turbo](https://huggingface.co/Comfy-Org/z_image_turbo)|
|Wan2.2-TI2V-5B|[Wan-AI/Wan2.2-TI2V-5B](https://huggingface.co/Wan-AI/Wan2.2-TI2V-5B)<br> [Comfy-Org/Wan_2.2_ComfyUI_Repackaged](https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged)|

###  Music generation:
|Name|Links|GUI|Additional information|
|:---|:---|:---:|:---|
|ACE-Step-1.5|[ace-step/ACE-Step-1.5](https://github.com/ace-step/ACE-Step-1.5)|7860||

###  Voice:
|Name|Links|GUI|Additional information|
|:---|:---|:---:|:---|
|Soprano|[ekwek1/soprano](https://github.com/ekwek1/soprano)<br> [Mateusz-Dera/soprano-rocm](https://github.com/Mateusz-Dera/soprano-rocm)|7860||
|OmniVoice|[k2-fsa/OmniVoice](https://github.com/k2-fsa/OmniVoice)|7860||
|Parakeet|[nvidia/parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)|7860|1. Added custom simple UI.|

###  3D generation:
|Name|Links|API|GUI|Additional information|
|:---|:---|:---:|:---:|:---|
|PartCrafter|[wgsxm/PartCrafter](https://github.com/wgsxm/PartCrafter)<br>[Mateusz-Dera/pytorch_cluster_rocm](https://github.com/Mateusz-Dera/pytorch_cluster_rocm)|-|7860|1. Added custom simple UI.|
|trellis.cpp|[pwilkin/trellis.cpp](https://github.com/pwilkin/trellis.cpp)<br> [ilintar/trellis2-gguf](https://huggingface.co/ilintar/trellis2-gguf)|8081|7860|1. Added custom simple UI.<br> 2. Available as <b>ROCm</b> or <b>Vulkan</b> build.|
|ARDY|[nv-tlabs/ardy](https://github.com/nv-tlabs/ardy)<br> [meta-llama/Meta-Llama-3-8B-Instruct](https://huggingface.co/meta-llama/Meta-Llama-3-8B-Instruct)|-|2333||
|TripoSplat|[VAST-AI-Research/TripoSplat](https://github.com/VAST-AI-Research/TripoSplat)|-|7860||
|AutoRemesher|[huxingyi/autoremesher](https://github.com/huxingyi/autoremesher)|-|-|1. Automatic quad-remeshing tool.|

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
