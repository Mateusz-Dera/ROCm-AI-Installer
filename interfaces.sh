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

# Basic
uv_install(){
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

    # Remove venv if exist
    if [ -d ".venv" ]; then
        rm -rf ".venv"
    fi

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
    uv pip install flash-attn=="$flash_attn_version" --no-build-isolation
}

# KoboldCPP
install_koboldcpp() {
    uv_install "https://github.com/YellowRoseCx/koboldcpp-rocm.git" "dfcf78f27f29559ad4dbc4dad230dde391cc5874" "uv run koboldcpp.py" "3.13" "rocm6.4" "0"
    make LLAMA_HIPBLAS=1 -j$(($(nproc) - 1))
}

# Text generation web UI
install_text_generation_web_ui() {
    uv_install "https://github.com/oobabooga/text-generation-webui.git" "45e2935e87f19aa3d5afec9a403203259cb1eacc" 'uv run server.py --api --listen --extensions sd_api_pictures send_pictures gallery'

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
    git checkout 2e3dff73a127679f643e971801cd51173c2c34e7

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
    git checkout 06aa5f064f6e742f33178214bc883883a5ed0c40
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
    uv_install "https://huggingface.co/spaces/maxin-cn/Cinemo" "9a3fcb44aced3210e8b5e4cf164a8ad3ce3e07fd" "uv run demo.py" "3.12"
    sed -i 's/demo.launch(debug=False, share=True)/demo.launch(debug=False, share=False, server_name="0.0.0.0")/' demo.py
}

# Ovis-U1
install_ovis() {
    uv_install "https://huggingface.co/spaces/AIDC-AI/Ovis-U1-3B" "cbc005ddff7376a20bc98a89136d088e0f7e1623" "uv run app.py" "3.13" "rocm6.3" "2.7.4.post1"
    sed -i 's/demo.launch(share=True, ssr_mode=False)/demo.launch(share=False, ssr_mode=False, server_name="0.0.0.0")/' "app.py"
    sed -i "/subprocess\.run('pip install flash-attn==2\.6\.3 --no-build-isolation', env={'FLASH_ATTENTION_SKIP_CUDA_BUILD': \"TRUE\"}, shell=True)/d" app.py
}

# ComfyUI
install_comfyui() {
    uv_install "https://github.com/comfyanonymous/ComfyUI.git" "37d620a6b85f61b824363ed8170db373726ca45a" "python3 ./main.py --listen --use-split-cross-attention" "3.12" "rocm6.3" "2.7.4.post1"

    install_flash_attention

    local gguf=0
    local flux=0

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
                huggingface-cli download fal/AuraSR-v2 model.safetensors --revision f452185a7c8b51206dd62c21c292e7baad5c3a3 --local-dir $installation_path/ComfyUI/models/checkpoints
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

        huggingface

        cd $installation_path/ComfyUI/models/vae
        huggingface-cli download black-forest-labs/FLUX.1-schnell vae/diffusion_pytorch_model.safetensors --revision 741f7c3ce8b383c54771c7003378a50191e9efe9 --local-dir $installation_path/ComfyUI/models/vae
    fi
}

# ACE-Step
install_ace_step() {
    uv_install "https://github.com/ace-step/ACE-Step" "6ae0852b1388de6dc0cca26b31a86d711f723cb3" "acestep --checkpoint_path ./checkpoints --server_name 0.0.0.0"
    uv pip install -e .
}

# WhisperSpeech web UI
install_whisperspeech_web_ui(){
    uv_install "https://github.com/Mateusz-Dera/whisperspeech-webui.git" "06aa5f064f6e742f33178214bc883883a5ed0c40" "uv run --extra rocm webui.py --listen --api"
}

# F5-TTS
install_f5_tts(){
    uv_install "https://github.com/SWivid/F5-TTS.git" "605fa13b42b40e860961bac8ce30fe49f02dfa0d" "f5-tts_infer-gradio --host 0.0.0.0" "3.12" "rocm6.3" "2.7.4.post1"
    git submodule update --init --recursive
    uv pip install -e .
}

