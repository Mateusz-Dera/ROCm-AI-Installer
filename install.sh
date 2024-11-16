#!/bin/bash

# ROCM-AI-Installer
# Copyright © 2023-2024 Mateusz Dera

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

export HSA_OVERRIDE_GFX_VERSION=11.0.0

# Version
version="6.0"

# Default installation path
default_installation_path="$HOME/AI"
# Global variable for installation path
installation_path="$default_installation_path"

# Get the directory of the script
SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
# Requirements directory
REQUIREMENTS_DIR="$SCRIPT_DIR/requirements"

# Check if whiptail is installed
if ! command -v whiptail &> /dev/null; then
    sudo apt update
    sudo apt -y install whiptail
fi

## MENUS
export NEWT_COLORS='
root=,black
textbox=white,black
border=brightgreen,black
window=white,black
title=brightgreen,black
button=black,white
compactbutton=brightgreen,black
listbox=white,black
actlistbox=black,white
actsellistbox=black,brightgreen
checkbox=white,black
actcheckbox=brightgreen,black
'

# Function to display the main menu
show_menu() {
    whiptail --title "ROCm-AI-Installer $version" --menu "Choose an option:" 17 100 10 \
    0 "Installation path ($installation_path)" \
    1 "Install ROCm and required packages" \
    2 "Text generation" \
    3 "Image generation" \
    4 "Video generation" \
    5 "Music generation" \
    6 "Voice generation" \
    7 "3D models generation" \
    8 Tools \
    2>&1 > /dev/tty
}

# Installation path
set_installation_path() {
    # Prompt for installation path, using the default if the user leaves it blank
    new_installation_path=$(whiptail --inputbox "Enter the installation path (default: $default_installation_path):" 10 150 "$installation_path" 3>&1 1>&2 2>&3)

    # If the user leaves it blank, use the default
    new_installation_path=${new_installation_path:-$default_installation_path}

    # Remove trailing "/" if it exists
    new_installation_path=$(echo "$new_installation_path" | sed 's#/$##')

    # Update the installation path variable
    installation_path="$new_installation_path"
}

# Text generation
text_generation() {
    whiptail --title "Text generation" --menu "Choose an option:" 15 100 3 \
    0 "KoboldCPP" \
    1 "Text generation web UI" \
    2 "SillyTavern" \
    2>&1 > /dev/tty
}

# Text generation web UI
text_generation_web_ui() {
    whiptail --title "Text generation web UI" --menu "Choose an option:" 15 100 3 \
    0 "Backup" \
    1 "Install" \
    2 "Restore" \
    2>&1 > /dev/tty
}

text_generation_web_ui_backup() {
    whiptail --title "Text generation web UI" --menu "Choose an option:" 15 100 4 \
    0 "Backup models" \
    1 "Backup characters" \
    2 "Backup presets" \
    3 "Backup instruction-templates" \
    2>&1 > /dev/tty
}

text_generation_web_ui_restore() {
    whiptail --title "Text generation web UI" --menu "Choose an option:" 15 100 4 \
    0 "Restore models" \
    1 "Restore characters" \
    2 "Restore presets" \
    3 "Restore instruction-templates" \
    2>&1 > /dev/tty
}

# SillyTavern
sillytavern() {
    whiptail --title "SillyTavern" --menu "Choose an option:" 15 100 3 \
    0 "Backup" \
    1 "Install" \
    2 "Restore" \
    2>&1 > /dev/tty
}

sillytavern_backup() {
    whiptail --title "SillyTavern" --menu "Choose an option:" 15 100 8 \
    0 "Backup config.yaml" \
    1 "Backup settings.json" \
    2 "Backup characters" \
    3 "Backup groups" \
    4 "Backup worlds" \
    5 "Backup chats" \
    6 "Backup group chats" \
    7 "Backup user avatars images" \
    8 "Backup backgrounds images" \
    9 "Backup themes" \
    10 "Backup presets" \
    11 "Backup context" \
    12 "Backup instruct" \
    13 "Backup sysprompt" \
    2>&1 > /dev/tty
}

