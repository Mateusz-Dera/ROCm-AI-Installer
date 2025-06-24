# ROCm-AI-Installer
A script that automatically installs all the required stuff to run selected AI interfaces on AMD Radeon 7900XTX.
It should also work on 7900XT cards.
For other cards, change HSA_OVERRIDE_GFX_VERSION and GFX at the beginning of the script (Not tested).

## Info
[![Version](https://img.shields.io/badge/7.8-version-orange.svg)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)

> [!Note]
> Ubuntu 24.04.2 LTS is recommended. Version 7.x is not tested on older systems.

### Test platform:
|Name|Info|
|:---|:---|
|CPU|AMD Ryzen 9950X3D (iGPU disabled in BIOS)|
|GPU|AMD Radeon 7900XTX|
|RAM|64GB DDR5 6600MHz|
|Motherboard|ASRock B650E PG Riptide WiFi (BIOS 3.25)|
|OS|Ubuntu 24.04.2 LTS|
|Kernel|6.11.0-26-generic|
|ROCm|6.4.1|

###  Text generation
|Name|Links|Additional information|
|:---|:---|:---|
|KoboldCPP|https://github.com/YellowRoseCx/koboldcpp-rocm|Support GGML and GGUF models.|
|Text generation web UI|https://github.com/oobabooga/text-generation-webui<br/> https://github.com/ROCm/bitsandbytes.git<br/>  https://github.com/turboderp/exllamav2|Support ExLlamaV2, Transformers using ROCm and llama.cpp using Vulkan.|
|SillyTavern|https://github.com/SillyTavern/SillyTavern||
|llama.cpp|https://github.com/ggerganov/llama.cpp|1. Put model.gguf into llama.cpp folder.<br> 2. Change context size in run.sh file (Default: 32768).<br> 3. Set GPU offload layers in run.sh file (Default: 1)|

###  Image & video generation
|Name|Links|Additional information|
|:---|:---|:---|
|ComfyUI|https://github.com/comfyanonymous/ComfyUI|Workflows templates are in the workflows folder.|
|Artist|https://github.com/songrise/Artist/||
|Cinemo|https://huggingface.co/spaces/maxin-cn/Cinemo<br> https://github.com/maxin-cn/Cinemo|Interface PyTorch uses PyTorch 2.4.0|

#### ComfyUI Addons

> [!Important]
> For GGUF models:<br>
> 1\. Accept accept the conditions to access its files and content on HugginFace website:<br>
> https://huggingface.co/black-forest-labs/FLUX.1-schnell <br>
> 2\. HugginFace token is required during installation.

|Name|Link|Additional information|
|:---|:---|:---|
|ComfyUI-Manager|https://github.com/ltdrdata/ComfyUI-Manager| Manage nodes of ComfyUI.<br> After first run change custom_nodes/ComfyUI-Manager/config.ini security_level to weak.|
|ComfyUI-GGUF|https://github.com/city96/ComfyUI-GGUF<br> https://huggingface.co/city96/t5-v1_1-xxl-encoder-bf16<br> https://huggingface.co/openai/clip-vit-large-patch14<br> https://huggingface.co/black-forest-labs/FLUX.1-schnell|GGUF models loader.|
|ComfyUI-AuraSR|https://github.com/alexisrolland/ComfyUI-AuraSR<br> https://huggingface.co/fal/AuraSR<br> https://huggingface.co/fal/AuraSR-v2|ComfyUI node to upscale images.|
|AuraFlow-v0.3|https://huggingface.co/fal/AuraFlow-v0.3|Text to image model.|
|FLUX.1-schnell GGUF|https://huggingface.co/black-forest-labs/FLUX.1-schnell<br> https://huggingface.co/city96/FLUX.1-schnell-gguf|Text to image model.|
|AnimePro FLUX GGUF|https://huggingface.co/advokat/AnimePro-FLUX|Text to image model.|
|Flex.1-alpha GGUF|https://huggingface.co/ostris/Flex.1-alpha<br> https://huggingface.co/hum-ma/Flex.1-alpha-GGUF|Text to image model.|
|Wan 2.1|https://github.com/Wan-Video/Wan2.1<br> https://comfyanonymous.github.io/ComfyUI_examples/wan/<br> https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged|Text to video model.<br> Image to video model.|

###  Music generation
|Name|Links|Additional information|
|:---|:---|:---|
|ACE-Step|https://github.com/ace-step/ACE-Step||

###  Voice generation
|Name|Links|Additional information|
|:---|:---|:---|
|WhisperSpeech web UI|https://github.com/Mateusz-Dera/whisperspeech-webui<br> https://github.com/collabora/WhisperSpeech||
|F5-TTS|https://github.com/SWivid/F5-TTS|Remember to select the voice file when using the interface.|
|Matcha-TTS|https://github.com/shivammehta25/Matcha-TTS||
|Dia|https://github.com/nari-labs/dia<br> https://github.com/tralamazza/dia/tree/optional-rocm-cuda|Script uses the optional-rocm-cuda fork by tralamazza.|
|Orpheus-TTS|https://huggingface.co/spaces/MohamedRashad/Orpheus-TTS/tree/main<br> https://github.com/canopyai/Orpheus-TTS|If GPU is not detected change HIP_VISIBLE_DEVICES value.|
|IMS-Toucan|https://github.com/DigitalPhonetics/IMS-Toucan.git|Interface PyTorch uses PyTorch 2.4.0|
|Chatterbox|https://github.com/resemble-ai/chatterbox<br> https://huggingface.co/spaces/ResembleAI/Chatterbox||
|HierSpeech++|https://github.com/sh-lee-prml/HierSpeechpp<br> http://huggingface.co/spaces/LeeSangHoon/HierSpeech_TTS|Interface PyTorch uses PyTorch 2.4.0|

###  3D generation
|Name|Links|Additional information|
|:---|:---|:---|
|TripoSG|https://github.com/VAST-AI-Research/TripoSG|Added custom simple UI.<br> Sometimes there are probelms with the preview, but the model should still be available for download.|

###  Tools
|Name|Links|Additional information|
|:---|:---|:---|
|Fastfetch|https://github.com/fastfetch-cli/fastfetch|Custom Fastfetch configuration with GPU memory info.<br> Script supports not only AMD but also NVIDIA graphics cards (nvidia-smi needed).<br> If you change the number or order of graphics cards you must run the installer again.|

## Instalation:
> [!Note]
> First startup after installation of the selected interface may take longer.

> [!Important]
> This script does not download any models. If the interface does not have defaults, download your own.

> [!Caution]
> If you update, back up your settings and models. Reinstallation deletes the previous directories.

1\. Add the user to the required groups.
```bash
sudo adduser `whoami` video
sudo adduser `whoami` render
```
2\. Reboot
```bash
sudo reboot
```
3\. Clone repository 
```bash
git clone https://github.com/Mateusz-Dera/ROCm-AI-Installer.git
```
4\. Run installer 
```bash
bash ./install.sh
```
5\. Select installation path.

6\. Select ROCm installation if you are upgrading or running the script for the first time.

7\. Install selected interfaces

8\. Go to the installation path with the selected interface and run:
```bash
./run.sh
```