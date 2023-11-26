#!/bin/bash

# ROCM-AI-Installer
# Copyright © 2023 Mateusz Dera

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

sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y git whiptail

# Default installation path
default_installation_path="$HOME/AI"
# Global variable for installation path
installation_path="$default_installation_path"

# Function to display the main menu
show_menu() {
    whiptail --title "Menu Example" --menu "Choose an option:" 15 100 4 \
    0 "Set Installation Path ($installation_path)" \
    1 "stable-diffusion-webui" \
    2 "text-generation-webui" \
    3 "SillyTavern" \
    2>&1 > /dev/tty
}

# Function to display the SillyTavern submenu
show_sillytavern_submenu() {
    whiptail --title "SillyTavern Submenu" --menu "Choose an option for SillyTavern:" 15 150 2 \
    1 "SillyTavern" \
    2 "SillyTavern + Extras + chromadb + XTTS-v2" \
    2>&1 > /dev/tty
}

# Function to set the installation path
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

# Main loop
while true; do
    choice=$(show_menu)

    case $choice in
        0)
            # Set Installation Path
            set_installation_path
            ;;
        1)
            # Action for Option 1
            if ! command -v python3.11 &> /dev/null; then
                echo "Install Python 3.11 first"
                exit 1
            fi
            sudo apt install -y cmake libtcmalloc-minimal4 imagemagick ffmpeg
            mkdir -p $installation_path
            cd $installation_path
            rm -Rf stable-diffusion-webui
            git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
            cd stable-diffusion-webui
            python3.11 -m venv .venv
            source .venv/bin/activate
            pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm5.6
            pip install gensim tables -U 
            pip install tensorflow-rocm
            pip install cupy-rocm-4-3 cupy-rocm-5-0
            pip install accelerate -U
            pip install onnx
            pip install super-gradients
            pip install -r requirements.txt --extra-index-url https://download.pytorch.org/whl/rocm5.6
            tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export TF_ENABLE_ONEDNN_OPTS=0
export TORCH_COMMAND="pip install torch torchvision --index-url https://download.pytorch.org/whl/rocm5.6"
export COMMANDLINE_ARGS="--api"
#export CUDA_VISIBLE_DEVICES="1"
source $installation_path/stable-diffusion-webui/.venv/bin/activate
$installation_path/stable-diffusion-webui/webui.sh 
EOF
            chmod +x run.sh
            ;;
        2)
            # Action for Option 2
            if ! command -v python3.10 &> /dev/null; then
                cd /tmp
                wget https://www.python.org/ftp/python/3.10.11/Python-3.10.11.tgz
                sudo apt-get update
                sudo apt-get install -y make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev xz-utils tk-dev
                tar xvf -O Python-3.10.11.tgz
                cd Python-3.10.11
                ./configure --enable-optimizations --with-ensurepip=install
                make -j 4
                sudo make altinstall
            fi
            mkdir -p $installation_path
            cd $installation_path
            rm -Rf text-generation-webui
            git clone https://github.com/oobabooga/text-generation-webui.git
            cd $installation_path/text-generation-webui
            python3.10 -m venv .venv
            source $installation_path/text-generation-webui/.venv/bin/activate
            pip install cmake colorama filelock lit numpy --index-url https://download.pytorch.org/whl/nightly/rocm5.7
            pip install torch torchvision torchtext torchaudio torchdata triton pytorch-triton pytorch-triton-rocm --index-url https://download.pytorch.org/whl/nightly/rocm5.7
            pip install torch-grammar
            cd $installation_path
            git clone https://github.com/arlo-phoenix/bitsandbytes-rocm-5.6.git
            cd $installation_path/bitsandbytes-rocm-5.6 
            BUILD_CUDA_EXT=0 pip install -r requirements.txt --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7
            make hip ROCM_TARGET=gfx1100 ROCM_HOME=/opt/rocm/
            pip install --upgrade pip
            pip install . --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7
            pip install gradio psutil markdown transformers accelerate datasets peft
            pip install gensim tables blosc2 cython
            pip install spyder python-lsp-black 
            pip install jaxlib-rocm
            pip install jax==0.4.6
            pip install tensorflow-rocm
            pip install cupy-rocm-5-0
            pip install loader
            pip install logger
            pip install -U scikit-learn
            pip install -U --index-url https://aiinfra.pkgs.visualstudio.com/PublicPackages/_packaging/Triton-Nightly/pypi/simple/ triton-nightly
            cd $installation_path/text-generation-webui
            mkdir repositories
            cd $installation_path/text-generation-webui/repositories
            git clone https://github.com/turboderp/exllama
            cd exllama
            pip install -r requirements.txt --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7
            cd $installation_path/text-generation-webui/repositories
            git clone https://github.com/turboderp/exllamav2.git
            cd exllamav2
            pip install -r requirements.txt --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7
            pip install fastparquet
            python setup.py install --user
            pip install -U . 
            cd $installation_path/text-generation-webui
            pip install bs4
            pip install gradio==3.40.0
            pip install tiktoken
            pip install SpeechRecognition
            pip install sse_starlette
            pip install chromadb==0.4.15 sentence_transformers pytextrank num2words optuna
            export CXX=hipcc
            export HIP_VISIBLE_DEVICES=0
            export HSA_OVERRIDE_GFX_VERSION=11.0.0
            CMAKE_ARGS="-DLLAMA_HIPBLAS=on" pip install llama-cpp-python
            pip install requests
            tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
source $installation_path/.venv/bin/activate
export TF_ENABLE_ONEDNN_OPTS=0
python3.10 server.py --listen --loader=exllama --auto-devices --extensions sd_api_pictures send_pictures gallery api superboogav2
EOF
            chmod u+x run.sh
            ;;
        3)
            # Submenu for SillyTavern
            submenu_choice=$(show_sillytavern_submenu)
            
            case $submenu_choice in
                1)
                    # Action for SillyTavern
                    whiptail --msgbox "You selected SillyTavern" 10 120
                    ;;
                2)
                    # Action for SillyTavern + Extras + chromadb + XTTS-v2
                    whiptail --msgbox "You selected SillyTavern + Extras + chromadb + XTTS-v2" 10 120
                    ;;
                *)
                    # Cancel
                    ;;
            esac
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