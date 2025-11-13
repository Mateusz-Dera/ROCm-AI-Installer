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

# uv
uv_base(){
    local git_repo=$1
    local git_commit=$2
    local start_command=$3
    local python_version=${4:-3.13}
    local pytorch_version=${5:-'nightly/rocm7.0'}
    local flash_attn_version=${6:-2.8.3}

    # Check if git repo and commit are provided
    if [[ -z "$git_repo" || -z "$git_commit" || -z "$start_command" ]]; then
        echo "Error: git repo, git commit, and start command must be provided"
        exit 1
    fi

    # Get the repository name
    local repo_name=$(basename "$git_repo" .git)

    # Check if uv version is installed
    if ! command -v uv &> /dev/null; then
        echo "Install uv first"
        exit 1
    fi

    # Create installation path
    if [ ! -d "$installation_path" ]; then
        mkdir -p $installation_path
    fi
    
    cd $installation_path
    
    # Clone the repository
    if [ -d "$repo_name" ]; then
        rm -rf $repo_name
    fi

    git clone $git_repo

    cd $repo_name || exit 1

    # Checkout the commit
    git checkout $git_commit

    # Create a virtual environment
    uv venv --python $python_version

    # Activate the virtual environment
    source .venv/bin/activate

    # Upgrade pip
    uv pip install -U pip==25.2
    uv pip install wheel==0.45.1
    uv pip install setuptools==80.9.0

    # Install requirements
    if [ -f "$REQUIREMENTS_DIR/$repo_name.txt" ]; then
        uv pip install -r $REQUIREMENTS_DIR/$repo_name.txt --index-url https://pypi.org/simple --extra-index-url https://download.pytorch.org/whl/$pytorch_version --index-strategy unsafe-best-match
    fi

tee --append run.sh <<EOF
#!/bin/bash
source $installation_path/$repo_name/.venv/bin/activate
export HSA_OVERRIDE_GFX_VERSION=$HSA_OVERRIDE_GFX_VERSION
export HIP_VISIBLE_DEVICES=0
#export CUDA_VISIBLE_DEVICES=0
export PYTORCH_ROCM_ARCH=$GFX
EOF

if [ -n "${flash_attn_version}" ] && [ "${flash_attn_version}" != "0" ]; then
    if [ "${flash_attn_version}" != "-1" ]; then
        install_flash_attention "$flash_attn_version"
    fi
    tee --append run.sh <<EOF
export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1
export TORCH_BLAS_PREFER_HIPBLASLT=0
export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"
EOF
fi

tee --append run.sh <<EOF
$start_command
EOF

    chmod +x run.sh
}

# FlashAttention
install_flash_attention() {
    local flash_attn_version=${1:-2.8.3}
    export PYTORCH_ROCM_ARCH=$GFX
    export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"
    echo "Installing FlashAttention version $flash_attn_version"
    uv pip install flash-attn=="$flash_attn_version" --no-build-isolation
}

# KoboldCPP
install_koboldcpp() {
    uv_base "https://github.com/YellowRoseCx/koboldcpp-rocm" "ee3f39fc7ce391d02eda407f828098f70488a6b7" "uv run koboldcpp.py" "3.13" "rocm6.4" "0"
    make LLAMA_HIPBLAS=1 -j$(($(nproc) - 1))
}

# Text generation web UI
install_text_generation_web_ui() {
    uv_base "https://github.com/oobabooga/text-generation-webui.git" "fc67e5e692c2d627fe181d116e6d35a73d5e8b09" 'uv run server.py --api --listen --extensions sd_api_pictures send_pictures gallery' "3.13" "rocm6.4"

    # bitsandbytes
    uv pip install git+https://github.com/ROCm/bitsandbytes.git@4fa939b3883ca17574333de2935beaabf71b2dba

    # ExLlamaV2
    uv pip install https://github.com/turboderp-org/exllamav2/releases/download/v0.3.2/exllamav2-0.3.2+rocm6.4.torch2.8.0-cp313-cp313-linux_x86_64.whl

    # llama_cpp
    uv pip install https://github.com/oobabooga/llama-cpp-binaries/releases/download/v0.55.0/llama_cpp_binaries-0.55.0+vulkan-py3-none-linux_x86_64.whl
}