sillytavern_restore() {
    whiptail --title "SillyTavern" --menu "Choose an option:" 15 100 8 \
    0 "Restore config.yaml" \
    1 "Restore settings.json" \
    2 "Restore characters" \
    3 "Restore groups" \
    4 "Restore worlds" \
    5 "Restore chats" \
    6 "Restore group chats" \
    7 "Restore user avatars images" \
    8 "Restore backgrounds images" \
    9 "Restore themes" \
    10 "Restore presets" \
    11 "Restore context" \
    12 "Restore instruct" \
    13 "Restore sysprompt" \
    2>&1 > /dev/tty
}

image_generation() {
    whiptail --title "Image generation" --menu "Choose an option:" 15 100 3 \
    0 "ANIMAGINE XL 3.1" \
    1 "Install ComfyUI" \
    2 "Install Artist" \
    2>&1 > /dev/tty
}

animagine_xl() {
    whiptail --title "ANIMAGINE XL 3.1" --menu "Choose an option:" 15 100 3 \
    0 "Backup" \
    1 "Install" \
    2 "Restore" \
    2>&1 > /dev/tty
}

animagine_xl_backup() {
    whiptail --title "ANIMAGINE XL 3.1" --menu "Choose an option:" 15 100 1 \
    0 "Backup config.py" \
    2>&1 > /dev/tty
}

animagine_xl_restore() {
    whiptail --title "ANIMAGINE XL 3.1" --menu "Choose an option:" 15 100 1 \
    0 "Restore config.py" \
    2>&1 > /dev/tty
}

video_generation() {
    whiptail --title "Video generation" --menu "Choose an option:" 15 100 1 \
    0 "Install Cinemo" \
    2>&1 > /dev/tty
}

music_generation() {
    whiptail --title "Music generation" --menu "Choose an option:" 15 100 1 \
    0 "Install AudioCraft" \
    2>&1 > /dev/tty
}

voice_generation() {
    whiptail --title "Voice generation" --menu "Choose an option:" 15 100 3 \
    0 "Install WhisperSpeech web UI" \
    1 "Install MeloTTS" \
    2 "Install MetaVoice" \
    2>&1 > /dev/tty
}

d3_generation() {
    whiptail --title "3D generation" --menu "Choose an option:" 15 100 1 \
    0 "Install TripoSR" \
    2>&1 > /dev/tty
}

tools() {
    whiptail --title "Tools" --menu "Choose an option:" 15 100 1 \
    0 "Install ExLlamaV2" \
    2>&1 > /dev/tty
}
## INSTALLATIONS

# Remove old
remove_old() {
    sudo apt purge -y rocm*
    sudo apt purge -y hip*
    sudo apt purge -y nvidia*

    if [ -f /etc/apt/keyrings/rocm.gpg ]; then
        sudo rm /etc/apt/keyrings/rocm.gpg
    fi

    if [ -f /etc/apt/sources.list.d/amdgpu.list ]; then
        sudo rm /etc/apt/sources.list.d/amdgpu.list
    fi

    if [ -f /etc/apt/sources.list.d/rocm.list ]; then
        sudo rm /etc/apt/sources.list.d/rocm.list
    fi

    if [ -f /etc/apt/preferences.d/rocm-pin-600 ]; then
        sudo rm /etc/apt/preferences.d/rocm-pin-600
    fi

    sudo apt autoremove -y
}

# Repositories
repo(){
    # Update
    sudo apt update -y && sudo apt upgrade -y
    
    # Wget
    sudo apt install -y wget

    # AMDGPU
    sudo apt-add-repository -y -s -s
    sudo apt install -y "linux-headers-$(uname -r)" \
	"linux-modules-extra-$(uname -r)"
    sudo mkdir --parents --mode=0755 /etc/apt/keyrings
    wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
    gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null
    echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/6.2.4/ubuntu noble main' \
    | sudo tee /etc/apt/sources.list.d/amdgpu.list
    sudo apt update -y
    sudo apt install -y amdgpu-dkms

    # ROCm
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/6.2.4 noble main" \
    | sudo tee --append /etc/apt/sources.list.d/rocm.list
    echo -e 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600' \
    | sudo tee /etc/apt/preferences.d/rocm-pin-600
    sudo apt update -y
    sudo apt install -y rocm-dev rocm-libs rocm-hip-sdk rocm-libs
}

