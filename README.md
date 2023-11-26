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
|OS|Ubuntu 23.10|

## Instalation:
TODO

## Supported AIs
### stable-diffusion-webui
(Python 3.11 with venv)
https://github.com/AUTOMATIC1111/stable-diffusion-webui

### text-generation-webui
(Python 3.10 with venv)
> [!TIP]
> If you want to modify the parameters at startup, modify the run.sh file in the text-generation-webui directory after installation.

https://github.com/oobabooga/text-generation-webui
https://github.com/arlo-phoenix/bitsandbytes-rocm-5.6
https://github.com/turboderp/exllama
https://github.com/turboderp/exllamav2.git

### SillyTavern with Extras and chromadb
TODO
https://github.com/SillyTavern/SillyTavern