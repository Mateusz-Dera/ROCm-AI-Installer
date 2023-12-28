# ROCm-AI-Installer
A script that automatically installs all the required stuff to run selected AI interfaces on AMD Radeon 7900XTX.

## Info
[![Version](https://img.shields.io/badge/2.0-version-orange.svg)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)

Part of the installation script is based on this guide: https://github.com/nktice/AMD-AI/blob/main/ROCm6.0.md

### Test platform:
|Name|Info|
|:---|:---|
|CPU|AMD Ryzen 7900X3D (iGPU disabled in BIOS)|
|GPU|AMD Radeon 7900XTX|
|RAM|64GB DDR5 6600MHz|
|Motherboard|ASRock B650E PG Riptide WiFi (BIOS 1.28)|
|OS|Ubuntu 22.04|
|Kernel|6.2.0-39-generic|
|ROCm|6.0|

## Instalation:
> [!WARNING]
> First startup after installation of the selected interface may take longer.

> [!WARNING]
> This script does not download any models. If the interface does not have defaults, download your own.

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
4. Go to the installation path with the selected interface and run:
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
* ~~exllama~~
* exllamav2

https://github.com/oobabooga/text-generation-webui

https://github.com/arlo-phoenix/bitsandbytes-rocm-5.6

https://github.com/turboderp/exllamav2.git

> [!TIP]
> If you want to modify the parameters at startup, modify the run.sh file in the text-generation-webui directory after installation.

> [!Caution]
> If you have more than one ROCm device and are having trouble getting it to work, replace the 0 in CUDA_VISIBLE_DEVICES with the number of the correct device.

### SillyTavern (1.11.0) with Smart Context
https://github.com/SillyTavern/SillyTavern

https://github.com/SillyTavern/SillyTavern-Extras

> [!WARNING]
> SillyTavern and SillyTavern-Extras are launched separately.

<!-- ### DreamCraft3D -->
<!-- (Python 3.11 with venv) -->
<!-- https://github.com/deepseek-ai/DreamCraft3D -->