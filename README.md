# ROCm-AI-Installer
A script that automatically installs all the required stuff to run selected AI apps on AMD Radeon 7900XTX.
It should also work on 7900XT cards.
For other cards, change HSA_OVERRIDE_GFX_VERSION and GFX at the beginning of the script (Not tested).

## Info
[![Version](https://img.shields.io/badge/Version-8.4-orange.svg)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)

> [!Note]
> Debian 13.1 with GNOME and Bash is recommended. Version 8.x is not tested on older systems.<br>
> On other distros, most of the python based apps should work, but manual installation of ROCm will be required.<br>

> [!Important]
> All apps and models are tested on a card with 24GB VRAM.<br>
> Some apps or models may not work on cards with less VRAM.

### Test platform:
|Name|Info|
|:---|:---|
|CPU|AMD Ryzen 9950X3D|
|GPU|AMD Radeon 7900XTX|
|RAM|64GB DDR5 6600MHz|
|Motherboard|ASRock B650E PG Riptide WiFi (BIOS 3.30)|
|OS|Debian 13.1|
|Kernel|6.12.43+deb13-amd64|
|ROCm|6.4.3|

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
|Artist|https://github.com/songrise/Artist/||
|Cinemo|https://huggingface.co/spaces/maxin-cn/Cinemo<br> https://github.com/maxin-cn/Cinemo||
|Ovis-U1-3B|https://huggingface.co/spaces/AIDC-AI/Ovis-U1-3B<br> https://github.com/AIDC-AI/Ovis-U1||

#### ComfyUI Addons

> [!Important]
> For GGUF Flux and Flux based models:<br>
> 1\. Accept accept the conditions to access its files and content on HugginFace website:<br>
> https://huggingface.co/black-forest-labs/FLUX.1-schnell <br>
> 2\. HugginFace token is required during installation.

|Name|Link|Additional information|
|:---|:---|:---|
|ComfyUI-Manager|https://github.com/ltdrdata/ComfyUI-Manager| Manage nodes of ComfyUI.<br> After first run change custom_nodes/ComfyUI-Manager/config.ini security_level to weak.|
|ComfyUI-GGUF|https://github.com/city96/ComfyUI-GGUF<br> https://github.com/calcuis/gguf|GGUF models loader.|
|ComfyUI-AuraSR|https://github.com/alexisrolland/ComfyUI-AuraSR<br> https://huggingface.co/fal/AuraSR<br> https://huggingface.co/fal/AuraSR-v2|ComfyUI node to upscale images.|
|AuraFlow-v0.3|https://huggingface.co/fal/AuraFlow-v0.3|Text to image model.|
|FLUX.1-schnell GGUF|https://huggingface.co/black-forest-labs/FLUX.1-schnell<br> https://huggingface.co/city96/FLUX.1-schnell-gguf|Text to image model.<br> Model quant: <b>Q8_0</b>|
|AnimePro FLUX GGUF|https://huggingface.co/advokat/AnimePro-FLUX|Text to image model.<br> Flux based.<br> Model quant: <b>Q5_K_M</b>|
|Flex.1-alpha GGUF|https://huggingface.co/ostris/Flex.1-alpha<br> https://huggingface.co/hum-ma/Flex.1-alpha-GGUF|Text to image model.<br>Flux based.<br>Model quant: <b>Q8_0</b>|
|Qwen-Image GGUF|https://huggingface.co/Qwen/Qwen-Image<br> https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI<br> https://huggingface.co/city96/Qwen-Image-gguf<br> https://huggingface.co/unsloth/Qwen2.5-VL-7B-Instruct-GGUF|Text to image model.<br> Qwen Image-Quant: <b>Q6_K</b><br> Qwen2.5-VL-7B-Instruct quant: <b>Q5_K_XL</b>|
|Qwen-Image-Edit GGUF|https://huggingface.co/Qwen/Qwen-Image-Edit<br>https://huggingface.co/calcuis/qwen-image-edit-gguf<br> https://huggingface.co/city96/Qwen-Image-gguf<br> https://huggingface.co/unsloth/Qwen2.5-VL-7B-Instruct-GGUF|Text to image model.<br> Qwen Image-Quant-Edit quant: <b>Q4_K_M</b><br> Qwen2.5-VL-7B-Instruct quant: <b>Q5_K_XL</b>|

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
|Chatterbox Multilingual|https://github.com/resemble-ai/chatterbox|Only Polish and English have been tested.<br> ThMay not read non-English characters.<br> Polish is fixed:<br> https://github.com/resemble-ai/chatterbox/issues/256<br> For other languages, you will need to add the changes manually in the multilingual_app.py file.<br> For a better effect in Polish, I recommend using lowercase letters for the entire text.|
|KaniTTS|https://github.com/nineninesix-ai/kani-tts||

###  3D generation
|Name|Links|Additional information|
|:---|:---|:---|
|TripoSG|https://github.com/VAST-AI-Research/TripoSG|Added custom simple UI.<br> Uses a modified version of PyTorch Cluster for ROCm https://github.com/Mateusz-Dera/pytorch_cluster_rocm.<br> Sometimes there are probelms with the preview, but the model should still be available for download.|
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

5\. Select ROCm installation if you are upgrading or running the script for the first time.

6\. If you are installing the script for the first time, restart system after this step.

7\. Install selected app.

8\. Go to the installation path with the selected app and run:
```bash
./run.sh
```
