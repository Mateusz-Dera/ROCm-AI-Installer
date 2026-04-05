# ROCm-AI-Installer
Installation scripts for an AI applications using ROCm on Linux.

## Info:
[![Version](https://img.shields.io/badge/Version-14-orange.svg)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)

![ROCm](https://img.shields.io/badge/ROCm-7.2.1-red.svg)

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
|OS|Debian 13.3|
|Kernel|6.12.74+deb13+1-amd64|

###  Text generation:
|Name|Links|Additional information|
|:---|:---|:---|
|KoboldCPP|https://github.com/YellowRoseCx/koboldcpp-rocm||
|SillyTavern|https://github.com/SillyTavern/SillyTavern||
|TabbyAPI|https://github.com/theroyallab/tabbyAPI|1. Put ExLlamaV2 model files into the <b>models/example-model</b> folder.<br> 2. In run.sh change <b>example-model</b> to the name of your model folder.|
|llama.cpp|https://github.com/ggerganov/llama.cpp|1. Put model.gguf into llama.cpp folder.<br> 2. In run.sh file, change the values of GPU offload layers and context size to match your model.|

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
|Wan2.2-TI2V-5B|https://huggingface.co/Wan-AI/Wan2.2-TI2V-5B<br> https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged||
|ComfyUI-SUPIR|https://github.com/kijai/ComfyUI-SUPIR||

###  Music generation:
|Name|Links|Additional information|
|:---|:---|:---|
|ACE-Step|https://github.com/ace-step/ACE-Step||
|HeartMuLa|https://github.com/HeartMuLa/heartlib|Fodler name is <b>heartlib</b>|

###  Voice generation:
|Name|Links|Additional information|
|:---|:---|:---|
|WhisperSpeech web UI|https://github.com/Mateusz-Dera/whisperspeech-webui<br> https://github.com/collabora/WhisperSpeech||
|F5-TTS|https://github.com/SWivid/F5-TTS|Remember to select voice.|
|Soprano|https://github.com/ekwek1/soprano<br> https://github.com/Mateusz-Dera/soprano-rocm|Uses my experimental fork for ROCm with vLLM|# (Initial run only) You may experience slower audio generation upon first launch. Please restart the application to resolve this.|

###  3D generation:
|Name|Links|Additional information|
|:---|:---|:---|
|PartCrafter|https://github.com/wgsxm/PartCrafter|Added custom simple UI.<br> Uses a modified version of PyTorch Cluster for ROCm https://github.com/Mateusz-Dera/pytorch_cluster_rocm.|
|TRELLIS-AMD|https://github.com/CalebisGross/TRELLIS-AMD|GLB Export Takes 5-10 Minutes.<br> Mesh preview may show grey, but the actual export works correctly.|

## Instalation:

1\. Install Podman.

> [!Note]
> If you are using Debian 13.3, you can use <b>sudo apt-get update && sudo apt-get -y install podman podman-compose qemu-system</b> (should also work on Ubuntu 24.04)


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