# Matcha-TTS
install_matcha_tts(){
    uv_install "https://github.com/shivammehta25/Matcha-TTS" "108906c603fad5055f2649b3fd71d2bbdf222eac" "matcha-tts-app"
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
    uv_install "https://github.com/tralamazza/dia.git" "8da0c755661e3cb71dc81583400012be6c3f62be" "MIOPEN_FIND_MODE=FAST uv run --extra rocm app.py"
    sed -i 's/demo.launch(share=args.share)/demo.launch(share=args.share,server_name="0.0.0.0")/' "app.py"
}

# IMS-Toucan
install_ims_toucan(){
    uv_install "https://github.com/DigitalPhonetics/IMS-Toucan.git" "dab8fe99199e707f869a219e836b69e53f13c528" "python3 run_simple_GUI_demo.py" "3.12" "rocm6.1" "2.7.4.post1"
    sed -i 's/self.iface.launch()/self.iface.launch(share=False, server_name="0.0.0.0")/' "run_simple_GUI_demo.py"
}

# Chatterbox
install_chatterbox(){
    uv_install "https://huggingface.co/spaces/ResembleAI/Chatterbox" "eb90621fa748f341a5b768aed0c0c12fc561894b" "uv run app.py"
    sed -i 's/demo.launch(mcp_server=True)/demo.launch(server_name="0.0.0.0")/' "app.py"
}

# TripoSG
install_triposg(){
    uv_install "https://github.com/VAST-AI-Research/TripoSG" "88cfe7101001ad6eefdb6c459c7034f1ceb70d72" "uv run triposg_webui.py" "3.12" "rocm6.3" "2.7.4.post1"
    cp $CUSTOM_FILES_DIR/triposg_webui.py ./
    git clone https://github.com/Mateusz-Dera/pytorch_cluster_rocm
    cd ./pytorch_cluster_rocm
    git checkout 6be490d08df52755684b7ccfe10d55463070f13d
    uv pip install .
}

install_partcrafter(){
    uv_install "https://github.com/wgsxm/PartCrafter" "f38187bba35c0b3a86a95fa85e567adbf3743b69" "uv run partcrafter_webui.py" "3.12" "rocm6.3" "2.7.4.post1"
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
    read -sp "Enter your Hugging Face access token: " HF_TOKEN
        
    if [ -z "$HF_TOKEN" ]; then
        echo -e "\nError: No token provided. Exiting."
        exit 1
    fi
        
    # Login to Hugging Face
    echo -e "\nLogging into Hugging Face..."
    huggingface-cli login --token "$HF_TOKEN"

    # Check login status
    if [ $? -eq 0 ]; then
        echo "Successfully logged into Hugging Face!"
    else
        echo "Login failed. Please check your token and try again."
        exit 1
    fi
}

# Install fastfetch
install_fastfetch(){
    # Install fastfetch
    if ! command -v fastfetch &> /dev/null; then
        sudo apt update
        sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch
        sudo apt update
        sudo apt -y install fastfetch
    fi

    if command -v gsettings &> /dev/null; then
        gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:b1dcc9dd-5262-4d8d-a863-c897e6d979b9/ default-size-columns 100
    fi

    # Add fastfetch to shell

    # Detect shell configuration file
    detect_shell_config() {
        if [ -n "$SHELL" ]; then
            case "$SHELL" in
                */zsh)
                    echo "$HOME/.zshrc"
                    sed '/fastfetch/d' "$HOME/.zshrc" > "$HOME/.zshrc.tmp" && mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
                    ;;
                */bash)
                    echo "$HOME/.bashrc"
                    sed '/fastfetch/d' "$HOME/.bashrc" > "$HOME/.bashrc.tmp" && mv "$HOME/.bashrc.tmp" "$HOME/.bashrc"
                    ;;
                */fish)
                    echo "$HOME/.config/fish/config.fish"
                    sed '/fastfetch/d' "$HOME/.config/fish/config.fish" > "$HOME/.config/fish/config.fish.tmp" && mv "$HOME/.config/fish/config.fish.tmp" "$HOME/.config/fish/config.fish"
                    ;;
                *)
                    echo ""
                    ;;
            esac
        else
            echo ""
        fi
    }

    fastfetch_LINE="alias fastfetch='dynamic-fastfetch'"
    CONFIG_FILE=$(detect_shell_config)

    if [ -z "$CONFIG_FILE" ]; then
        echo "Could not detect shell configuration file"
        exit 1
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Creating $CONFIG_FILE"
        touch "$CONFIG_FILE"
    fi

    if [ -f "/usr/bin/dynamic-fastfetch" ]; then
        sudo rm "/usr/bin/dynamic-fastfetch"
    fi

    sudo tee "/usr/bin/dynamic-fastfetch" << 'EOF'