# SillyTavern
install_sillytavern() {
    mkdir -p $installation_path
    cd $installation_path
    if [ -d "SillyTavern" ]
    then
        rm -rf SillyTavern
    fi
    git clone https://github.com/SillyTavern/SillyTavern.git
    cd SillyTavern
    git checkout 8f7b6b43c3f6402a8908d8d9bbf3134b2a43fb2c

    mv ./start.sh ./run.sh

    # Default config
    cd ./default
    sed -i 's/listen: false/listen: true/' config.yaml
    sed -i 's/whitelistMode: true/whitelistMode: false/' config.yaml
    sed -i 's/basicAuthMode: false/basicAuthMode: true/' config.yaml
}

# SillyTavern WhisperSpeech web UI
install_sillytavern_whisperspeech_web_ui() {
    if [ ! -d "$installation_path/SillyTavern" ]; then
        echo "SillyTavern is not installed. Please install SillyTavern first."
        return 1
    fi

    cd $installation_path/SillyTavern/public/scripts/extensions/third-party
    if [ -d "whisperspeech-webui" ]; then
        rm -rf whisperspeech-webui
    fi

    git clone https://github.com/Mateusz-Dera/whisperspeech-webui
    mv ./whisperspeech-webui ./whisperspeech-webui-temp
    cd whisperspeech-webui-temp
    git checkout 37e2ddf59664dd1604cc41b2660f48d1fa1af173
    mv ./whisperspeech-webui ../
    cd ..
    rm -rf whisperspeech-webui-temp
}

# Ollama
uninstall_ollama(){
    # Stop and disable ollama service
    sudo systemctl stop ollama
    sudo systemctl disable ollama

    # Remove service file
    sudo rm -f /etc/systemd/system/ollama.service

    # Reload systemd after removing service file
    sudo systemctl daemon-reload

    # Remove ollama binary
    sudo rm -f $(which ollama)

    # Remove ollama directory
    sudo rm -rf /usr/share/ollama

    # Remove all users from ollama group first
    if getent group ollama > /dev/null 2>&1; then
        # Get list of users in ollama group
        OLLAMA_USERS=$(getent group ollama | cut -d: -f4 | tr ',' ' ')
        
        # Remove each user from ollama group
        for user in $OLLAMA_USERS; do
            if [ -n "$user" ]; then
                echo "Removing user $user from ollama group"
                sudo gpasswd -d "$user" ollama
            fi
        done
    fi

    # Delete ollama user (this will also remove the group if it's the user's primary group)
    if id "ollama" &>/dev/null; then
        sudo userdel ollama
    fi

    # Force remove ollama group if it still exists
    if getent group ollama > /dev/null 2>&1; then
        sudo groupdel ollama
    fi

    echo "Ollama uninstallation completed."
}

install_ollama() {
    uninstall_ollama
    cd /tmp
    curl -fsSL https://ollama.com/install.sh | sh

    sudo mkdir -p /etc/systemd/system/ollama.service.d/
    echo '[Service]
Environment="OLLAMA_HOST=0.0.0.0"' | sudo tee /etc/systemd/system/ollama.service.d/override.conf

    sudo systemctl daemon-reload
    sudo systemctl restart ollama

    if [ -d "$installation_path/Ollama" ]; then
        rm -rf "$installation_path/Ollama"
    fi

    mkdir "$installation_path/Ollama"
    cd "$installation_path/Ollama"

    cp $CUSTOM_FILES_DIR/ollama_custom.sh ./run.sh
    chmod +x ./run.sh
}

