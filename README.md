# ROCm-AI-Installer
A script that automatically installs all the required stuff to run selected AI interfaces on AMD Radeon 7900XTX.
It should also work on 7900XT cards.
For other cards, change HSA_OVERRIDE_GFX_VERSION and GFX at the beginning of the script (Not tested).

## Info
[![Version](https://img.shields.io/badge/Version-8.0-orange.svg)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)

> [!Note]
> Debian 13 with GNOME and Bash is recommended. Version 8.x is not tested on older systems.
> It should work on Ubuntu 24.04 LTS.

> [!Important]
> All interfaces and models are tested on a card with 24GB VRAM.<br>
> Some interfaces or models may not work on cards with less VRAM.

### Test platform:
|Name|Info|
|:---|:---|
|CPU|AMD Ryzen 9950X3D|
|GPU|AMD Radeon 7900XTX|
|RAM|64GB DDR5 6600MHz|
|Motherboard|ASRock B650E PG Riptide WiFi (BIOS 3.30)|
|OS|Debian 13|
|Kernel|6.14.0-27-generic|
|ROCm|6.4.3|

###  Text generation
|Name|Links|Additional information|
|:---|:---|:---|
|KoboldCPP|https://github.com/YellowRoseCx/koboldcpp-rocm|Support GGML and GGUF models.|
|Text generation web UI|https://github.com/oobabooga/text-generation-webui<br/> https://github.com/ROCm/bitsandbytes.git<br/>  https://github.com/turboderp/exllamav2|1. Support ExLlamaV2, Transformers using ROCm and llama.cpp using Vulkan.<br> 2. If you are using Transformers, it is recommended to use sdpa option instead of flash_attention_2.|
|SillyTavern|https://github.com/SillyTavern/SillyTavern||
|llama.cpp|https://github.com/ggerganov/llama.cpp|1. Put model.gguf into llama.cpp folder.<br> 2. In run.sh file, change the values of GPU offload layers and context size to match your model.|
|Ollama|https://github.com/ollama/ollama|You can use standard Ollama commands in terminal or run GGUF model.<br>1. Put model.gguf into Ollama folder.<br> 2. In run.sh file, change the values of GPU offload layers and context size to match your model.<br> 3. In run.sh file, customize model parameters.|

#### SillyTavern Extensions
|Name|Link|Additional information|
|:---|:---|:---|
|WhisperSpeech web UI|https://github.com/Mateusz-Dera/whisperspeech-webui|Install and run WhisperSpeech web UI first.|

###  Image & video generation
|Name|Links|Additional information|
|:---|:---|:---|
|ComfyUI|https://github.com/comfyanonymous/ComfyUI|Workflows templates are in the workflows folder.|
|Artist|https://github.com/songrise/Artist/||
|Cinemo|https://huggingface.co/spaces/maxin-cn/Cinemo<br> https://github.com/maxin-cn/Cinemo||
|Ovis-U1-3B|https://huggingface.co/spaces/AIDC-AI/Ovis-U1-3B<br> https://github.com/AIDC-AI/Ovis-U1||

#### ComfyUI Addons

> [!Important]
> For GGUF Flux and Flux based models:<br>
> 1\. Accept accept the conditions to access its files and content on HugginFace website:<br>
> https://huggingface.co/black-forest-labs/FLUX.1-schnell <br>
> 2\. HugginFace token is required during installation.

|Name|Link|Additional information|
|:---|:---|:---|
|ComfyUI-Manager|https://github.com/ltdrdata/ComfyUI-Manager| Manage nodes of ComfyUI.<br> After first run change custom_nodes/ComfyUI-Manager/config.ini security_level to weak.|
|ComfyUI-GGUF|https://github.com/city96/ComfyUI-GGUF<br> https://huggingface.co/city96/t5-v1_1-xxl-encoder-bf16<br> https://huggingface.co/openai/clip-vit-large-patch14<br> https://huggingface.co/black-forest-labs/FLUX.1-schnell|GGUF models loader.|
|ComfyUI-AuraSR|https://github.com/alexisrolland/ComfyUI-AuraSR<br> https://huggingface.co/fal/AuraSR<br> https://huggingface.co/fal/AuraSR-v2|ComfyUI node to upscale images.|
|AuraFlow-v0.3|https://huggingface.co/fal/AuraFlow-v0.3|Text to image model.|
|FLUX.1-schnell GGUF|https://huggingface.co/black-forest-labs/FLUX.1-schnell<br> https://huggingface.co/city96/FLUX.1-schnell-gguf|Text to image model.<br> Model quant: <b>Q8_0</b>|
|AnimePro FLUX GGUF|https://huggingface.co/advokat/AnimePro-FLUX|Text to image model.<br> Flux based.<br> Model quant: <b>Q5_K_M</b>|
|Flex.1-alpha GGUF|https://huggingface.co/ostris/Flex.1-alpha<br> https://huggingface.co/hum-ma/Flex.1-alpha-GGUF|Text to image model.<br>Flux based.<br>Model quant: <b>Q8_0</b>|
|Qwen-Image GGUF|https://huggingface.co/Qwen/Qwen-Image<br> https://huggingface.co/city96/Qwen-Image-gguf/tree/main<br> https://huggingface.co/unsloth/Qwen2.5-VL-7B-Instruct-GGUF<br> https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI|Text to image model.<br> Qwen Image-Quant: <b>Q6_K</b><br> Qwen2.5-VL-7B-Instruct quant: <b>Q6_K_XL</b>|

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
|Orpheus-TTS|https://huggingface.co/spaces/MohamedRashad/Orpheus-TTS<br> https://github.com/canopyai/Orpheus-TTS|If GPU is not detected change HIP_VISIBLE_DEVICES value.<br> Examples may show errors.|
|IMS-Toucan|https://github.com/DigitalPhonetics/IMS-Toucan.git|Interface PyTorch uses PyTorch 2.4.0|
|Chatterbox|https://github.com/resemble-ai/chatterbox<br> https://huggingface.co/spaces/ResembleAI/Chatterbox||
|HierSpeech++|https://github.com/sh-lee-prml/HierSpeechpp<br> http://huggingface.co/spaces/LeeSangHoon/HierSpeech_TTS|Interface PyTorch uses PyTorch 2.4.0|

###  3D generation
|Name|Links|Additional information|
|:---|:---|:---|
|TripoSG|https://github.com/VAST-AI-Research/TripoSG|Added custom simple UI.<br> Uses a modified version of PyTorch Cluster for ROCm https://github.com/Mateusz-Dera/pytorch_cluster_rocm.<br> Sometimes there are probelms with the preview, but the model should still be available for download.|
|PartCrafter|https://github.com/wgsxm/PartCrafter|Added custom simple UI.<br> Uses a modified version of PyTorch Cluster for ROCm https://github.com/Mateusz-Dera/pytorch_cluster_rocm.|

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
