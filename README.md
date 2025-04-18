# ROCm-AI-Installer
A script that automatically installs all the required stuff to run selected AI interfaces on AMD Radeon 7900XTX.
It should also work on 7900XT cards.
For other cards, change HSA_OVERRIDE_GFX_VERSION and GFX at the beginning of the script (Not tested).

## Info
[![Version](https://img.shields.io/badge/6.4.1-version-orange.svg)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)

> [!Note]
> Ubuntu 24.04.2 LTS is recommended. Version 6.x is not tested on older systems.

### Test platform:
|Name|Info|
|:---|:---|
|CPU|AMD Ryzen 7900X3D (iGPU disabled in BIOS)|
|GPU|AMD Radeon 7900XTX|
|RAM|64GB DDR5 6600MHz|
|Motherboard|ASRock B650E PG Riptide WiFi (3.18.AS02 Beta)|
|OS|Ubuntu 24.04.2 LTS|
|Kernel|6.11.0-21-generic|
|ROCm|6.3.4|

###  Text generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|KoboldCPP|Python 3.12 venv|https://github.com/YellowRoseCx/koboldcpp-rocm|GGML and GGUF models.|
|Text generation web UI|Python 3.12 venv|https://github.com/oobabooga/text-generation-webui<br/> https://github.com/ROCm/bitsandbytes.git<br/>  https://github.com/turboderp/exllamav2|ExLlamaV2 and Transformers models.|
|SillyTavern (1.12.13)|Node|https://github.com/SillyTavern/SillyTavern||
|llama.cpp|C++|https://github.com/ggerganov/llama.cpp|1. Put model.gguf into llama.cpp folder.<br> 2. Change context size in run.sh file (Default: 32768).<br> 3. Set GPU offload layers in run.sh file (Default: 1)|

###  Image generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|ComfyUI|Python 3.12 venv|https://github.com/comfyanonymous/ComfyUI|1. Workflows templates are in the workflows folder.|
|Artist|Python 3.12 venv|https://github.com/songrise/Artist/||
|Animagine XL 4.0|Python 3.12 venv|https://huggingface.co/cagliostrolab/animagine-xl-4.0<br> https://huggingface.co/spaces/cagliostrolab/animagine-xl-4.0||

#### ComfyUI Addons
|Name|Link|Additional information|
|:---|:---|:---|
|ComfyUI-Manager|https://github.com/ltdrdata/ComfyUI-Manager| Manage nodes of ComfyUI.|
|ComfyUI-GGUF|https://github.com/city96/ComfyUI-GGUF<br> https://huggingface.co/city96/t5-v1_1-xxl-encoder-bf16<br> https://huggingface.co/openai/clip-vit-large-patch14<br> https://huggingface.co/black-forest-labs/FLUX.1-schnell|GGUF models loader.|
|ComfyUI-AuraSR|https://github.com/alexisrolland/ComfyUI-AuraSR<br> https://huggingface.co/fal/AuraSR<br> https://huggingface.co/fal/AuraSR-v2|ComfyUI node to upscale images.|
|AuraFlow-v0.3|https://huggingface.co/fal/AuraFlow-v0.3|Text to image model.|
|FLUX.1-schnell GGUF|https://huggingface.co/black-forest-labs/FLUX.1-schnell<br> https://huggingface.co/city96/FLUX.1-schnell-gguf|Text to image model.|
|AnimePro FLUX GGUF|https://civitai.com/models/934628?modelVersionId=1053818|Text to image model.|
|Flex.1-alpha GGUF|https://huggingface.co/ostris/Flex.1-alpha<br> https://huggingface.co/hum-ma/Flex.1-alpha-GGUF|Text to image model.|


###  Video generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|Cinemo|Python 3.12 venv|https://huggingface.co/spaces/maxin-cn/Cinemo<br> https://github.com/maxin-cn/Cinemo||

###  Music generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|AudioCraft|Python 3.12 venv|https://github.com/facebookresearch/audiocraft||

###  Voice generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|WhisperSpeech web UI|Python 3.12 venv|https://github.com/Mateusz-Dera/whisperspeech-webui<br> https://github.com/collabora/WhisperSpeech||
|MeloTTS|Python 3.12 venv|https://github.com/myshell-ai/MeloTTS||
|MetaVoice|Python 3.12 venv|https://github.com/metavoiceio/metavoice-src<br> https://github.com/metavoiceio/metavoice-src/tree/sidroopdaska/faster_decoding|1. Script uses the faster_decoding fork by sidroopdaska.<br> 2. Telemetry is disabled by default|
|F5-TTS|Python 3.12 venv|https://github.com/SWivid/F5-TTS|1. Remember to select the voice file when using the interface.|
|Matcha-TTS|Python 3.12 venv|https://github.com/shivammehta25/Matcha-TTS||
|StableTTS|Python 3.12 venv|https://github.com/lpscr/StableTTS||

###  3D generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|TripoSR|Python3.12 venv|https://github.com/VAST-AI-Research/TripoSR|1. It uses PyTorch ROCm, but torchmcubes is built for the CPU. This method is still faster than using just PyTorch CPU-only version.|
|TripoSG|Python3.12 venv|https://github.com/VAST-AI-Research/TripoSG|1. Added custom simple UI. 2. When accessing the interface from the VS Code tunnel, preview of generated 3D files may not be available.|

###  Tools
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|Fastfetch|Shell|https://github.com/fastfetch-cli/fastfetch|1. Custom Fastfetch configuration with GPU memory info.|

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