# llama.cpp
install_llama_cpp() {
    cd $installation_path
    if [ -d "llama.cpp" ]
    then
        rm -rf llama.cpp
    fi
    git clone https://github.com/ggerganov/llama.cpp.git
    cd llama.cpp
    git checkout 5f7e166cbf7b9ca928c7fad990098ef32358ac75
    
    HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
    cmake -S . -B build -DLLAMA_CURL=OFF -DGGML_HIP=ON -DAMDGPU_TARGETS=$GFX -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --config Release -- -j$(($(nproc) - 1))

    tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=$HSA_OVERRIDE_GFX_VERSION
export HIP_VISIBLE_DEVICES=0
#export CUDA_VISIBLE_DEVICES=0
./build/bin/llama-server -m model.gguf --host 0.0.0.0 --port 8080 --ctx-size 32768 --gpu-layers 1
EOF
    chmod +x run.sh
}

# ComfyUI
install_comfyui() {
    ROCM_VERSION="nightly/rocm7.0"
    uv_base "https://github.com/comfyanonymous/ComfyUI.git" "1c10b33f9bbc75114053bc041851b60767791783" "MIOPEN_FIND_MODE=2 MIOPEN_LOG_LEVEL=3 PYTORCH_TUNABLEOP_ENABLED=1 TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1 python3 ./main.py --listen --reserve-vram 1.0 --preview-method auto --bf16-vae --disable-xformers --lowvram" "3.13" "$ROCM_VERSION" "-1"

    local gguf=0
    local flux=0
    local qwen=0
    local needs_hf_login=0

    # Check if HF login is needed for any selected choices
    for choice in $CHOICES; do
        case $choice in
            '"4"'|'"5"'|'"6"')
                needs_hf_login=1
                ;;
        esac
    done

    # LOGIN to HF if needed
    if [ $needs_hf_login -eq 1 ]; then
        retry_count=0
        max_retries=3
        while [ $retry_count -lt $max_retries ]; do
            retry_count=$((retry_count + 1))
            is_last_attempt=0
            if [ $retry_count -eq $max_retries ]; then
                is_last_attempt=1
            fi
            
            if huggingface $is_last_attempt; then
                break
            else
                if [ $retry_count -lt $max_retries ]; then
                    echo "Login failed. Retrying attempt ($retry_count/$max_retries)..."
                    sleep 2
                else
                    whiptail --title "Login Failed" --msgbox "Failed to login after $max_retries attempts. Exiting." 8 60
                    exit 1
                fi
            fi
        done
    fi

    uv pip install -r $REQUIREMENTS_DIR/ComfyUI_post.txt --index-url https://pypi.org/simple --extra-index-url https://download.pytorch.org/whl/$ROCM_VERSION --index-strategy unsafe-best-match

    install_flash_attention "2.8.3 "

    # Process each selected choice
    for choice in $CHOICES; do
        case $choice in
            '"0"')
                # ComfyUI-Manager
                cd $installation_path/ComfyUI/custom_nodes
                git clone https://github.com/ltdrdata/ComfyUI-Manager
                cd ComfyUI-Manager
                git checkout 393839b3ab497522fac489d84119dd362d90dae1
                ;;
            '"1"')
                gguf=1
                ;;
            '"2"')
                # AuraSR
                cd $installation_path/ComfyUI/custom_nodes
                git clone https://github.com/alexisrolland/ComfyUI-AuraSR --recursive
                cd ComfyUI-AuraSR
                git checkout 29c97cf9d7bda74d3020678a03545d74dfccadf4

                cd $installation_path/ComfyUI/models/upscale_models
                
                hf download fal/AuraSR-v2 model.safetensors --revision ff452185a7c8b51206dd62c21c292e7baad5c3a3 --local-dir $installation_path/ComfyUI/models/upscale_models
                mv ./model.safetensors ./aura_sr_v2.safetensors

                hf download fal/AuraSR model.safetensors --revision 87da2f52b29b6351391f71c74de581c393fc19f5 --local-dir $installation_path/ComfyUI/models/upscale_models
                mv ./model.safetensors ./aura_sr.safetensors

                pip install aura-sr==0.0.4
                ;;
            '"3"')
                # AuraFlow
                hf download fal/AuraFlow-v0.3 aura_flow_0.3.safetensors --revision 2cd8588f04c886002be4571697d84654a50e3af3 --local-dir $installation_path/ComfyUI/models/checkpoints
                ;;
            '"4"')
                gguf=1
                flux=1
                # Flux
                hf download city96/FLUX.1-schnell-gguf flux1-schnell-Q8_0.gguf --revision f495746ed9c5efcf4661f53ef05401dceadc17d2 --local-dir $installation_path/ComfyUI/models/unet
                ;;
            '"5"')
                gguf=1
                flux=1
                # AnimePro FLUX
                hf download advokat/AnimePro-FLUX animepro-Q5_K_M.gguf --revision be1cbbe8280e6d038836df868c79cdf7687ad39d --local-dir $installation_path/ComfyUI/models/unet
                ;;
            '"6"')
                gguf=1
                flux=1
                # Flex.1-alpha 
                hf download hum-ma/Flex.1-alpha-GGUF Flex.1-alpha-Q8_0.gguf --revision 2ccb9cb781dfbafdf707e21b915c654c4fa6a07d --local-dir $installation_path/ComfyUI/models/unet
                ;;
            '"7"')
                gguf=1
                qwen=1
                # Qwen-Image
                hf download city96/Qwen-Image-gguf qwen-image-Q6_K.gguf --revision e77babc55af111419e1714a7a0a848b9cac25db7 --local-dir $installation_path/ComfyUI/models/diffusion_models
                ;;
            '"8"')
                gguf=1
                qwen=1
                # Qwen-Image-Edit
                hf download calcuis/qwen-image-edit-gguf qwen-image-edit-q4_k_s.gguf --revision 113bedf317589c2e8f6d6f7fde3a40dbf90ef6eb --local-dir $installation_path/ComfyUI/models/diffusion_models
                ;;
            '"9"')
                gguf=1
                qwen2509=1
                # Qwen-Image-Edit-2509
                hf download QuantStack/Qwen-Image-Edit-2509-GGUF Qwen-Image-Edit-2509-Q4_0.gguf --revision 37f16c813605380a97900aac19433ffb1622817a --local-dir $installation_path/ComfyUI/models/diffusion_models
                ;;
            '"10"')
                # Wan 2.2
                cd /tmp
                TEMP_DIR="ComfyUI-Wan2.2"
                COMMIT="bcd839189de217703be0450c4f3736062a4a4873"

                if [ -d "$TEMP_DIR" ]; then
                    rm -rf "$TEMP_DIR"
                fi

                mkdir $TEMP_DIR

                hf download Comfy-Org/Wan_2.2_ComfyUI_Repackaged split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors --revision $COMMIT --local-dir /tmp/$TEMP_DIR
                mv /tmp/$TEMP_DIR/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors $installation_path/ComfyUI/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors

                hf download Comfy-Org/Wan_2.2_ComfyUI_Repackaged split_files/vae/wan_2.1_vae.safetensors --revision $COMMIT --local-dir /tmp/$TEMP_DIR
                mv /tmp/$TEMP_DIR/split_files/vae/wan_2.1_vae.safetensors $installation_path/ComfyUI/models/vae/wan_2.1_vae.safetensors

                hf download Comfy-Org/Wan_2.2_ComfyUI_Repackaged split_files/vae/wan2.2_vae.safetensors --revision $COMMIT --local-dir /tmp/$TEMP_DIR
                mv /tmp/$TEMP_DIR/split_files/vae/wan2.2_vae.safetensors $installation_path/ComfyUI/models/vae/wan2.2_vae.safetensors

                hf download Comfy-Org/Wan_2.2_ComfyUI_Repackaged split_files/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors --revision $COMMIT --local-dir /tmp/$TEMP_DIR
                mv /tmp/$TEMP_DIR/split_files/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors $installation_path/ComfyUI/models/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors

                rm -rf /tmp/$TEMP_DIR
                
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
        cd $installation_path/ComfyUI/custom_nodes
        git clone https://github.com/calcuis/gguf
        cd gguf
        git checkout a64ccbf6c694a46c181a444a1ac9d2d810607309
    fi
    
    if [ $flux -eq 1 ]; then
        cd $installation_path/ComfyUI/models/text_encoders
        hf download city96/t5-v1_1-xxl-encoder-bf16 model.safetensors --revision 1b9c856aadb864af93c1dcdc226c2774fa67bc86 --local-dir $installation_path/ComfyUI/models/text_encoders
        mv ./model.safetensors ./t5-v1_1-xxl-encoder-bf16.safetensors
        hf download openai/clip-vit-large-patch14 model.safetensors --revision 32bd64288804d66eefd0ccbe215aa642df71cc41 --local-dir $installation_path/ComfyUI/models/text_encoders
        mv ./model.safetensors ./clip-vit-large-patch14.safetensors

        cd $installation_path/ComfyUI/models/vae
        hf download black-forest-labs/FLUX.1-schnell vae/diffusion_pytorch_model.safetensors --revision 741f7c3ce8b383c54771c7003378a50191e9efe9 --local-dir $installation_path/ComfyUI/models/vae
    fi

    if [ $qwen -eq 1 ]; then
        # Lightning
        hf download lightx2v/Qwen-Image-Lightning Qwen-Image-Lightning-4steps-V2.0.safetensors --revision 21e79ba3c2cb6454834051ea973ffcd04ff1993f --local-dir $installation_path/ComfyUI/models/loras
        hf download lightx2v/Qwen-Image-Lightning Qwen-Image-Lightning-8steps-V2.0.safetensors --revision 21e79ba3c2cb6454834051ea973ffcd04ff1993f --local-dir $installation_path/ComfyUI/models/loras
    fi

    if [ $qwen2509 -eq 1 ]; then
        # Lightning
        hf download lightx2v/Qwen-Image-Lightning Qwen-Image-Edit-2509/Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors --revision 21e79ba3c2cb6454834051ea973ffcd04ff1993f --local-dir $installation_path/ComfyUI/models/loras
        hf download lightx2v/Qwen-Image-Lightning Qwen-Image-Edit-2509/Qwen-Image-Edit-2509-Lightning-8steps-V1.0-bf16.safetensors --revision 21e79ba3c2cb6454834051ea973ffcd04ff1993f --local-dir $installation_path/ComfyUI/models/loras

        mv $installation_path/ComfyUI/models/loras/Qwen-Image-Edit-2509/Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors $installation_path/ComfyUI/models/loras/Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors
        mv $installation_path/ComfyUI/models/loras/Qwen-Image-Edit-2509/Qwen-Image-Edit-2509-Lightning-8steps-V1.0-bf16.safetensors $installation_path/ComfyUI/models/loras/Qwen-Image-Edit-2509-Lightning-8steps-V1.0-bf16.safetensors

        rm -rf $installation_path/ComfyUI/models/loras/Qwen-Image-Edit-2509
    fi

    if [ $qwen -eq 1 -o $qwen2509 -eq 1 ]; then
        # VL-7B
        hf download Comfy-Org/Qwen-Image_ComfyUI split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors --revision 25608066f9bf5cdc28020836ce9549587053f346 --local-dir "$installation_path/ComfyUI/models/"
        mv $installation_path/ComfyUI/models/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors $installation_path/ComfyUI/models/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors
        rm -rf $installation_path/ComfyUI/models/split_files
    
        # vae
        hf download Comfy-Org/Qwen-Image_ComfyUI split_files/vae/qwen_image_vae.safetensors --revision b8f0a47470ec2a0724d6267ca696235e441baa5d --local-dir "$installation_path/ComfyUI/models/vae"
        mv $installation_path/ComfyUI/models/vae/split_files/vae/qwen_image_vae.safetensors $installation_path/ComfyUI/models/vae/qwen_image_vae.safetensors
        rm -rf $installation_path/ComfyUI/models/vae/split_files 
    fi
}

