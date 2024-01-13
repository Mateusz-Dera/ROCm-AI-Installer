# ROCm-AI-Installer
A script that automatically installs all the required stuff to run selected AI interfaces on AMD Radeon 7900XTX.

## Info
[![Version](https://img.shields.io/badge/1.3-version-orange.svg)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)

Part of the installation script is based on this guide: https://github.com/nktice/AMD-AI/blob/main/ROCm-5.7.md

### Test platform:
|Name|Info|
|:---|:---|
|CPU|AMD Ryzen 7900X3D (iGPU disabled in BIOS)|
|GPU|AMD Radeon 7900XTX|
|RAM|64GB DDR5 6600MHz|
|Motherboard|ASRock B650E PG Riptide WiFi (BIOS 1.30.AS02 [Beta])|
|OS|Ubuntu 22.04|
|Kernel|6.5.0-14-generic|
|ROCm|5.7.3|

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

## Supported

### stable-diffusion-webui
(Python 3.11 with venv)

https://github.com/AUTOMATIC1111/stable-diffusion-webui

> [!TIP]
> If you want to modify the parameters at startup, modify the webui-user.sh file in the stable-diffusion-webui directory after installation.

### text-generation-webui
(Python 3.11 with venv)

Supported:
* llamaccp
* exllamav2

exllama is no longer supported

https://github.com/oobabooga/text-generation-webui

https://github.com/arlo-phoenix/bitsandbytes-rocm-5.6

https://github.com/ROCmSoftwarePlatform/flash-attention

https://github.com/turboderp/exllamav2.git

> [!TIP]
> If you want to modify the parameters at startup, modify the run.sh file in the text-generation-webui directory after installation.

> [!TIP]
> Superboogav2 requirements are installed, but the extension is disabled by default.

> [!Caution]
> If you have more than one ROCm device and are having trouble getting it to work, replace the 0 in CUDA_VISIBLE_DEVICES with the number of the correct device.

### SillyTavern (1.11.1) with Smart Context and Silero TTS
(Node + Python 3.11 with venv)

https://github.com/SillyTavern/SillyTavern

https://github.com/SillyTavern/SillyTavern-Extras

> [!WARNING]
> SillyTavern, SillyTavern-Extras are launched separately.

> [!WARNING]
> Smart Context and Silero TTS extensions must be manually configured in SillyTavern settings. SillyTavern must be connected to SillyTavern-Extras.

![Smart Context](https://github.com/Mateusz-Dera/ROCm-AI-Installer/img/smart.png)

![Silero TTS](https://github.com/Mateusz-Dera/ROCm-AI-Installer/img/tts.png)