#!/bin/bash
# Dynamic fastfetch wrapper that ensures VRAM information is always up-to-date

# Generate temporary config file with current GPU VRAM info
TMP_CONFIG="$HOME/.config/fastfetch/tmp_config.jsonc"
BASE_CONFIG="$HOME/.config/fastfetch/base_config.jsonc"

# Copy base config to temp
cp "$BASE_CONFIG" "$TMP_CONFIG"

# Get dynamic GPU modules
gpu_modules=$(dynamic-gpu-vram)

# Insert GPU modules into temp config
if [ -n "$gpu_modules" ]; then
    # Replace placeholder with actual modules
    sed -i "s|__GPU_VRAM_MODULES__|$gpu_modules,|" "$TMP_CONFIG"
else
    # Remove placeholder if no GPU data
    sed -i "s|__GPU_VRAM_MODULES__||" "$TMP_CONFIG"
fi

# Run fastfetch with the temporary config
echo
/usr/bin/fastfetch --config "$TMP_CONFIG"
echo

# Clean up temp file
rm "$TMP_CONFIG"
EOF

    sudo chmod +x /usr/bin/dynamic-fastfetch

    echo "dynamic-fastfetch" >> "$CONFIG_FILE"

    if [ -d "$HOME/.config/fastfetch" ]; then
        echo "Fastfetch config already exists"
    else
        mkdir -p "$HOME/.config/fastfetch"
        echo "Fastfetch config created"
    fi

    if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
        rm "$HOME/.config/fastfetch/config.jsonc"
    fi

    # Create the base config with placeholders for dynamic GPU VRAM modules
    tee "$HOME/.config/fastfetch/base_config.jsonc" << 'EOF'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "type": "none",
    "padding": {
    "top": 0
    },
  },
  "modules": [
    "title",
    "break",
    "os",
    "localip",
    "host",
    "kernel",
    "uptime",
    "packages",
    "shell",
    "break",
    "disk",
    "break",
    {
      "type": "cpu",
      "key": "CPU",
      "showPeCoreCount": true,
      "temp": true,
      "format": "{name} ({core-types}) {freq-max}"
    },
    {
      "type": "memory",
      "key": "RAM",
      "format": "{used} / {total})"
    },
    {
      "type": "swap",
      "key": "SWAP",
      "format": "{used} / {total}"
    },
    "gpu",
    "break",
    __GPU_VRAM_MODULES__
  ]
}
EOF

    if [ -f "/usr/bin/get-gpu-vram" ]; then
        sudo rm "/usr/bin/get-gpu-vram"
    fi

    sudo tee "/usr/bin/get-gpu-vram" << 'EOF'
#!/bin/bash

# Function to get AMD GPU names and count
get_amd_gpus() {
    lspci -nn | grep -i "VGA" | grep -i "AMD" | sed 's/.*\[AMD\/ATI\] //; s/ \[.*\]//'
}

# Function to count AMD GPUs
count_amd_gpus() {
    lspci | grep -i "VGA" | grep -i "AMD" | wc -l
}

# Function to count NVIDIA GPUs
count_nvidia_gpus() {
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi --query-gpu=count --format=csv,noheader
    else
        echo 0
    fi
}

# Check for required tools
has_rocm_smi=false
has_nvidia_smi=false

if command -v rocm-smi &> /dev/null; then
    has_rocm_smi=true
fi

if command -v nvidia-smi &> /dev/null; then
    has_nvidia_smi=true
fi

# Count GPUs
amd_count=$(count_amd_gpus)
nvidia_count=$(count_nvidia_gpus)

# Get GPU names
amd_names=()
if [ "$amd_count" -gt 0 ]; then
    while IFS= read -r line; do
        amd_names+=("$line")
    done < <(get_amd_gpus)
fi