# vLLM
install_vllm() {
    uv_base "https://github.com/vllm-project/vllm.git" "e261d37c9a5e88a6c86d32decf39f1fab7ca1f2c" 'LD_LIBRARY_PATH=/opt/rocm/lib:$LD_LIBRARY_PATH vllm serve ./model --cpu-offload-gb 32 --gpu-memory-utilization 0.95 --max-model-len=8192 --max-num-seqs=1 --host 0.0.0.0 --port 7860'

    uv pip install -U setuptools==79.0.1

    uv pip uninstall triton
    git clone https://github.com/ROCm/triton.git
    cd triton
    git checkout f9e5bf54
    uv pip install -e . --no-build-isolation

    cd ../
    cp  -r /opt/rocm/share/amd_smi ./
    cd amd_smi
    uv pip install .

    export PYTORCH_ROCM_ARCH=$GFX

    cd ../
    python3 setup.py develop
}

# ACE-Step
install_ace_step() {
    uv_base "https://github.com/ace-step/ACE-Step" "6ae0852b1388de6dc0cca26b31a86d711f723cb3" 'LD_LIBRARY_PATH=/opt/rocm/lib:$LD_LIBRARY_PATH acestep --checkpoint_path ./checkpoints --server_name 0.0.0.0' "3.13" "rocm6.4"
    sed -i 's/spacy==3\.8\.4/spacy/g' "requirements.txt"
    sed -i 's/datasets==3\.4\.1/datasets/g' "requirements.txt"
    sed -i 's/matplotlib==3\.10\.1/matplotlib/g' "requirements.txt"
    sed -i 's/transformers==4\.50\.0/transformers/g' "requirements.txt"
    uv pip install -e .
}

