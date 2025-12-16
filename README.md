# ROCm-AI-Installer
Installation scripts for an AI applications using ROCm on Linux.

## Info:
[![Version](https://img.shields.io/badge/Version-10.0-orange.svg)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)

![ROCm](https://img.shields.io/badge/ROCm-7.1.1-red.svg)

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
|OS|Debian 13.2|
|Kernel|6.12.57+deb13-amd64|

###  Text generation:
|Name|Links|Additional information|
|:---|:---|:---|
|KoboldCPP|https://github.com/YellowRoseCx/koboldcpp-rocm|Support GGML and GGUF models.|
|Text generation web UI|https://github.com/oobabooga/text-generation-webui<br/> https://github.com/ROCm/bitsandbytes.git<br/>  https://github.com/turboderp/exllamav2|1. Support ExLlamaV2, llama.cpp and Transformers.<br> 2. If you are using Transformers, it is recommended to use sdpa option instead of flash_attention_2.|
|SillyTavern|https://github.com/SillyTavern/SillyTavern||
|llama.cpp|https://github.com/ggerganov/llama.cpp|1. Put model.gguf into llama.cpp folder.<br> 2. In run.sh file, change the values of GPU offload layers and context size to match your model.|

#### SillyTavern Extensions:
|Name|Link|Additional information|
|:---|:---|:---|
|WhisperSpeech web UI|https://github.com/Mateusz-Dera/whisperspeech-webui|Install and run WhisperSpeech web UI first.|

###  Image & video generation:
|Name|Links|Additional information|
|:---|:---|:---|
|ComfyUI|https://github.com/comfyanonymous/ComfyUI|Workflows templates are in the workflows folder.|

#### ComfyUI Addons:
|Name|Link|Additional information|
|:---|:---|:---|
|ComfyUI-Manager|https://github.com/ltdrdata/ComfyUI-Manager| Manage nodes of ComfyUI.<br> After first run change custom_nodes/ComfyUI-Manager/config.ini security_level to weak.|
|GGUF|https://github.com/calcuis/gguf|GGUF models loader.|
|ComfyUI-AuraSR|https://github.com/alexisrolland/ComfyUI-AuraSR<br> https://huggingface.co/fal/AuraSR<br> https://huggingface.co/fal/AuraSR-v2|ComfyUI node to upscale images.|
|AuraFlow-v0.3|https://huggingface.co/fal/AuraFlow-v0.3|Text to image model.|
|Qwen-Image GGUF|https://huggingface.co/Qwen/Qwen-Image<br> https://huggingface.co/QuantStack/Qwen-Image-Edit-2509-GGUF<br> https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI<br> https://huggingface.co/lightx2v/Qwen-Image-Lightning|Text to image model.<br> Qwen Image-Quant: <b>Q6_K</b>|
|Qwen-Image-Edit GGUF|https://huggingface.co/Qwen/Qwen-Image-Edit<br> https://huggingface.co/calcuis/qwen-image-edit-ggu<br> https://huggingface.co/Comfy-Org/Qwen-Image-Edit_ComfyUI<br> https://huggingface.co/city96/Qwen-Image-gguf<br> https://huggingface.co/lightx2v/Qwen-Image-Lightning|Text to image model.<br> Qwen Image-Quant-Edit quant: <b>Q4_K_M</b>|
|Qwen-Image-Edit-2509 GGUF|https://huggingface.co/Qwen/Qwen-Image-Edit-2509<br> https://huggingface.co/calcuis/qwen-image-edit-gguf<br> https://huggingface.co/Comfy-Org/Qwen-Image-Edit_ComfyUI<br> https://huggingface.co/city96/Qwen-Image-gguf<br> https://huggingface.co/lightx2v/Qwen-Image-Lightning|Text to image model.<br> Qwen Image-Quant-Edit-2509 quant: <b>Q4_0</b>|
|Wan2.2-TI2V-5B|https://huggingface.co/Wan-AI/Wan2.2-TI2V-5B<br> https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged|Text to video model.<br> Workflow also supports image to video.|

###  Music generation:
|Name|Links|Additional information|
|:---|:---|:---|
|ACE-Step|https://github.com/ace-step/ACE-Step||

###  Voice generation:
|Name|Links|Additional information|
|:---|:---|:---|
|WhisperSpeech web UI|https://github.com/Mateusz-Dera/whisperspeech-webui<br> https://github.com/collabora/WhisperSpeech||
|F5-TTS|https://github.com/SWivid/F5-TTS|Remember to select voice.|
|Matcha-TTS|https://github.com/shivammehta25/Matcha-TTS||
|Dia|https://github.com/nari-labs/dia<br> https://github.com/tralamazza/dia/tree/optional-rocm-cuda|Script uses the optional-rocm-cuda fork by tralamazza.|
|Chatterbox Multilingual|https://github.com/resemble-ai/chatterbox|Only Polish and English have been tested.<br> May not read non-English characters.<br> Polish is fixed:<br> https://github.com/resemble-ai/chatterbox/issues/256<br> For other languages, you will need to add the changes manually in the multilingual_app.py file.<br> For a better effect in Polish, I recommend using lowercase letters for the entire text.|
|KaniTTS|https://github.com/nineninesix-ai/kani-tts|If you want to change the default model, edit the <b>kanitts/config.py</b> file.|
|KaniTTS-vLLM|https://github.com/nineninesix-ai/kanitts-vllm|If you want to change the default model, edit the <b>config.py</b> file.|

###  3D generation:
|Name|Links|Additional information|
|:---|:---|:---|
|PartCrafter|https://github.com/wgsxm/PartCrafter|Added custom simple UI.<br> Uses a modified version of PyTorch Cluster for ROCm https://github.com/Mateusz-Dera/pytorch_cluster_rocm.|

## Instalation:

1\. Install Podman.

> [!Note]
> If you are using Debian 13.2, you can use <b>sudo apt-get update && sudo apt-get -y install podman podman-compose qemu-system</b> (should also work on Ubuntu 24.04)


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
bash ./install.sh
```
6\. Set variables

> [!NOTE]
> By default, the script is configured for AMD Radeon 7900XTX.<br>
> For other cards and architectures, edit <b>GFX</b> and <b>HSA_OVERRIDE_GFX_VERSION</b>.

7\. Create container if you are upgrading or running the script for the first time.

8\. Install selected app.

9\. Go to the application folder and run:
```bash
./run.sh
```

> [!NOTE]
> Everything is configured to start from the host side (You don’t need to enter the container).