#!/bin/bash

# ROCM-AI-Installer
# Copyright © 2023-2025 Mateusz Dera

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# CONTAINER
basic_container(){
    # Check if rocm container is running
    if ! podman ps --format "{{.Names}}" | grep -q "^rocm$"; then
        echo "Container rocm is not running. Starting..."
        podman start rocm
    fi
}

# GIT
basic_git(){
    local REPO=$1
    local COMMIT=$2
    FOLDER=$(basename "$REPO")

    podman exec -t rocm bash -c "cd /AI && echo $FOLDER && if [ -d $FOLDER ]; then rm -rf $FOLDER; fi"
    podman exec -it rocm bash -c "cd /AI && git clone $REPO && cd $FOLDER && git checkout $COMMIT"
}

# VENV
basic_venv(){
    local REPO=$1
    local PYTHON=${2:-3.13}
    FOLDER=$(basename "$REPO")

    podman exec -it rocm bash -c "cd /AI/$FOLDER && uv venv --python $PYTHON"
}

# REQUIREMENTS
basic_requirements(){
    local REPO=$1
    FOLDER=$(basename "$REPO")
    REQUIREMENTS=$(tr '\n' ' ' < "$SCRIPT_DIR/requirements/$FOLDER.txt")

    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install $REQUIREMENTS"
}

# RUN
basic_run(){
    local REPO=$1
    local COMMAND="$2"
    local VENV=${3:-"&& source .venv/bin/activate &&"}
    FOLDER=$(basename "$REPO")

    podman exec -t rocm bash -c "cat > /AI/$FOLDER/run.sh << RUNEOF
#!/bin/bash
# Check if rocm container is running
if ! podman ps --format \"{{.Names}}\" | grep -q \"^rocm\\\$\"; then
    echo \"Container rocm is not running. Starting...\"
    podman start rocm
fi
podman exec -it rocm bash -c \"cd /AI/$FOLDER $VENV $COMMAND\"
RUNEOF
chmod +x /AI/$FOLDER/run.sh"
}

# PIP
basic_pip(){
    local REPO=$1
    local LINK=$2
    FOLDER=$(basename "$REPO")

    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install $LINK"
}

# KoboldCPP
install_koboldcpp() {
    REPO="https://github.com/YellowRoseCx/koboldcpp-rocm"
    COMMIT="b4fa4f897f0c75a1e8d45e8247a14c6053548a61"
    COMMAND="uv run koboldcpp.py"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && make LLAMA_HIPBLAS=1 -j\$(nproc)"
    basic_run "$REPO" "$COMMAND"
}

# llama.cpp
install_llama_cpp() {
    REPO="https://github.com/ggml-org/llama.cpp"
    COMMIT="9e6649ecf244a99749dacc28fc4f49f7d6ad6f60"
    COMMAND="./build/bin/llama-server -m model.gguf --host 0.0.0.0 --port 8080 --ctx-size 32768 --gpu-layers 1"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    PODMAN='HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" cmake -S . -B build -DLLAMA_CURL=OFF -DGGML_HIP=ON -DAMDGPU_TARGETS=$GFX -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release -- -j$(($(nproc) - 1))'
    podman exec -it rocm bash -c "cd /AI/$FOLDER && $PODMAN"
    basic_run "$REPO" "$COMMAND" "&&"
}

# Text generation web UI
install_text_generation_web_ui() {
    REPO="https://github.com/oobabooga/text-generation-webui"
    COMMIT="34804f93540ca5dffd86e27ce8af55184d2b5096"
    COMMAND="uv run server.py --api --listen --extensions sd_api_pictures send_pictures gallery"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"

    # bitsandbytes
    basic_pip "$REPO" "git+https://github.com/ROCm/bitsandbytes.git@4fa939b3883ca17574333de2935beaabf71b2dba"

    # ExLlamaV2
    basic_pip "$REPO" "https://github.com/turboderp-org/exllamav2/releases/download/v0.3.2/exllamav2-0.3.2+rocm6.4.torch2.8.0-cp313-cp313-linux_x86_64.whl"

    # llama_cpp
    basic_pip "$REPO" "https://github.com/oobabooga/llama-cpp-binaries/releases/download/v0.69.0/llama_cpp_binaries-0.69.0+rocm6.4.4-py3-none-linux_x86_64.whl"

    basic_run "$REPO" "$COMMAND"
}