profile(){
    # Check if there's a line starting with PATH=
    if grep -q '^PATH=' ~/.profile; then
        # If the line exists, add new paths at the beginning if they're not already there
        if ! grep -q '/opt/rocm/bin' ~/.profile || ! grep -q '/opt/rocm/opencl/bin' ~/.profile; then
            sed -i '/^PATH=/ s|PATH=|PATH=/opt/rocm/bin:/opt/rocm/opencl/bin:|' ~/.profile
            echo "Added new paths ~/.profile"
        else
            echo "Paths already exist in ~/.profile"
        fi
    else
        # If the line doesn't exist, add a new line with these paths at the beginning
        echo 'PATH=/opt/rocm/bin:/opt/rocm/opencl/bin:$PATH' >> ~/.profile
        echo "Added a new PATH line to ~/.profile"
    fi
}

# Function to install ROCm and basic packages
install_rocm() {
    sudo apt update -y
    remove_old

    repo

    sudo tee --append /etc/ld.so.conf.d/rocm.conf <<EOF
/opt/rocm/lib
/opt/rocm/lib64
EOF
    sudo ldconfig

    profile

    sudo apt install -y git git-lfs
    sudo apt install -y libstdc++-12-dev
    sudo apt install -y libtcmalloc-minimal4
    sudo apt install -y git git-lfs
    sudo apt install -y python3.12 python3.12-venv python3.12-dev python3.12-tk
    sudo apt install -y libgl1
    sudo apt install -y ffmpeg
    sudo apt install -y libmecab-dev
    sudo apt install -y rustc 

    sudo snap install node --classic
}

# Universal function
install() {
    local git_repo=$1
    local git_commit=$2
    local start_command=$3
    local python_version=${4:-python3.12}

    # Check if git repo and commit are provided
    if [[ -z "$git_repo" || -z "$git_commit" || -z "$start_command" ]]; then
        echo "Error: git repo, git commit, and start command must be provided"
        exit 1
    fi

    # Get the repository name
    local repo_name=$(basename "$git_repo" .git)

    # Check if Python version is installed
    if ! command -v $python_version &> /dev/null; then
        echo "Install $python_version first"
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
    $python_version -m venv .venv --prompt $repo_name

    # Activate the virtual environment
    source .venv/bin/activate

    # Upgrade pip
    pip install --upgrade pip

    # Install requirements
    if [ -f "$REQUIREMENTS_DIR/$repo_name.txt" ]; then
        pip install -r $REQUIREMENTS_DIR/$repo_name.txt
    fi

    # Create run.sh
    tee --append run.sh <<EOF
#!/bin/bash
source $installation_path/$repo_name/.venv/bin/activate
export HSA_OVERRIDE_GFX_VERSION=$HSA_OVERRIDE_GFX_VERSION
export CUDA_VISIBLE_DEVICES=0
export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1
export TORCH_BLAS_PREFER_HIPBLASLT=0
$start_command
EOF
    chmod +x run.sh
}

# KoboldCPP
install_koboldcpp() {
    install "https://github.com/YellowRoseCx/koboldcpp-rocm.git" "5ac2de794ddf791194854c86cb8512e9ab6b4cc4" "python koboldcpp.py"
    make LLAMA_HIPBLAS=1 -j4
}

# Text generation web UI
install_text_generation_web_ui() {
    install "https://github.com/oobabooga/text-generation-webui.git" "cc8c7ed2093cbc747e7032420eae14b5b3c30311" "python server.py --api --listen --extensions sd_api_pictures send_pictures gallery"

    # Additional requirements
    pip install git+https://github.com/ROCm/flash-attention@b28f18350af92a68bec057875fd486f728c9f084 --no-build-isolation --extra-index-url https://download.pytorch.org/whl/rocm6.2
    pip install git+https://github.com/turboderp/exllamav2@03b2d551b2a3a398807199456737859eb34c9f9c --no-build-isolation --extra-index-url https://download.pytorch.org/whl/rocm6.2
    CMAKE_ARGS="-DGGML_HIPBLAS=on" pip install llama-cpp-python==0.3.1 --extra-index-url https://download.pytorch.org/whl/rocm6.2
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
    git checkout a3ca407b2714df5af5a9f83aa925fd64fb778e24

    mv ./start.sh ./run.sh

    # Default config
    cd ./default
    sed -i 's/listen: false/listen: true/' config.yaml
    sed -i 's/whitelistMode: true/whitelistMode: false/' config.yaml
    sed -i 's/basicAuthMode: false/basicAuthMode: true/' config.yaml
}

