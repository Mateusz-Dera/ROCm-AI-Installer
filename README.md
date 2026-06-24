# ROCm-AI-Installer
Installation scripts for an AI applications using ROCm on Linux.

## Info:
[![Version](https://img.shields.io/badge/Version-16-orange.svg)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)

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
|OS|Debian 13.5|
|Kernel|6.12.90+deb13.1-amd64|

###  Text generation:
|Name|Links|Additional information|
|:---|:---|:---|
|KoboldCPP|https://github.com/YellowRoseCx/koboldcpp-rocm||
|SillyTavern|https://github.com/SillyTavern/SillyTavern||
|llama.cpp|https://github.com/ggml-org/llama.cpp<br> https://huggingface.co/unsloth/gemma-4-12b-it-GGUF|1. Multi-Token Prediction (MTP)<br> 2. By default, it downloads <b>gemma-4-12b-it Q8_0 model</b> and MTP head<br> 3. A Vulkan version is also available.|
|turboquant-rocm-llamacpp|https://github.com/jagsan-cyber/turboquant-rocm-llamacpp<br> https://huggingface.co/unsloth/gemma-4-12b-it-GGUF|1. TurboQuant 4-bit KV-cache compression (q4_0)<br> 2. By default, it downloads <b>gemma-4-12b-it Q8_0 model</b><br> 3. ROCm only.|

#### SillyTavern Extensions:
|Name|Link|Additional information|
|:---|:---|:---|
|WhisperSpeech web UI|https://github.com/Mateusz-Dera/whisperspeech-webui|Install and run WhisperSpeech web UI first.|

###  Image & video generation:
|Name|Links|Additional information|
|:---|:---|:---|
|ComfyUI|https://github.com/comfyanonymous/ComfyUI<br> https://github.com/city96/ComfyUI-GGUF|Workflows templates are in the workflows folder.<br> Extension manager is installed by default.<br> <b>ComfyUI-GGUF</b> is installed by default.|

#### ComfyUI Addons:
|Name|Link|Additional information|
|:---|:---|:---|
|Qwen-Image-2512-GGUF|https://huggingface.co/Qwen/Qwen-Image-2512<br>https://huggingface.co/unsloth/Qwen-Image-2512-GGUF<br> https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI<br> https://huggingface.co/Wuli-art/Qwen-Image-2512-Turbo-LoRA-2-Steps|Uses <b>Q5_0</b> quant.<br> Uses <b>2-step turbo LoRA</b>.|
|Qwen-Image-2511-Edit-GGUF|https://huggingface.co/Qwen/Qwen-Image-Edit-2511<br> https://huggingface.co/unsloth/Qwen-Image-Edit-2511-GGUF<br> https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI<br> https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning|Uses <b>Q5_0</b> quant.<br> Uses <b>4-step Lightning LoRA</b>|
|Z-Image-Turbo|https://huggingface.co/Tongyi-MAI/Z-Image-Turbo<br> https://huggingface.co/Comfy-Org/z_image_turbo||
|Z-Anime|https://huggingface.co/SeeSee21/Z-Anime<br> https://huggingface.co/Comfy-Org/z_image_turbo||
|Wan2.2-TI2V-5B|https://huggingface.co/Wan-AI/Wan2.2-TI2V-5B<br> https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged||

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
|TRELLIS.2_rocm|https://github.com/hqnicolas/TRELLIS.2_rocm|1. Go to https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m<br> 2. If you haven't set the <b>HuggingFace Token</b> in <b>Variables</b>, add it and run <b>Create a container</b> again.<br> 3. Recommended resolution: <b>512</b>.|
|Kimodo|https://github.com/nv-tlabs/kimodo|1. Set <b>HuggingFace Token</b> in Variables.<br> 2. Request access to <a href="https://huggingface.co/meta-llama/Meta-Llama-3-8B-Instruct">meta-llama/Meta-Llama-3-8B-Instruct</a> (required for text encoder).|
|TripoSplat|https://github.com/VAST-AI-Research/TripoSplat||

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