# SillyTavern
install_sillytavern(){
    REPO="https://github.com/SillyTavern/SillyTavern"
    COMMIT="088ce0e962b138bb60958f8d32b549a4123f6508"
    COMMAND="bash start.sh"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_run "$REPO" "$COMMAND" "&&"

    podman exec -t rocm bash -c "cd $FOLDER/default && sed -i 's/listen: false/listen: true/' config.yaml"
    podman exec -t rocm bash -c "cd $FOLDER/default && sed -i 's/whitelistMode: true/whitelistMode: false/' config.yaml"
    podman exec -t rocm bash -c "cd $FOLDER/default && sed -i 's/basicAuthMode: false/basicAuthMode: true/' config.yaml"
}

# SillyTavern WhisperSpeech web UI
install_sillytavern_whisperspeech_web_ui() {
    REPO="https://github.com/Mateusz-Dera/whisperspeech-webui"
    COMMIT="37e2ddf59664dd1604cc41b2660f48d1fa1af173"

    basic_container

    # Check if SillyTavern is installed
    if ! podman exec -t rocm bash -c "[ -d /AI/SillyTavern ]"; then
        echo "SillyTavern is not installed. Please install SillyTavern first."
        return 1
    fi

    # Install WhisperSpeech web UI extension
    podman exec -it rocm bash -c "cd /AI/SillyTavern/public/scripts/extensions/third-party && \
        if [ -d whisperspeech-webui ]; then rm -rf whisperspeech-webui; fi && \
        git clone $REPO && \
        mv ./whisperspeech-webui ./whisperspeech-webui-temp && \
        cd whisperspeech-webui-temp && \
        git checkout $COMMIT && \
        mv ./whisperspeech-webui ../ && \
        cd .. && \
        rm -rf whisperspeech-webui-temp"
}