# ANIMAGINE XL 3.1
install_animagine_xl() {
    install "https://huggingface.co/spaces/cagliostrolab/animagine-xl-3.1" "76b0dfc75bdc06e7bceeae96de3c09c8fa833008" "python app.py"
    sed -i 's/demo.queue(max_size=20).launch(debug=IS_COLAB, share=IS_COLAB)/demo.queue(max_size=20).launch(debug=IS_COLAB, share=False, server_name="0.0.0.0")/' app.py
}

# Artist
install_artist() {
    install "https://github.com/songrise/Artist.git" "dcc252adb81e7e57e1763758cf57b8c865dbe1bb" "python injection_main.py --mode app"
    sed -i 's/app.launch()/app.launch(share=False, server_name="0.0.0.0")/' injection_main.py
}

# Cinemo
install_cinemo() {
    install "https://huggingface.co/spaces/maxin-cn/Cinemo" "2bf400b88528c0ff3aedeaac064ca98b42acf2ca" "python demo.py"
    sed -i 's/demo.launch(debug=False, share=True)/demo.launch(debug=False, share=False, server_name="0.0.0.0")/' demo.py
}

# ComfyUI
install_comfyui() {
    local choices=$1
    
    install "https://github.com/comfyanonymous/ComfyUI.git" "122c9ca1cec50e78fb0fb0eb7a3d7fd015e7f037" "python3 ./main.py --listen"

    # Process each selected choice
    for choice in $choices; do
        case $choice in
            "0")
                # ComfyUI-Manager
                cd $installation_path/ComfyUI/custom_nodes
                git clone https://github.com/ltdrdata/ComfyUI-Manager
                cd ComfyUI-Manager
                git checkout b6a8e6ba8147080a320b1b91c93a0b1cbdb93136
                ;;
            "1")
                # ComfyUI_UltimateSDUpscale
                cd $installation_path/ComfyUI/custom_nodes
                git clone https://github.com/ssitu/ComfyUI_UltimateSDUpscale --recursive
                cd ComfyUI_UltimateSDUpscale
                git checkout e617ff20e7ef5baf6526c5ff4eb46a35d24ecbba
                ;;
            "2")
                # AuraFlow
                cd $installation_path/ComfyUI
                git clone --no-checkout https://huggingface.co/fal/AuraFlow-v0.3
                cd AuraFlow-v0.3
                git sparse-checkout init --cone
                git sparse-checkout set aura_flow_0.3.safetensors
                git checkout 2cd8588f04c886002be4571697d84654a50e3af3
                mv ./aura_flow_0.3.safetensors $installation_path/ComfyUI/models/checkpoints
                rm -rf $installation_path/ComfyUI/AuraFlow-v0.3
                ;;
            "3")
                # Flux
                cd $installation_path/ComfyUI
                git clone https://huggingface.co/Comfy-Org/flux1-schnell
                cd flux1-schnell
                git checkout f2808ab17fe9ff81dcf89ed0301cf644c281be0a
                mv ./flux1-schnell-fp8.safetensors $installation_path/ComfyUI/models/checkpoints
                rm -rf $installation_path/ComfyUI/flux1-schnell
                ;;
            "4")
                # AnimePro FLUX
                cd $installation_path/ComfyUI/models/checkpoints
                wget 'https://civitai.com/api/download/models/1046190?type=Model&format=SafeTensor&size=pruned&fp=fp8'
                ;;
            "5")
                # Mochi
                cd $installation_path/ComfyUI/custom_nodes
                git clone https://github.com/kijai/ComfyUI-MochiWrapper.git
                cd ComfyUI-MochiWrapper
                git checkout e1bd05240ac31b72166e9d952c75dd5735352311
                cd $installation_path/ComfyUI/models/checkpoints
                wget https://huggingface.co/Kijai/Mochi_preview_comfy/resolve/83359d26a7e2bbe200ecbfda8ebff850fd03b545/mochi_preview_dit_fp8_e4m3fn.safetensors
                cd $installation_path/ComfyUI/models/vae
                if [ ! -d "mochi" ]; then
                    mkdir mochi
                fi
                cd mochi
                wget https://huggingface.co/Kijai/Mochi_preview_comfy/resolve/83359d26a7e2bbe200ecbfda8ebff850fd03b545/mochi_preview_vae_encoder_bf16_.safetensors
                wget https://huggingface.co/Kijai/Mochi_preview_comfy/resolve/83359d26a7e2bbe200ecbfda8ebff850fd03b545/mochi_preview_vae_decoder_bf16_.safetensors
                ;;
            *)
                echo "Unknown option: $choice"
                ;;
        esac
    done
}