# WhisperSpeech web UI
install_whisperspeech_web_ui(){
    uv_base "https://github.com/Mateusz-Dera/whisperspeech-webui.git" "37e2ddf59664dd1604cc41b2660f48d1fa1af173" "uv run --extra rocm webui.py --listen --api"
}

# F5-TTS
install_f5_tts(){
    uv_base "https://github.com/SWivid/F5-TTS.git" "3eecd94baa74fa1eea44ba36f000b9e8d0b163f9" "f5-tts_infer-gradio --host 0.0.0.0" "3.12" "rocm6.4"
    git submodule update --init --recursive
    uv pip install -e .
}

# Matcha-TTS
install_matcha_tts(){
    uv_base "https://github.com/shivammehta25/Matcha-TTS" "108906c603fad5055f2649b3fd71d2bbdf222eac" "MIOPEN_LOG_LEVEL=3 matcha-tts-app" "3.13" "rocm6.4"
    cd ./matcha
    sed -i 's/demo\.queue().launch(share=True)/demo.queue().launch(server_name="0.0.0.0")/' "app.py"
    cd $installation_path/Matcha-TTS
    sed -i 's/cython==0.29.35/cython/' "pyproject.toml"
    sed -i 's/numpy==1.24.3/numpy/' "pyproject.toml"
    rm requirements.txt
    touch requirements.txt
    uv pip install -e .
}