# ComfyUI
install_comfyui() {
    REPO="https://github.com/comfyanonymous/ComfyUI"
    COMMIT="a5e85017d8574cb99024d320f7a53a77a9e6aa5a"
    COMMAND="MIOPEN_FIND_MODE=2 PYTORCH_TUNABLEOP_ENABLED=1 uv run main.py --listen --reserve-vram 1.0 --preview-method auto --bf16-vae --disable-xformers --lowvram"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"

    local gguf=0
    local qwen=0
    local qwen2509=0

    # Process each selected choice
    for choice in $CHOICES; do
        case $choice in
            '"1"')
                # ComfyUI-Manager
                podman exec -it rocm bash -c "cd /AI/$FOLDER/custom_nodes && \
                    git clone https://github.com/ltdrdata/ComfyUI-Manager && \
                    cd ComfyUI-Manager && \
                    git checkout c7f03ad64e70ddda3b6e015e807f111b4ace45cf"
                ;;
            '"2"')
                gguf=1
                ;;
            '"3"')
                # AuraSR
                podman exec -it rocm bash -c "cd /AI/$FOLDER/custom_nodes && \
                    git clone https://github.com/alexisrolland/ComfyUI-AuraSR --recursive && \
                    cd ComfyUI-AuraSR && \
                    git checkout 29c97cf9d7bda74d3020678a03545d74dfccadf4"

                podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
                    hf download fal/AuraSR-v2 model.safetensors --revision ff452185a7c8b51206dd62c21c292e7baad5c3a3 --local-dir /AI/$FOLDER/models/upscale_models && \
                    mv /AI/$FOLDER/models/upscale_models/model.safetensors /AI/$FOLDER/models/upscale_models/aura_sr_v2.safetensors && \
                    hf download fal/AuraSR model.safetensors --revision 87da2f52b29b6351391f71c74de581c393fc19f5 --local-dir /AI/$FOLDER/models/upscale_models && \
                    mv /AI/$FOLDER/models/upscale_models/model.safetensors /AI/$FOLDER/models/upscale_models/aura_sr.safetensors && \
                    uv pip install aura-sr==0.0.4"
                ;;
            '"4"')
                # AuraFlow
                podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
                    hf download fal/AuraFlow-v0.3 aura_flow_0.3.safetensors --revision 2cd8588f04c886002be4571697d84654a50e3af3 --local-dir /AI/$FOLDER/models/checkpoints"
                ;;
            '"8"')
                gguf=1
                qwen=1
                # Qwen-Image
                podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
                    hf download city96/Qwen-Image-gguf qwen-image-Q6_K.gguf --revision e77babc55af111419e1714a7a0a848b9cac25db7 --local-dir /AI/$FOLDER/models/diffusion_models"
                ;;
            '"9"')
                gguf=1
                qwen=1
                # Qwen-Image-Edit
                podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
                    hf download calcuis/qwen-image-edit-gguf qwen-image-edit-q4_k_s.gguf --revision 113bedf317589c2e8f6d6f7fde3a40dbf90ef6eb --local-dir /AI/$FOLDER/models/diffusion_models"
                ;;
            '"10"')
                gguf=1
                qwen2509=1
                # Qwen-Image-Edit-2509
                podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
                    hf download QuantStack/Qwen-Image-Edit-2509-GGUF Qwen-Image-Edit-2509-Q4_0.gguf --revision 37f16c813605380a97900aac19433ffb1622817a --local-dir /AI/$FOLDER/models/diffusion_models"
                ;;
            '"11"')
                # Wan 2.2
                TEMP_DIR="ComfyUI-Wan2.2"
                WAN_COMMIT="bcd839189de217703be0450c4f3736062a4a4873"

                podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
                    cd /tmp && \
                    if [ -d '$TEMP_DIR' ]; then rm -rf '$TEMP_DIR'; fi && \
                    mkdir $TEMP_DIR && \
                    hf download Comfy-Org/Wan_2.2_ComfyUI_Repackaged split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors --revision $WAN_COMMIT --local-dir /tmp/$TEMP_DIR && \
                    mv /tmp/$TEMP_DIR/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors /AI/$FOLDER/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors && \
                    hf download Comfy-Org/Wan_2.2_ComfyUI_Repackaged split_files/vae/wan_2.1_vae.safetensors --revision $WAN_COMMIT --local-dir /tmp/$TEMP_DIR && \
                    mv /tmp/$TEMP_DIR/split_files/vae/wan_2.1_vae.safetensors /AI/$FOLDER/models/vae/wan_2.1_vae.safetensors && \
                    hf download Comfy-Org/Wan_2.2_ComfyUI_Repackaged split_files/vae/wan2.2_vae.safetensors --revision $WAN_COMMIT --local-dir /tmp/$TEMP_DIR && \
                    mv /tmp/$TEMP_DIR/split_files/vae/wan2.2_vae.safetensors /AI/$FOLDER/models/vae/wan2.2_vae.safetensors && \
                    hf download Comfy-Org/Wan_2.2_ComfyUI_Repackaged split_files/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors --revision $WAN_COMMIT --local-dir /tmp/$TEMP_DIR && \
                    mv /tmp/$TEMP_DIR/split_files/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors /AI/$FOLDER/models/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors && \
                    rm -rf /tmp/$TEMP_DIR"
                ;;
            "")
                break
                ;;
            *)
                echo "Unknown option: $choice"
                ;;
        esac
    done

    if [ $gguf -eq 1 ]; then
        podman exec -it rocm bash -c "cd /AI/$FOLDER/custom_nodes && \
            git clone https://github.com/calcuis/gguf && \
            cd gguf && \
            git checkout a64ccbf6c694a46c181a444a1ac9d2d810607309"
    fi

    if [ $qwen -eq 1 ]; then
        # Lightning
        podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
            hf download lightx2v/Qwen-Image-Lightning Qwen-Image-Lightning-4steps-V2.0.safetensors --revision 21e79ba3c2cb6454834051ea973ffcd04ff1993f --local-dir /AI/$FOLDER/models/loras && \
            hf download lightx2v/Qwen-Image-Lightning Qwen-Image-Lightning-8steps-V2.0.safetensors --revision 21e79ba3c2cb6454834051ea973ffcd04ff1993f --local-dir /AI/$FOLDER/models/loras"
    fi

    if [ $qwen2509 -eq 1 ]; then
        # Lightning
        podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
            hf download lightx2v/Qwen-Image-Lightning Qwen-Image-Edit-2509/Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors --revision 21e79ba3c2cb6454834051ea973ffcd04ff1993f --local-dir /AI/$FOLDER/models/loras && \
            hf download lightx2v/Qwen-Image-Lightning Qwen-Image-Edit-2509/Qwen-Image-Edit-2509-Lightning-8steps-V1.0-bf16.safetensors --revision 21e79ba3c2cb6454834051ea973ffcd04ff1993f --local-dir /AI/$FOLDER/models/loras && \
            mv /AI/$FOLDER/models/loras/Qwen-Image-Edit-2509/Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors /AI/$FOLDER/models/loras/Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors && \
            mv /AI/$FOLDER/models/loras/Qwen-Image-Edit-2509/Qwen-Image-Edit-2509-Lightning-8steps-V1.0-bf16.safetensors /AI/$FOLDER/models/loras/Qwen-Image-Edit-2509-Lightning-8steps-V1.0-bf16.safetensors && \
            rm -rf /AI/$FOLDER/models/loras/Qwen-Image-Edit-2509"
    fi

    if [ $qwen -eq 1 -o $qwen2509 -eq 1 ]; then
        # VL-7B
        podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
            hf download Comfy-Org/Qwen-Image_ComfyUI split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors --revision 25608066f9bf5cdc28020836ce9549587053f346 --local-dir /AI/$FOLDER/models/ && \
            mv /AI/$FOLDER/models/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors /AI/$FOLDER/models/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors && \
            rm -rf /AI/$FOLDER/models/split_files && \
            hf download Comfy-Org/Qwen-Image_ComfyUI split_files/vae/qwen_image_vae.safetensors --revision b8f0a47470ec2a0724d6267ca696235e441baa5d --local-dir /AI/$FOLDER/models/vae && \
            mv /AI/$FOLDER/models/vae/split_files/vae/qwen_image_vae.safetensors /AI/$FOLDER/models/vae/qwen_image_vae.safetensors && \
            rm -rf /AI/$FOLDER/models/vae/split_files"
    fi

    # Create wrapper script for AMD optimization
    podman exec -t rocm bash -c "cat > /AI/$FOLDER/main_amd.py << 'AMDEOF'