# AudioCraft
install_audiocraft() {
    install "https://github.com/facebookresearch/audiocraft.git" "adf0b04a4452f171970028fcf80f101dd5e26e19" "python -m demos.musicgen_app --listen 0.0.0.0"
}

# WhisperSpeech web UI
install_whisperspeech_web_ui(){
    install "https://github.com/Mateusz-Dera/whisperspeech-webui.git" "295f314c6b267683d07b2a962a787a9a0adc62a2" "python3 webui.py --listen"
    pip install -r requirements_rocm_6.2.txt
}

# MeloTTS
install_melotts(){
    install "https://github.com/myshell-ai/MeloTTS" "5b538481e24e0d578955be32a95d88fcbde26dc8" "python3.12 -m venv .venv --prompt MeloTTS"
    rm requirements.txt
    touch requirements.txt
    pip install -e . --extra-index-url https://download.pytorch.org/whl/rocm6.2
    python -m unidic download
}

install_metavoice(){
    install "https://github.com/metavoiceio/metavoice-src.git" "e606e8af2b154db2ee7eb76f9ab4389fd8e52822" "ANONYMIZED_TELEMETRY=False python app.py"

    rm ./requirements.txt
    touch ./requirements.txt

    git clone https://github.com/facebookresearch/audiocraft.git
    cd audiocraft
    git checkout adf0b04a4452f171970028fcf80f101dd5e26e19
    rm ./requirements.txt
    touch ./requirements.txt
    pip install -e .

    cd $installation_path/metavoice-src

    pip install -e .
    sed -i 's|TTS_MODEL = tyro\.cli(TTS, args=\["--telemetry_origin", "webapp"\])|TTS_MODEL = tyro.cli(TTS)|' app.py

    sed -i '/logging\.basicConfig(level=logging\.INFO, handlers=\[logging\.StreamHandler(sys\.stdout), logging\.StreamHandler(sys\.stderr)\])/a def get_telemetry_status():\n    value = os.getenv("ANONYMIZED_TELEMETRY", "True")  # Default to "True"\n    return value.lower() in ("1", "true", "yes")' ./fam/telemetry/posthog.py
    sed -i 's/if not os.getenv("ANONYMIZED_TELEMETRY", True) or "pytest" in sys.modules:/if not get_telemetry_status() or "pytest" in sys.modules:/g' ./fam/telemetry/posthog.py
}

install_triposr(){
    install "https://github.com/VAST-AI-Research/TripoSR" "d26e33181947bbbc4c6fc0f5734e1ec6c080956e" "python3 gradio_app.py --listen"

    # Additional requirements
    pip install git+https://github.com/tatsy/torchmcubes.git@cb81cddece46a8a126b08f7fbb9742f8605eefab --extra-index-url https://download.pytorch.org/whl/rocm6.2
}

install_exllamav2(){
    install "https://github.com/turboderp/exllamav2" "40e37f494488d930bb196b6e01d9c5c8a64456e8" "python3 -i"
    pip install . --extra-index-url https://download.pytorch.org/whl/rocm6.2
}
## MAIN