# Dia
install_dia(){
    uv_base "https://github.com/tralamazza/dia.git" "8da0c755661e3cb71dc81583400012be6c3f62be" "MIOPEN_FIND_MODE=FAST uv run --extra rocm app.py" "3.13" "nightly/rocm7.0" "0"
    sed -i 's|url = "https://download.pytorch.org/whl/rocm6\.3"|url = "https://download.pytorch.org/whl/nightly/rocm7.0"|' pyproject.toml
    sed -i 's/demo.launch(share=args.share)/demo.launch(share=args.share,server_name="0.0.0.0")/' "app.py"
}

# IMS-Toucan
install_ims_toucan(){
    uv_base "https://github.com/DigitalPhonetics/IMS-Toucan.git" "dab8fe99199e707f869a219e836b69e53f13c528" 'uv run run_simple_GUI_demo.py' "3.12" "rocm6.1" "2.7.4.post1"
    sed -i 's/self.iface.launch()/self.iface.launch(share=False, server_name="0.0.0.0")/' "run_simple_GUI_demo.py"
}

# Chatterbox Multilingual
install_chatterbox(){
    uv_base "https://github.com/resemble-ai/chatterbox" "bf169fe5f518760cb0b6c6a6eba3f885e10fa86f" "MIOPEN_LOG_LEVEL=3 uv run multilingual_app.py"
    rm -rf ./multilingual_app.py
    cp $CUSTOM_FILES_DIR/chatterbox/multilingual_app.py ./
    
    rm pyproject.toml
    cp $CUSTOM_FILES_DIR/chatterbox/pyproject.toml ./
    
    uv pip install -e .
}

