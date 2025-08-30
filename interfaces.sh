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
    local pytorch_version=${5:-rocm6.4}
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
    install_flash_attention "$flash_attn_version"
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
    uv_base "https://github.com/YellowRoseCx/koboldcpp-rocm.git" "dfcf78f27f29559ad4dbc4dad230dde391cc5874" "uv run koboldcpp.py" "3.13" "rocm6.4" "0"
    make LLAMA_HIPBLAS=1 -j$(($(nproc) - 1))
}

# Text generation web UI
install_text_generation_web_ui() {
    uv_base "https://github.com/oobabooga/text-generation-webui.git" "45e2935e87f19aa3d5afec9a403203259cb1eacc" 'uv run server.py --api --listen --extensions sd_api_pictures send_pictures gallery'

    # bitsandbytes
    uv pip install git+https://github.com/ROCm/bitsandbytes.git@48a551fd80995c3733ea65bb475d67cd40a6df31

    # ExLlamaV2
    git clone https://github.com/turboderp/exllamav2
    cd exllamav2
    git checkout 6a2d8311408aa23af34e8ec32e28085ea68dada7
    uv pip install .
    cd ..

    # llama_cpp
    uv pip install https://github.com/oobabooga/llama-cpp-binaries/releases/download/v0.36.0/llama_cpp_binaries-0.36.0+vulkanavx-py3-none-linux_x86_64.whl
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
    git checkout 12ac17197925ee1e1dba00a9505001e09e13dfde

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
    git checkout 5e6229a8409ac786e62cb133d09f1679a9aec13e
    
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

# Cinemo
install_cinemo() {
    uv_base "https://huggingface.co/spaces/maxin-cn/Cinemo" "9a3fcb44aced3210e8b5e4cf164a8ad3ce3e07fd" "uv run demo.py" "3.12"
    sed -i 's/demo.launch(debug=False, share=True)/demo.launch(debug=False, share=False, server_name="0.0.0.0")/' demo.py
}

# Ovis-U1
install_ovis() {
    uv_base "https://huggingface.co/spaces/AIDC-AI/Ovis-U1-3B" "cbc005ddff7376a20bc98a89136d088e0f7e1623" "uv run app.py" "3.13" "rocm6.3" "2.7.4.post1"
    sed -i 's/demo.launch(share=True, ssr_mode=False)/demo.launch(share=False, ssr_mode=False, server_name="0.0.0.0")/' "app.py"
    sed -i "/subprocess\.run('pip install flash-attn==2\.6\.3 --no-build-isolation', env={'FLASH_ATTENTION_SKIP_CUDA_BUILD': \"TRUE\"}, shell=True)/d" app.py
}

# ComfyUI
install_comfyui() {
    uv_base "https://github.com/comfyanonymous/ComfyUI.git" "37d620a6b85f61b824363ed8170db373726ca45a" "python3 ./main.py --listen --use-split-cross-attention" "3.12" "rocm6.3" "0"

    local gguf=0
    local flux=0
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

    uv pip install -r $REQUIREMENTS_DIR/ComfyUI_post.txt --index-url https://pypi.org/simple --extra-index-url https://download.pytorch.org/whl/rocm6.3 --index-strategy unsafe-best-match

    install_flash_attention "2.7.4.post1"

    # Process each selected choice
    for choice in $CHOICES; do
        case $choice in
            '"0"')
                # ComfyUI-Manager
                cd $installation_path/ComfyUI/custom_nodes
                git clone https://github.com/ltdrdata/ComfyUI-Manager
                cd ComfyUI-Manager
                git checkout 205044ca667e97b8da4417cf21835d713d22bd23
                ;;
            '"1"')
                gguf=1
                ;;
            '"2"')
                # AuraSR
                cd $installation_path/ComfyUI/custom_nodes
                git clone https://github.com/alexisrolland/ComfyUI-AuraSR --recursive
                cd ComfyUI-AuraSR
                git checkout fab70362f423dc63bd0e7980eb740b0d84605be7

                cd $installation_path/ComfyUI/models/checkpoints
                huggingface-cli download fal/AuraSR-v2 model.safetensors --revision ff452185a7c8b51206dd62c21c292e7baad5c3a3 --local-dir $installation_path/ComfyUI/models/checkpoints
                mv ./model.safetensors ./aura_sr_v2.safetensors
                huggingface-cli download fal/AuraSR model.safetensors --revision 87da2f52b29b6351391f71c74de581c393fc19f5 --local-dir $installation_path/ComfyUI/models/checkpoints
                mv ./model.safetensors ./aura_sr.safetensors

                pip install aura-sr==0.0.4
                ;;
            '"3"')
                # AuraFlow
                huggingface-cli download fal/AuraFlow-v0.3 aura_flow_0.3.safetensors --revision 2cd8588f04c886002be4571697d84654a50e3af3 --local-dir $installation_path/ComfyUI/models/checkpoints
                ;;
            '"4"')
                gguf=1
                flux=1
                # Flux
                huggingface-cli download city96/FLUX.1-schnell-gguf flux1-schnell-Q8_0.gguf --revision f495746ed9c5efcf4661f53ef05401dceadc17d2 --local-dir $installation_path/ComfyUI/models/unet
                ;;
            '"5"')
                gguf=1
                flux=1
                # AnimePro FLUX
                huggingface-cli download advokat/AnimePro-FLUX animepro-Q5_K_M.gguf --revision be1cbbe8280e6d038836df868c79cdf7687ad39d --local-dir $installation_path/ComfyUI/models/unet
                ;;
            '"6"')
                gguf=1
                flux=1
                # Flex.1-alpha 
                huggingface-cli download hum-ma/Flex.1-alpha-GGUF Flex.1-alpha-Q8_0.gguf --revision 2ccb9cb781dfbafdf707e21b915c654c4fa6a07d --local-dir $installation_path/ComfyUI/models/unet
                ;;
            '"7"')
                gguf=1
                # Qwen-Image
                huggingface-cli download city96/Qwen-Image-gguf qwen-image-Q6_K.gguf --revision e77babc55af111419e1714a7a0a848b9cac25db7 --local-dir $installation_path/ComfyUI/models/diffusion_models

                huggingface-cli download unsloth/Qwen2.5-VL-7B-Instruct-GGUF Qwen2.5-VL-7B-Instruct-UD-Q6_K_XL.gguf --revision 68bb8bc4b7df5289c143aaec0ab477a7d4051aab --local-dir $installation_path/ComfyUI/models/text_encoders
            
                huggingface-cli download Comfy-Org/Qwen-Image_ComfyUI split_files/vae/qwen_image_vae.safetensors --revision b8f0a47470ec2a0724d6267ca696235e441baa5d --local-dir "$installation_path/ComfyUI/models/vae"
                mv $installation_path/ComfyUI/models/vae/split_files/vae/qwen_image_vae.safetensors $installation_path/ComfyUI/models/vae/qwen_image_vae.safetensors
                rm -rf $installation_path/ComfyUI/models/vae/split_files
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
        git clone https://github.com/city96/ComfyUI-GGUF
        cd ComfyUI-GGUF
        git checkout cf0573351ac260d629d460d97f09b09ac17d3726
    fi
    
    if [ $flux -eq 1 ]; then
        cd $installation_path/ComfyUI/models/text_encoders
        huggingface-cli download city96/t5-v1_1-xxl-encoder-bf16 model.safetensors --revision 1b9c856aadb864af93c1dcdc226c2774fa67bc86 --local-dir $installation_path/ComfyUI/models/text_encoders
        mv ./model.safetensors ./t5-v1_1-xxl-encoder-bf16.safetensors
        huggingface-cli download openai/clip-vit-large-patch14 model.safetensors --revision 32bd64288804d66eefd0ccbe215aa642df71cc41 --local-dir $installation_path/ComfyUI/models/text_encoders
        mv ./model.safetensors ./clip-vit-large-patch14.safetensors

        cd $installation_path/ComfyUI/models/vae
        huggingface-cli download black-forest-labs/FLUX.1-schnell vae/diffusion_pytorch_model.safetensors --revision 741f7c3ce8b383c54771c7003378a50191e9efe9 --local-dir $installation_path/ComfyUI/models/vae
    fi
}