backup_and_restore() {
    # Check if folder exists
    if ! [ -e "$1" ]; then
        echo "Folder or file '$1' does not exist." && exit 1 
    fi

    if ! [ -d "$2" ]; then
        # Create backup folder
        mkdir -p "$2" || (echo "Failed to create folder '$2'." && exit 1)
    else
        rm -rf "$2" || (echo "Failed to remove old folder '$2'." && exit 1)
    fi

    # Copy the contents $1 to $2
    rsync -av --progress --delete "$1/" "$2" || (echo "Failed to copy contents of '$1' to '$2'." && exit 1)
}

backup_and_restore_file() {
    # Check if file exists
    if ! [ -e "$1/$3" ]; then
        echo "File '$1/$3' does not exist." && exit 1 
    fi

    if ! [ -d "$2" ]; then
        # Create backup folder
        mkdir -p "$2" || (echo "Failed to create folder '$2'." && exit 1)
    fi

    # Copy the contents $1 to $2
    cp -f "$1/$3" "$2/$3" || (echo "Failed to copy contents of '$1$3' to '$2'." && exit 1)
}

# Main loop
while true; do
    choice=$(show_menu)

    case $choice in
        0)
            # Set installation path
            set_installation_path
            ;;
        1)
            # Install ROCm and basic packages
            install_rocm
            ;;
        2)
            # Text generation
            first=true
            while $first; do
            
                choice=$(text_generation)

                case $choice in
                    0)
                        # KoboldCPP
                        install_koboldcpp
                        ;;
                    1)
                        # Text generation web UI
                        second=true
                        while $second; do
                            choice=$(text_generation_web_ui)

                            case $choice in
                                0)
                                    # Backup
                                    next=true
                                    while $next; do
                                        choice=$(text_generation_web_ui_backup)
                                        case $choice in
                                            0)
                                                # Backup models
                                                backup_and_restore $installation_path/text-generation-webui/models $installation_path/Backups/text-generation-webui/models
                                                ;;
                                            1)
                                                # Backup characters
                                                backup_and_restore $installation_path/text-generation-webui/characters $installation_path/Backups/text-generation-webui/characters
                                                ;;
                                            2)
                                                # Backup presets
                                                backup_and_restore $installation_path/text-generation-webui/presets $installation_path/Backups/text-generation-webui/presets
                                                ;;
                                            3)
                                                # Backup instruction-templates
                                                backup_and_restore $installation_path/text-generation-webui/instruction-templates $installation_path/Backups/text-generation-webui/instruction-templates
                                                ;;
                                            *)
                                                next=false
                                                ;;
                                        esac
                                    done
                                    ;;
                                1)
                                    # Install
                                    install_text_generation_web_ui
                                    ;;
                                2)
                                    # Restore
                                    next=true
                                    while $next; do
                                        choice=$(text_generation_web_ui_restore)

                                        case $choice in
                                            0)
                                                # Restore models
                                                backup_and_restore $installation_path/Backups/text-generation-webui/models $installation_path/text-generation-webui/models
                                                ;;
                                            1)
                                                # Restore characters
                                                backup_and_restore $installation_path/Backups/text-generation-webui/characters $installation_path/text-generation-webui/characters
                                                ;;
                                            2)
                                                # Restore presets
                                                backup_and_restore $installation_path/Backups/text-generation-webui/presets $installation_path/text-generation-webui/presets
                                                ;;
                                            3)
                                                # Restore instruction-templates
                                                backup_and_restore $installation_path/Backups/text-generation-webui/instruction-templates $installation_path/text-generation-webui/instruction-templates
                                                ;;
                                            *)
                                                next=false
                                                ;;
                                        esac
                                    done
                                    ;;
                                *)
                                    second=false
                                    ;;
                            esac
                        done
                        ;;
                    2)
                        # SillyTavern
                        second=true
                        while $second; do
                            choice=$(sillytavern)

                            case $choice in
                                0)
                                    next=true
                                    while $next; do
                                        choice=$(sillytavern_backup)
                                        case $choice in
                                            0)
                                                # Backup config
                                                backup_and_restore_file $installation_path/SillyTavern $installation_path/Backups/SillyTavern config.yaml
                                                ;;
                                            1)
                                                # Backup settings
                                                backup_and_restore_file $installation_path/SillyTavern/data/default-user $installation_path/Backups/SillyTavern/data/default-user settings.json
                                                ;;
                                            2)
                                                # Backup characters
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/characters $installation_path/Backups/SillyTavern/data/default-user/characters
                                                ;;
                                            3)
                                                # Backup groups
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/groups $installation_path/Backups/SillyTavern/data/default-user/groups
                                                ;;
                                            4)
                                                # Backup worlds
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/worlds $installation_path/Backups/SillyTavern/data/default-user/worlds
                                                ;;
                                            5)
                                                # Backup chats
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/chats $installation_path/Backups/SillyTavern/data/default-user/chats
                                                ;;
                                            6)
                                                # Backup group chats
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/group\ chats $installation_path/Backups/SillyTavern/data/default-user/group\ chats
                                                ;;
                                            7)
                                                # Backup user avatars images
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/User\ Avatars $installation_path/Backups/SillyTavern/data/default-user/User\ Avatars
                                                ;;
                                            8)
                                                # Backup backgrounds images
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/backgrounds $installation_path/Backups/SillyTavern/data/default-user/backgrounds
                                                ;;
                                            9)
                                                # Backup themes
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/themes $installation_path/Backups/SillyTavern/data/default-user/themes
                                                ;;
                                            10)
                                                # Backup presets
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/TextGen\ Settings $installation_path/Backups/SillyTavern/data/default-user/TextGen\ Settings
                                                ;;
                                            11)
                                                # Backup context
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/context $installation_path/Backups/SillyTavern/data/default-user/context
                                                ;;
                                            12)
                                                # Backup instruct
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/instruct $installation_path/Backups/SillyTavern/data/default-user/instruct
                                                ;;
                                            13)
                                                # Backup sysprompt
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/sysprompt $installation_path/Backups/SillyTavern/data/default-user/sysprompt
                                                ;;
                                            *)
                                                next=false
                                                ;;
                                        esac
                                    done
                                    ;;
                                1)
                                    # Install
                                    install_sillytavern
                                    ;;
                                2)  
                                    # Restore
                                    next=true
                                    while $next; do
                                        choice=$(sillytavern_restore)
                                        case $choice in
                                            0)
                                                # Restoreconfig
                                                backup_and_restore_file $installation_path/Backups/SillyTavern $installation_path/SillyTavern config.yaml
                                                ;;
                                            1)
                                                # Restore settings
                                                backup_and_restore_file $installation_path/Backups/SillyTavern/data/default-user $installation_path/SillyTavern/data/default-user settings.json
                                                ;;
                                            2)
                                                # Restore characters
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/characters $installation_path/SillyTavern/data/default-user/characters
                                                ;;
                                            3)
                                                # Restore groups
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/groups $installation_path/SillyTavern/data/default-user/groups
                                                ;;
                                            4)
                                                # Restore worlds
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/worlds $installation_path/SillyTavern/data/default-user/worlds
                                                ;;
                                            5)
                                                # Restore chats
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/chats $installation_path/SillyTavern/data/default-user/chats
                                                ;;
                                            6)
                                                # Restore group chats
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/group\ chats $installation_path/SillyTavern/data/default-user/group\ chats
                                                ;;
                                            7)
                                                # Restore user avatars images
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/User\ Avatars $installation_path/SillyTavern/data/default-user/User\ Avatars
                                                ;;
                                            8)
                                                # Restore backgrounds images
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/backgrounds $installation_path/SillyTavern/data/default-user/backgrounds
                                                ;;
                                            9)
                                                # Restore themes
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/themes $installation_path/SillyTavern/data/default-user/themes
                                                ;;
                                            10)
                                                # Restore presets
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/TextGen\ Settings $installation_path/SillyTavern/data/default-user/TextGen\ Settings
                                                ;;
                                            11)
                                                # Restore context
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/context $installation_path/SillyTavern/data/default-user/context
                                                ;;
                                            12)
                                                # Restore instruct
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/instruct $installation_path/SillyTavern/data/default-user/instruct
                                                ;;
                                            13)
                                                # Restore sysprompt
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/sysprompt $installation_path/SillyTavern/data/default-user/sysprompt
                                                ;;
                                            *)
                                                next=false
                                                ;;
                                        esac
                                    done
                                    ;;
                                *)
                                    second=false
                                ;;
                            esac
                        done
                        ;;
                    *)
                        first=false
                        ;;
                esac
            done
            ;;
        3)
            # Image generation
            first=true
            while $first; do
                choice=$(image_generation)
                case $choice in
                    0) 
                        # ANIMAGINE XL 3.1
                        second=true
                        while $second; do
                            choice=$(animagine_xl)
                            case $choice in
                                0)
                                    # Backup
                                    next=true
                                    while $next; do
                                        choice=$(animagine_xl_backup)
                                        case $choice in
                                            0)
                                                # Backup config.py
                                                backup_and_restore_file $installation_path/animagine-xl-3.1 $installation_path/Backups/animagine-xl-3.1 config.py
                                                ;;
                                            *)
                                                next=false
                                                ;;
                                        esac
                                    done
                                    ;;
                                1)
                                    # Install
                                    install_animagine_xl
                                    ;;
                                2)
                                    # Restore
                                    next=true
                                    while $next; do
                                        choice=$(animagine_xl_restore)
                                        case $choice in
                                            0)
                                                # Restore config.py
                                                backup_and_restore_file $installation_path/Backups/animagine-xl-3.1 $installation_path/animagine-xl-3.1 config.py
                                                ;;
                                            *)
                                                next=false
                                                ;;
                                        esac
                                    done
                                    ;;
                                *)
                                    second=false
                                    ;;
                            esac
                        done
                        ;;
                    1)
                        # ComfyUI