import torch
# Disable cuDNN for better AMD performance
torch.backends.cudnn.enabled = False

# Import and run the original main.py
import sys
import os

# Execute main.py
exec(open('main.py').read())
AMDEOF"

    # Update COMMAND to use the wrapper
    COMMAND="MIOPEN_FIND_MODE=2 PYTORCH_TUNABLEOP_ENABLED=1 uv run main_amd.py --listen --reserve-vram 1.0 --preview-method auto --bf16-vae --disable-xformers --lowvram"

    basic_run "$REPO" "$COMMAND"
}

# ACE-Step
install_ace_step() {
    REPO="https://github.com/ace-step/ACE-Step"
    COMMIT="6ae0852b1388de6dc0cca26b31a86d711f723cb3"
    COMMAND="uv run acestep --checkpoint_path ./checkpoints --server_name 0.0.0.0"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"

    # Modify requirements.txt from repo (used by pip install -e .)
    podman exec -t rocm bash -c "cd /AI/$FOLDER && \
        sed -i 's/spacy==3\.8\.4/spacy/g' requirements.txt && \
        sed -i 's/datasets==3\.4\.1/datasets/g' requirements.txt && \
        sed -i 's/matplotlib==3\.10\.1/matplotlib/g' requirements.txt && \
        sed -i 's/transformers==4\.50\.0/transformers/g' requirements.txt"

    basic_requirements "$REPO"

    # Install package in editable mode and torchcodec
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install -e . && \
        uv pip install torchcodec==0.8.1"

    basic_run "$REPO" "$COMMAND"
}

# Backup and Restore Manager
run_backup() {
    bash "$SCRIPT_DIR/backup.sh"
}