nvidia_names=()
if [ "$nvidia_count" -gt 0 ] && $has_nvidia_smi; then
    while IFS= read -r line; do
        nvidia_names+=("$line")
    done < <(nvidia-smi --query-gpu=name --format=csv,noheader)
fi

# Check if any GPUs are found
if [ "$amd_count" -le 0 ] && [ "$nvidia_count" -le 0 ]; then
    exit 0
fi

# Process AMD GPUs if found
if [ "$amd_count" -gt 0 ]; then
    if $has_rocm_smi; then
        # Loop through each AMD GPU index
        for ((gpu=0; gpu<amd_count; gpu++)); do
            used_mem_bytes=$(rocm-smi --showmeminfo vram -d $gpu | grep 'Used Memory' | awk '{print $NF}')
            total_mem_bytes=$(rocm-smi --showmeminfo vram -d $gpu | grep 'Total Memory' | awk '{print $NF}')
            used_mem_mb=$(echo "$used_mem_bytes / 1048576" | bc)
            total_mem_mb=$(echo "$total_mem_bytes / 1048576" | bc)
            
            # Output format: GPU_NAME||VRAM_INFO
            # FIX: Use $gpu instead of 0 to get the correct GPU name
            gpu_name=$(rocm-smi --showproductname -d $gpu | grep 'Card Series' | awk -F: '{print $NF}' | xargs)
            echo "$gpu_name||$used_mem_mb/$total_mem_mb MB"
        done
    else
        # If no rocm-smi, just output the names
        for ((gpu=0; gpu<amd_count; gpu++)); do
            gpu_name="${amd_names[$gpu]:-AMD GPU $gpu}"
            echo "$gpu_name||Memory info unavailable"
        done
    fi
fi

# Process NVIDIA GPUs if found
if [ "$nvidia_count" -gt 0 ]; then
    if $has_nvidia_smi; then
        # Get memory usage for all NVIDIA GPUs
        nvidia_index=0
        nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader,nounits | while read -r line; do
            index=$(echo "$line" | awk -F ', ' '{print $1}')
            used=$(echo "$line" | awk -F ', ' '{print $2}')
            total=$(echo "$line" | awk -F ', ' '{print $3}')
            
            # Output format: GPU_NAME||VRAM_INFO
            gpu_name="${nvidia_names[$nvidia_index]:-NVIDIA GPU $index}"
            echo "$gpu_name||$used/$total MB"
            
            nvidia_index=$((nvidia_index + 1))
        done
    else
        # If no nvidia-smi, just output the model names if available
        for ((gpu=0; gpu<nvidia_count; gpu++)); do
            gpu_name="${nvidia_names[$gpu]:-NVIDIA GPU $gpu}"
            echo "$gpu_name||Memory info unavailable"
        done
    fi
fi
EOF

    sudo chmod +x /usr/bin/get-gpu-vram

    if [ -f "/usr/bin/dynamic-gpu-vram" ]; then
        sudo rm "/usr/bin/dynamic-gpu-vram"
    fi

    sudo tee "/usr/bin/dynamic-gpu-vram" << 'EOF'
#!/bin/bash

# Run the get-gpu-vram command and capture output
output=$(get-gpu-vram)

# Exit if no output
if [ -z "$output" ]; then
    echo ""
    exit 0
fi

# Initialize JSON modules array
modules=""

# Process each line of output
while IFS= read -r line; do
    # Split by the || delimiter to get name and info
    gpu_name=$(echo "$line" | cut -d'|' -f1)
    vram_info=$(echo "$line" | cut -d'|' -f3-)  # Allows for cases where || might appear in the vram_info
    
    # Escape any quotes in the line
    escaped_vram_info=$(echo "$vram_info" | sed 's/"/\\"/g')
    escaped_gpu_name=$(echo "$gpu_name" | sed 's/"/\\"/g')
    
    # Create a JSON module for this GPU
    if [ -n "$modules" ]; then
        modules="${modules},"
    fi
    modules="${modules}{\"type\": \"command\", \"text\": \"echo '$escaped_vram_info'\", \"key\": \"$escaped_gpu_name\"}"
done <<< "$output"

# Output the JSON
echo "$modules"
EOF

    sudo chmod +x /usr/bin/dynamic-gpu-vram
}