#                         CHOICES=$(whiptail --separate-output --checklist "Choose options" 10 35 5 \
#   "1" "The first option" ON \
#   "2" "The second option" ON \
#   "3" "The third option" OFF \
#   "4" "The fourth option" OFF 3>&1 1>&2 2>&3)

                        CHOICES=$(whiptail --separate-output --checklist "Addons:" 10 35 6 \
    "0" "ComfyUI-Manager" ON \
    "1" "UltimateSDUpscale" ON \
    "2" "AuraFlow-v0.3" ON \
    "3" "FLUX.1-schnell " ON \
    "4" "AnimePro FLUX" ON \
    "5" "Mochi" ON 3>&1 1>&2 2>&3) && install_comfyui $CHOICES
                        ;;
                    2)
                        # Artist
                        install_artist
                        ;;
                    *)
                        first=false
                        ;;
                esac
            done
            ;;
         4)
            # Video generation
            first=true
            while $first; do
            
                choice=$(video_generation)

                case $choice in
                    0)
                        # Cinemo
                        install_cinemo
                        ;;
                    *)
                        first=false
                        ;;
                esac
            done
            ;;
        5)
            # Music generation
            first=true
            while $first; do
            
                choice=$(music_generation)

                case $choice in
                    0)
                        # AudioCraft
                        install_audiocraft
                        ;;
                    *)
                        first=false
                        ;;
                esac
            done
            ;;
        6)
            # Voice generation
            first=true
            while $first; do
            
                choice=$(voice_generation)

                case $choice in
                    0)
                        # WhisperSpeech web UI
                        install_whisperspeech_web_ui
                        ;;
                    1)
                        # MeloTTS
                        install_melotts
                        ;;
                    2)
                        # MetaVoice
                        install_metavoice
                        ;;
                    *)
                        first=false
                        ;;
                esac
            done
            ;;
        7)
            # 3D generation
            first=true
            while $first; do
            
                choice=$(d3_generation)

                case $choice in
                    0)
                        # TripoSR
                        install_triposr
                        ;;
                    *)
                        first=false
                        ;;
                esac
            done
            ;;
        8)
            # Tools
            first=true
            while $first; do
            
                choice=$(tools)

                case $choice in
                    0)
                        # ExLlamaV2
                        install_exllamav2
                        ;;
                    *)
                        first=false
                        ;;
                esac
            done
            ;;
        *)
            # Cancel or Exit
            whiptail --yesno "Do you really want to exit?" 10 30
            if [ $? -eq 0 ]; then
                exit 0
            fi
            ;;
    esac
done