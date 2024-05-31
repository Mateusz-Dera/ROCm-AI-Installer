# ROCm-AI-Installer
A script that automatically installs all the required stuff to run selected AI interfaces on AMD Radeon 7900XTX.

## Info
[![Version](https://img.shields.io/badge/4.0-version-orange.svg)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)

> [!Note]
> Ubuntu 24.04 is recommended. Version 4.0 is not tested on older versions.

Part of the installation script is based on this guide: https://github.com/nktice/AMD-AI/blob/main/ROCm6.0.md

### Test platform:
|Name|Info|
|:---|:---|
|CPU|AMD Ryzen 7900X3D (iGPU disabled in BIOS)|
|GPU|AMD Radeon 7900XTX|
|RAM|64GB DDR5 6600MHz|
|Motherboard|ASRock B650E PG Riptide WiFi (2.10)|
|OS|Ubuntu 24.04|
|Kernel|6.8.0-31-generic|
|ROCm|6.1.1|


### Text generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|KoboldCPP|Python 3.11 venv|https://github.com/YellowRoseCx/koboldcpp-rocm||
|Text generation web UI|Python 3.11 venv|https://github.com/oobabooga/text-generation-webui<br/> https://github.com/arlo-phoenix/bitsandbytes-rocm-5.6<br/> https://github.com/ROCmSoftwarePlatform/flash-attention<br/> https://github.com/turboderp/exllamav2|1. Tested: ExLlamav2, Transformers, llama.ccp<br> 2. Requrements for Superbooga are installed, but the extension is not enabled by default |
|SillyTavern (1.12.0)|Node|https://github.com/SillyTavern/SillyTavern|1. Extras project is discontinued and removed from the script.<br> https://github.com/SillyTavern/SillyTavern-Extras|

### Image generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|Stable Diffusion web UI|Python 3.11 venv|https://github.com/AUTOMATIC1111/stable-diffusion-webui|1. Startup parameters are in the webui-user.sh file|
|ANIMAGINE XL 3.1|Python 3.12 venv|https://huggingface.co/spaces/cagliostrolab/animagine-xl-3.1<br> https://huggingface.co/cagliostrolab/animagine-xl-3.1||

### Music generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|AudioCraft|Python 3.11 venv|https://github.com/facebookresearch/audiocraft||

### Voice generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|WhisperSpeech web UI|Python 3.11 venv|https://github.com/Mateusz-Dera/whisperspeech-webui<br> https://github.com/collabora/WhisperSpeech<br/> https://github.com/ROCmSoftwarePlatform/flash-attention||

### 3D generation
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|TripoSR|Python3.12 venv|https://github.com/VAST-AI-Research/TripoSR<br> https://github.com/ROCmSoftwarePlatform/flash-attention.git|1. It uses PyTorch ROCm, but torchmcubes is built for the CPU. This method is still faster than using just PyTorch CPU-only version.|

## Instalation:
> [!Note]
> First startup after installation of the selected interface may take longer.

> [!Important]
> This script does not download any models. If the interface does not have defaults, download your own.

> [!Caution]
> If you update, back up your settings and models. Reinstallation deletes the previous directories.

1. Add the user to the required groups.
```bash
sudo adduser `whoami` video
sudo adduser `whoami` render
```
2. Reboot
```bash
sudo reboot
```
3. Run installer 
```bash
bash ./install.sh
```
4. Select installation path.
5. Select ROCm installation if you are upgrading or running the script for the first time.
6. Install selected interfaces
7. Go to the installation path with the selected interface and run:
```bash
./run.sh
```
