# ROCm-AI-Installer
A script that automatically installs all the required stuff to run selected AI interfaces on AMD Radeon 7900XTX.

# Work in progress

## Info
[![Version](https://img.shields.io/badge/0.0-version-orange.svg)](https://github.com/Mateusz-Dera/Gasp/edit/main/README.md)

Part of the installation script is based on this guide: https://github.com/nktice/AMD-AI/blob/main/ROCm-5.7.md

### Test platform:
|Name|Info|
|:---|:---|
|CPU|AMD Ryzen 7900X3D|
|GPU|AMD Radeon 7900XTX|
|RAM|64GB DDR5 6600MHz|
|OS|Ubuntu 23.04|
|Kernel|6.2.0-37-generic|

## Instalation:
> [!WARNING]
> The first startup after installation of the selected interface may take longer.

> [!WARNING]
> This script does not download any models. If the interface does not have defaults, download your own.

1. Add the user to the required groups.
```bash
sudo adduser `whoami` video
sudo adduser `whoami` render
```
2. Reboot
3. TODO

## Supported AIs

### stable-diffusion-webui
TODO
(Python 3.11 with venv)
> [!TIP]
> If you want to modify the parameters at startup, modify the run.sh file in the text-generation-webui directory after installation.
https://github.com/AUTOMATIC1111/stable-diffusion-webui

### text-generation-webui
TODO fix exlama exlamav2
(Python 3.11 with venv)
> [!TIP]
> If you want to modify the parameters at startup, modify the run.sh file in the text-generation-webui directory after installation.

> [!WARNING]
> The script may show the error "o module named 'torchvision.transforms.functional_tensor'", this is normal.

https://github.com/oobabooga/text-generation-webui

https://github.com/arlo-phoenix/bitsandbytes-rocm-5.6

https://github.com/ROCmSoftwarePlatform/flash-attention

https://github.com/turboderp/exllama

https://github.com/turboderp/exllamav2.git

### SillyTavern with Extras and chromadb
TODO
https://github.com/SillyTavern/SillyTavern