# KaniTTS
install_kanitts(){
    uv_base "https://github.com/nineninesix-ai/kani-tts" "63df2212c069c4cc147a0dd9f7804672ef8a8cbb" "uv run fastapi_example/server.py"
    cd fastapi_example
    mv ./client.html ./index.html
    sed -i '/if __name__ == "__main__":/,/uvicorn\.run(app, host="0\.0\.0\.0", port=8000, log_level="info")/d' server.py
    cat >> server.py << 'EOF'

if __name__ == "__main__":
    import http.server
    import threading
    import os
    
    # Change to fastapi_example folder and start HTML server
    os.chdir('fastapi_example')
    threading.Thread(target=lambda: http.server.HTTPServer(('', 7860), http.server.SimpleHTTPRequestHandler).serve_forever(), daemon=True).start()
    print("HTML Server: http://0.0.0.0:7860")
    
    # Start FastAPI server
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
EOF
}

install_partcrafter(){
    uv_base "https://github.com/wgsxm/PartCrafter" "269bd4164fbe35b17a6e58f8d6934262822082eb" "uv run partcrafter_webui.py" "3.13"
    cp $CUSTOM_FILES_DIR/partcrafter/inference_partcrafter.py ./scripts/inference_partcrafter.py
    cp $CUSTOM_FILES_DIR/partcrafter/render_utils.py ./src/utils/render_utils.py
    cp $CUSTOM_FILES_DIR/partcrafter/partcrafter_webui.py ./partcrafter_webui.py
    git clone https://github.com/Mateusz-Dera/pytorch_cluster_rocm
    cd ./pytorch_cluster_rocm
    git checkout 6be490d08df52755684b7ccfe10d55463070f13d
    rm -r ./requirements.txt
    touch ./requirements.txt
    uv pip install .
}

# Login to HuggingFace
huggingface() {
    local is_last_attempt=${1:-0}
    
    HF_TOKEN=$(whiptail --title "Hugging Face Login" --inputbox "Enter your Hugging Face access token:" 10 60 3>&1 1>&2 2>&3)
    
    # Check if user cancelled or token is empty
    if [ $? -ne 0 ] || [ -z "$HF_TOKEN" ]; then
        whiptail --title "Error" --msgbox "No token provided. Login cancelled." 8 50
        return 1
    fi
        
    # Login to Hugging Face
    hf auth login --token "$HF_TOKEN"

    # Check login status
    if [ $? -eq 0 ]; then
        whiptail --title "Success" --msgbox "Successfully logged into Hugging Face!" 8 50
        return 0
    else
        if [ $is_last_attempt -eq 0 ]; then
            whiptail --title "Error" --msgbox "Login failed. Please check your token and try again." 8 50
        fi
        return 1
    fi
}

