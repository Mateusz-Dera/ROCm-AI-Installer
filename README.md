# ROCm-AI-Installer
A script that automatically installs all the required stuff to run selected AI interfaces on AMD Radeon 7900XTX.

## Info
[![Version](https://img.shields.io/badge/2.0-version-orange.svg)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)

Part of the installation script is based on this guide: https://github.com/nktice/AMD-AI/blob/main/ROCm6.0.md

### Supported interfaces
|Name|Enviroment|Links|Additional information|
|:---|:---|:---|:---|
|Stable Diffusion web UI|Python 3.11 with venv|https://github.com/AUTOMATIC1111/stable-diffusion-webui|Startup parameters are in the webui-user.sh file|
|Text generation web UI|Python 3.11 with venv|https://github.com/oobabooga/text-generation-webui<br/> https://github.com/arlo-phoenix/bitsandbytes-rocm-5.6<br/> https://github.com/ROCmSoftwarePlatform/flash-attention<br/> https://github.com/turboderp/exllamav2.git|Startup parameters are in the run.sh file<br> Tested: ExLlamav2, Transformers, llama.ccp|
|SillyTavern (1.11.2)<br> Smart Context<br> Silero TTS|Node + Python 3.11 with venv|https://github.com/SillyTavern/SillyTavern<br> https://github.com/SillyTavern/SillyTavern-Extras|SillyTavern and SillyTavern-Extras are launched separately<br> Startup parameters are in the run.sh files<br>SillyTavern must be connected to SillyTavern-Extras in settings<br>Smart Context requires an additional extension download in settings<br>![Smart Context](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/images/smart.png)|

### Test platform:
|Name|Info|
|:---|:---|
|CPU|AMD Ryzen 7900X3D (iGPU disabled in BIOS)|
|GPU|AMD Radeon 7900XTX|
|RAM|64GB DDR5 6600MHz|
|Motherboard|ASRock B650E PG Riptide WiFi (2.06.AS03 [Beta])|
|OS|Ubuntu 22.04|
|Kernel|6.5.0-14-generic|
|ROCm|6.0|

## Instalation:
> [!WARNING]
> First startup after installation of the selected interface may take longer.

> [!WARNING]
> This script does not download any models. If the interface does not have defaults, download your own.

> [!WARNING]
> If you update, back up your settings and models, as reinstalling deletes the selected interface directory

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
wget -O - https://example.com/script.sh | bash
```
4. Select installation path.
5. Select ROCm installation if you are upgrading or running the script for the first time.
6. Install selected interfaces
7. Go to the installation path with the selected interface and run:
```bash
./run.sh
```

### SillyTavern (1.11.2) with Smart Context and Silero TTS
(Node + Python 3.11 with venv)

> [!WARNING]
> SillyTavern, SillyTavern-Extras are launched separately.

> [!WARNING]
> Smart Context and Silero TTS extensions must be manually configured in SillyTavern settings and SillyTavern must be connected to SillyTavern-Extras.

![Connect](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/images/connect.png)

![Silero TTS](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/images/tts.png)

### AudioCraft
(Python 3.10 with venv)

https://github.com/facebookresearch/audiocraft