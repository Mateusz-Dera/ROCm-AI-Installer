# ROCm-AI-Installer
A script that automatically installs the required dependencies to run selected AI applications on AMD Radeon GPUs (default: RX 7900 XTX). For other cards and architectures, the <b>HSA_OVERRIDE_GFX_VERSION</b> and <b>GFX</b> variables in the <b>install.sh</b> file should be modified accordingly (Not tested).

## Info
[![Version](https://img.shields.io/badge/Version-9.0-orange.svg)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)

> [!Note]
> Debian 13.1 is recommended. Version 9.x is not tested on older systems.<br>
> On other distros, most of the python based applications should work, but manual installation of ROCm will be required.<br>

> [!Important]
> All models and applications are tested on a GPU with 24GB of VVRAM.<br>
> Some applications may not work on GPUs with less VRAM.

### Test platform:
|Name|Info|
|:---|:---|
|CPU|AMD Ryzen 5 7500F|
|GPU|AMD Radeon 7900XTX|
|RAM|64GB DDR5 6600MHz|
|Motherboard|Gigabyte X870 AORUS ELITE WIFI7 (BIOS F8e)|
|OS|Debian 13.1|
|Kernel|6.12.48+deb13-amd64|
|ROCm|7.1|

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

#### ComfyUI Addons

> [!Important]
> For GGUF Flux and Flux based models:<br>
> 1\. Accept accept the conditions to access its files and content on HugginFace website:<br>
> https://huggingface.co/black-forest-labs/FLUX.1-schnell <br>
> 2\. HugginFace token is required during installation.

|Name|Link|Additional information|
|:---|:---|:---|
|ComfyUI-Manager|https://github.com/ltdrdata/ComfyUI-Manager| Manage nodes of ComfyUI.<br> After first run change custom_nodes/ComfyUI-Manager/config.ini security_level to weak.|
|GGUF|https://github.com/calcuis/gguf|GGUF models loader.|
|ComfyUI-AuraSR|https://github.com/alexisrolland/ComfyUI-AuraSR<br> https://huggingface.co/fal/AuraSR<br> https://huggingface.co/fal/AuraSR-v2|ComfyUI node to upscale images.|
|AuraFlow-v0.3|https://huggingface.co/fal/AuraFlow-v0.3|Text to image model.|
|FLUX.1-schnell GGUF|https://huggingface.co/black-forest-labs/FLUX.1-schnell<br> https://huggingface.co/city96/FLUX.1-schnell-gguf|Text to image model.<br> Model quant: <b>Q8_0</b>|
|AnimePro FLUX GGUF|https://huggingface.co/advokat/AnimePro-FLUX|Text to image model.<br> Flux based.<br> Model quant: <b>Q5_K_M</b>|
|Flex.1-alpha GGUF|https://huggingface.co/ostris/Flex.1-alpha<br> https://huggingface.co/hum-ma/Flex.1-alpha-GGUF|Text to image model.<br>Flux based.<br>Model quant: <b>Q8_0</b>|
|Qwen-Image GGUF|https://huggingface.co/Qwen/Qwen-Image<br> https://huggingface.co/QuantStack/Qwen-Image-Edit-2509-GGUF<br> https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI<br> https://huggingface.co/lightx2v/Qwen-Image-Lightning|Text to image model.<br> Qwen Image-Quant: <b>Q6_K</b>|
Qwen-Image-Edit GGUF|https://huggingface.co/Qwen/Qwen-Image-Edit<br> https://huggingface.co/calcuis/qwen-image-edit-ggu<br> https://huggingface.co/Comfy-Org/Qwen-Image-Edit_ComfyUI<br> https://huggingface.co/city96/Qwen-Image-gguf<br> https://huggingface.co/lightx2v/Qwen-Image-Lightning|Text to image model.<br> Qwen Image-Quant-Edit quant: <b>Q4_K_M</b>|
Qwen-Image-Edit-2509 GGUF|https://huggingface.co/Qwen/Qwen-Image-Edit-2509<br> https://huggingface.co/calcuis/qwen-image-edit-gguf<br> https://huggingface.co/Comfy-Org/Qwen-Image-Edit_ComfyUI<br> https://huggingface.co/city96/Qwen-Image-gguf<br> https://huggingface.co/lightx2v/Qwen-Image-Lightning|Text to image model.<br> Qwen Image-Quant-Edit-2509 quant: <b>Q4_0</b>|
|Wan2.2-TI2V-5B|https://huggingface.co/Wan-AI/Wan2.2-TI2V-5B<br> https://github.com/Wan-Video/Wan2.2<br> https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged<br>|Text to video model.<br> Supported <b>5B</b> version.|

###  Music generation
|Name|Links|Additional information|
|:---|:---|:---|
|ACE-Step|https://github.com/ace-step/ACE-Step||
|YuE-UI|https://github.com/joeljuvel/YuE-UI<br> https://huggingface.co/m-a-p/xcodec_mini_infer<br> https://huggingface.co/Doctor-Shotgun/YuE-s1-7B-anneal-en-cot-exl2<br> https://huggingface.co/Doctor-Shotgun/YuE-s2-1B-general-exl2|Interface PyTorch uses PyTorch 2.6.0<br> YuE-s1-7B-anneal-en-cot-exl2 quant: <b>4.25bpw-h6</b><br> YuE-s2-1B-general-exl2 quant: <b>8.0bpw-h8</b>|

###  Voice generation
|Name|Links|Additional information|
|:---|:---|:---|
|WhisperSpeech web UI|https://github.com/Mateusz-Dera/whisperspeech-webui<br> https://github.com/collabora/WhisperSpeech||
|F5-TTS|https://github.com/SWivid/F5-TTS|Remember to select voice.|
|Matcha-TTS|https://github.com/shivammehta25/Matcha-TTS||
|Dia|https://github.com/nari-labs/dia<br> https://github.com/tralamazza/dia/tree/optional-rocm-cuda|Script uses the optional-rocm-cuda fork by tralamazza.|
|IMS-Toucan|https://github.com/DigitalPhonetics/IMS-Toucan.git|Interface PyTorch uses PyTorch 2.4.0|
|Chatterbox Multilingual|https://github.com/resemble-ai/chatterbox|Only Polish and English have been tested.<br> May not read non-English characters.<br> Polish is fixed:<br> https://github.com/resemble-ai/chatterbox/issues/256<br> For other languages, you will need to add the changes manually in the multilingual_app.py file.<br> For a better effect in Polish, I recommend using lowercase letters for the entire text.|
|KaniTTS|https://github.com/nineninesix-ai/kani-tts||

###  3D generation
|Name|Links|Additional information|
|:---|:---|:---|
|PartCrafter|https://github.com/wgsxm/PartCrafter|Added custom simple UI.<br> Uses a modified version of PyTorch Cluster for ROCm https://github.com/Mateusz-Dera/pytorch_cluster_rocm.|

###  Tools
|Name|Links|Additional information|
|:---|:---|:---|
|Fastfetch|https://github.com/fastfetch-cli/fastfetch|Custom Fastfetch configuration with GPU memory info.<br> Supports also NVIDIA graphics cards (nvidia-smi needed).<br>If you want your own logo, place the *asci.txt* file in the *~/.config/fastfetch directory.*|

## Instalation:
> [!Note]
> First startup after installation of the selected app may take longer.

> [!Important] 
> If app does not download any default models, download your own.

> [!Caution]
> If you update, back up your settings and models. Reinstallation deletes the previous directories.

1\. If you have installed uv other than through <b>pipx</b>, uninstall <b>uv</b> first.

2\. Clone repository 
```bash
git clone https://github.com/Mateusz-Dera/ROCm-AI-Installer.git
```

3\. Run installer 
```bash
bash ./install.sh
```

4\. Select installation path.

5\. Select <b>Install required packages</b> if you are upgrading or running the script for the first time.

6\. If you are installing the script for the first time, restart system after this step.

7\. Install selected app.

8\. Go to the installation path with the selected app and run:
```bash
./run.sh
```
