# ROCm-AI-Installer
A script that automatically installs all the required stuff to run selected AI interfaces on AMD Radeon 7900XTX.
It should also work on 7900XT cards.
For other cards, change HSA_OVERRIDE_GFX_VERSION at the beginning of the script (Not tested).

## Info
[![Version](https://img.shields.io/badge/5.3.1-version-orange.svg)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)

> [!Note]
> Ubuntu 24.04 is recommended. Version 5.x is not tested on older systems.

### Test platform:
|Name|Info|
|:---|:---|
|CPU|AMD Ryzen 7900X3D (iGPU disabled in BIOS)|
|GPU|AMD Radeon 7900XTX|
|RAM|64GB DDR5 6600MHz|
|Motherboard|ASRock B650E PG Riptide WiFi (3.08)|
|OS|Ubuntu 24.04.1|
|Kernel|6.8.0-49-generic|
|ROCm|6.2.2|

###  Text generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|KoboldCPP|Python 3.12 venv|https://github.com/YellowRoseCx/koboldcpp-rocm||
|Text generation web UI|Python 3.12 venv|https://github.com/oobabooga/text-generation-webui<br/> https://github.com/ROCm/bitsandbytes.git<br/> https://github.com/ROCmSoftwarePlatform/flash-attention<br/> https://github.com/turboderp/exllamav2|1. Tested: ExLlamav2, Transformers<br> 2. Requrements for Superbooga are installed, but the extension is not enabled by default<br> 3. Requrements for SuperboogaV2 are installed, but the extension is not enabled by default<br> 4. Remember to check Flash Attention|
|SillyTavern (1.12.7)|Node|https://github.com/SillyTavern/SillyTavern||

###  Image generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|Stable Diffusion web UI|Python 3.11 venv|https://github.com/AUTOMATIC1111/stable-diffusion-webui|1. Startup parameters are in the webui-user.sh file|
|ANIMAGINE XL 3.1|Python 3.12 venv|https://huggingface.co/spaces/cagliostrolab/animagine-xl-3.1</br> https://huggingface.co/cagliostrolab/animagine-xl-3.1||
|ComfyUI<br>ComfyUI-CLIPSeg<br>AuraFlow<br>AuraSR<br>FLUX.1-schnell|Python 3.12 venv|https://github.com/comfyanonymous/ComfyUI</br> https://github.com/biegert/ComfyUI-CLIPSeg</br> https://huggingface.co/fal/AuraFlow-v0.3</br> https://huggingface.co/fal/AuraSR</br> https://huggingface.co/fal/AuraSR-v2</br> https://github.com/alexisrolland/ComfyUI-AuraSR<br> https://huggingface.co/black-forest-labs/FLUX.1-schnell<br> https://huggingface.co/Comfy-Org/flux1-schnell/blob/main/|1. Flux examples: https://comfyanonymous.github.io/ComfyUI_examples/flux/#simple-to-use-fp8-checkpoint-version|
|Artist|Python 3.12 venv|https://github.com/songrise/Artist/||

###  Video generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|Cinemo|Python 3.12 venv|https://huggingface.co/spaces/maxin-cn/Cinemo<br>https://github.com/maxin-cn/Cinemo||

###  Music generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|AudioCraft|Python 3.12 venv|https://github.com/facebookresearch/audiocraft||

###  Voice generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|WhisperSpeech web UI|Python 3.12 venv|https://github.com/Mateusz-Dera/whisperspeech-webui<br> https://github.com/collabora/WhisperSpeech<br/> https://github.com/ROCmSoftwarePlatform/flash-attention||
|MeloTTS|Python 3.12 venv|https://github.com/myshell-ai/MeloTTS||
|MetaVoice|Python 3.12 venv|https://github.com/metavoiceio/metavoice-src.git<br>https://github.com/metavoiceio/metavoice-src/tree/sidroopdaska/faster_decoding|1. Script uses the faster_decoding branch.<br> 2. Telemetry is disabled by default|

###  3D generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|TripoSR|Python3.12 venv|https://github.com/VAST-AI-Research/TripoSR<br> https://github.com/ROCmSoftwarePlatform/flash-attention|1. It uses PyTorch ROCm, but torchmcubes is built for the CPU. This method is still faster than using just PyTorch CPU-only version.|

###  Tools
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|ExLlamaV2|Python3.12 venv|https://github.com/turboderp/exllamav2|1. LLM conversion to exl2 format using convert.py<br>2.Run:<br>```export HSA_OVERRIDE_GFX_VERSION=11.0.0```<br>```export CUDA_VISIBLE_DEVICES=0```<br>```source .venv/bin/activate```|

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
3\. Run installer 
```bash
bash ./install.sh
```
4\. Select installation path.

5\. Select ROCm installation if you are upgrading or running the script for the first time.

6\. Install selected interfaces

7\. Go to the installation path with the selected interface and run:
```bash
./run.sh
```