# ACE-Step
install_ace_step() {
    uv_base "https://github.com/ace-step/ACE-Step" "6ae0852b1388de6dc0cca26b31a86d711f723cb3" "acestep --checkpoint_path ./checkpoints --server_name 0.0.0.0" "3.12"
    uv pip install -e .
}

# WhisperSpeech web UI
install_whisperspeech_web_ui(){
    uv_base "https://github.com/Mateusz-Dera/whisperspeech-webui.git" "37e2ddf59664dd1604cc41b2660f48d1fa1af173" "uv run --extra rocm webui.py --listen --api"
}

# F5-TTS
install_f5_tts(){
    uv_base "https://github.com/SWivid/F5-TTS.git" "605fa13b42b40e860961bac8ce30fe49f02dfa0d" "f5-tts_infer-gradio --host 0.0.0.0" "3.12" "rocm6.3" "2.7.4.post1"
    git submodule update --init --recursive
    uv pip install -e .
}

# Matcha-TTS
install_matcha_tts(){
    uv_base "https://github.com/shivammehta25/Matcha-TTS" "108906c603fad5055f2649b3fd71d2bbdf222eac" "matcha-tts-app"
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
    uv_base "https://github.com/tralamazza/dia.git" "8da0c755661e3cb71dc81583400012be6c3f62be" "MIOPEN_FIND_MODE=FAST uv run --extra rocm app.py"
    sed -i 's/demo.launch(share=args.share)/demo.launch(share=args.share,server_name="0.0.0.0")/' "app.py"
}

# IMS-Toucan
install_ims_toucan(){
    uv_base "https://github.com/DigitalPhonetics/IMS-Toucan.git" "dab8fe99199e707f869a219e836b69e53f13c528" "python3 run_simple_GUI_demo.py" "3.12" "rocm6.1" "2.7.4.post1"
    sed -i 's/self.iface.launch()/self.iface.launch(share=False, server_name="0.0.0.0")/' "run_simple_GUI_demo.py"
}

# Chatterbox
install_chatterbox(){
    uv_base "https://huggingface.co/spaces/ResembleAI/Chatterbox" "eb90621fa748f341a5b768aed0c0c12fc561894b" "uv run app.py"
    sed -i 's/demo.launch(mcp_server=True)/demo.launch(server_name="0.0.0.0")/' "app.py"
}

# TripoSG
install_triposg(){
    uv_base "https://github.com/VAST-AI-Research/TripoSG" "88cfe7101001ad6eefdb6c459c7034f1ceb70d72" "uv run triposg_webui.py" "3.12" "rocm6.3" "2.7.4.post1"
    cp $CUSTOM_FILES_DIR/triposg_webui.py ./
    git clone https://github.com/Mateusz-Dera/pytorch_cluster_rocm
    cd ./pytorch_cluster_rocm
    git checkout 6be490d08df52755684b7ccfe10d55463070f13d
    uv pip install .
}

install_partcrafter(){
    uv_base "https://github.com/wgsxm/PartCrafter" "f38187bba35c0b3a86a95fa85e567adbf3743b69" "uv run partcrafter_webui.py" "3.12" "rocm6.3" "2.7.4.post1"
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
    huggingface-cli login --token "$HF_TOKEN"

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