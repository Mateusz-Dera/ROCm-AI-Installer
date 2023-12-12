# ROCm-AI-Installer
A script that automatically installs all the required stuff to run selected AI interfaces on AMD Radeon 7900XTX.

## Info
[![Version](https://img.shields.io/badge/1.0-version-orange.svg)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)

Part of the installation script is based on this guide: https://github.com/nktice/AMD-AI/blob/main/ROCm-5.7.md

### Test platform:
|Name|Info|
|:---|:---|
|CPU|AMD Ryzen 7900X3D (iGPU disabled in BIOS)|
|GPU|AMD Radeon 7900XTX|
|RAM|64GB DDR5 6600MHz|
|Motherboard|ASRock B650E PG Riptide WiFi (BIOS 1.28)|
|OS|Ubuntu 23.04|
|Kernel|6.2.0-39-generic|
|ROCm|5.7.2|

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

## Supported AIs

### stable-diffusion-webui
(Python 3.11 with venv)
https://github.com/AUTOMATIC1111/stable-diffusion-webui

> [!TIP]
> If you want to modify the parameters at startup, modify the run.sh file in the text-generation-webui directory after installation.

> [!TIP]
> Superboogav2 requirements are installed, but the extension is disabled by default.

### text-generation-webui
(Python 3.11 with venv)

Supported:
* llamaccp
* exllama
* exllamav2

https://github.com/oobabooga/text-generation-webui

https://github.com/arlo-phoenix/bitsandbytes-rocm-5.6

https://github.com/ROCmSoftwarePlatform/flash-attention

https://github.com/turboderp/exllama

https://github.com/turboderp/exllamav2.git

> [!TIP]
> If you want to modify the parameters at startup, modify the run.sh file in the text-generation-webui directory after installation.

> [!WARNING]
> The script may show the error "o module named 'torchvision.transforms.functional_tensor'", this is normal.

> [!Caution]
> If you have more than one ROCm device and are having trouble getting it to work, replace the 0 in CUDA_VISIBLE_DEVICES with the number of the correct device.

### SillyTavern (1.11.0) with Smart Context
https://github.com/SillyTavern/SillyTavern

https://github.com/SillyTavern/SillyTavern-Extras

> [!WARNING]
> SillyTavern and SillyTavern-Extras are launched separately.

<!-- ### koboldcpp-rocm
https://github.com/YellowRoseCx/koboldcpp-rocm -->