# Install fastfetch
install_fastfetch(){
    local language=${1:-"english"}

    # Install fastfetch
    
    if ! command -v fastfetch &> /dev/null; then
        sudo apt -y install fastfetch
    fi

    if command -v gsettings &> /dev/null; then
        gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:b1dcc9dd-5262-4d8d-a863-c897e6d979b9/ default-size-columns 100
    fi

    # Add fastfetch to shell

    CONFIG_FILE="$HOME/.bashrc"
    
    # Remove old fastfetch line if it exists
    OLD_LINE="fastfetch"
    if grep -qxF "$OLD_LINE" "$CONFIG_FILE"; then
        sed -i "/^fastfetch$/d" "$CONFIG_FILE"
    fi

    # Config

    if [ ! -d "$HOME/.config/fastfetch" ]; then
        mkdir -p "$HOME/.config/fastfetch"
    fi

    if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
        rm -rf "$HOME/.config/fastfetch/config.jsonc"
    fi

    if [ -f "$HOME/.config/fastfetch/config_temp.jsonc" ]; then
        rm -rf "$HOME/.config/fastfetch/config_temp.jsonc"
    fi


    # Copy language-specific config file as config_temp
    case "$language" in
        "polish")
            cp "$CUSTOM_FILES_DIR/fastfetch/config_polish.jsonc" "$HOME/.config/fastfetch/config_temp.jsonc"
            ;;
        "polish_no_logo")
            cp "$CUSTOM_FILES_DIR/fastfetch/config_polish_no_logo.jsonc" "$HOME/.config/fastfetch/config_temp.jsonc"
            ;;
        "english_no_logo")
            cp "$CUSTOM_FILES_DIR/fastfetch/config_english_no_logo.jsonc" "$HOME/.config/fastfetch/config_temp.jsonc"
            ;;
        "english"|*)
            cp "$CUSTOM_FILES_DIR/fastfetch/config_english.jsonc" "$HOME/.config/fastfetch/config_temp.jsonc"
            ;;
    esac

    # GPU

    if [ -f "/usr/bin/fastfetch-gpu" ]; then
        sudo rm -rf "/usr/bin/fastfetch-gpu"
    fi

    sudo cp "$CUSTOM_FILES_DIR/fastfetch/fastfetch-gpu.sh" /usr/bin/fastfetch-gpu
    sudo chmod +x /usr/bin/fastfetch-gpu

    # Dynamic fastfetch
    if [ -f "/usr/bin/dynamic-fastfetch" ]; then
        sudo rm -rf "/usr/bin/dynamic-fastfetch"
    fi

    sudo cp "$CUSTOM_FILES_DIR/fastfetch/dynamic-fastfetch.sh" /usr/bin/dynamic-fastfetch
    sudo chmod +x /usr/bin/dynamic-fastfetch

    # Add dynamic-fastfetch alias to bash
    CONFIG_FILE="$HOME/.bashrc"
    
    # Remove old entries if they exist
    OLD_ALIAS="alias fastfetch='dynamic-fastfetch'"
    FASTFETCH_LINE="fastfetch"
    
    if grep -qF "$OLD_ALIAS" "$CONFIG_FILE"; then
        sed -i '/alias fastfetch='\''dynamic-fastfetch'\''/d' "$CONFIG_FILE"
    fi
    
    if grep -qxF "$FASTFETCH_LINE" "$CONFIG_FILE"; then
        sed -i "/^fastfetch$/d" "$CONFIG_FILE"
    fi
    
    # Add new entries (alias must be before fastfetch)
    echo "alias fastfetch='dynamic-fastfetch'" >> "$CONFIG_FILE"
    echo "fastfetch" >> "$CONFIG_FILE"
}
