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

arch="x86_64"
export HSA_OVERRIDE_GFX_VERSION=11.0.0

# Default installation path
default_installation_path="$HOME/AI"
# Global variable for installation path
installation_path="$default_installation_path"

sudo apt-get update
sudo apt-get upgrade -y

sudo add-apt-repository -y -s deb http://security.ubuntu.com/ubuntu jammy main universe

sudo mkdir --parents --mode=0755 /etc/apt/keyrings
sudo rm /etc/apt/keyrings/rocm.gpg
sudo rm /etc/apt/sources.list.d/rocm.list
wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
    gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/5.7.2 jammy main" \
    | sudo tee --append /etc/apt/sources.list.d/rocm.list
echo -e 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600' \
    | sudo tee /etc/apt/preferences.d/rocm-pin-600 
sudo rm /etc/apt/sources.list.d/amdgpu.list
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/latest/ubuntu jammy main' \
    | sudo tee /etc/apt/sources.list.d/amdgpu.list
sudo apt update -y 

sudo apt-add-repository -y -s -s
sudo apt install -y "linux-headers-$(uname -r)" \
	"linux-modules-extra-$(uname -r)"

sudo apt-get install -y whiptail wget git git-lfs ffmpeg libstdc++-12-dev libtcmalloc-minimal4 python3 python3-venv imagemagick libgl1 libglib2.0-0 amdgpu-dkms rocm-dev rocm-libs rocm-hip-sdk rocm-dkms rocm-libs

sudo rm /etc/ld.so.conf.d/rocm.conf
sudo tee --append /etc/ld.so.conf.d/rocm.conf <<EOF
/opt/rocm/lib
/opt/rocm/lib64
EOF
sudo ldconfig

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
            
            ;;
        2)
            # Action for Option 2
            if ! command -v python3.11 &> /dev/null; then
                echo "Install Python 3.11 first"
                exit 1
            fi
            mkdir -p $installation_path
            cd $installation_path
            rm -rf text-generation-webui
            git clone https://github.com/oobabooga/text-generation-webui
            cd text-generation-webui
            python3.11 -m venv .venv --prompt TextGen
            source .venv/bin/activate
            pip install --pre cmake colorama filelock lit numpy Pillow Jinja2 \
                mpmath fsspec MarkupSafe certifi filelock networkx \
                sympy packaging requests \
                    --index-url https://download.pytorch.org/whl/nightly/rocm5.7
            pip install --pre torch==2.2.0.dev20231128   --index-url https://download.pytorch.org/whl/nightly/rocm5.7
            pip install torchdata==0.7.1
            pip install --pre torch==2.2.0.dev20231128 torchvision==0.17.0.dev20231128+rocm5.7 torchtext==0.17.0.dev20231128+cpu torchaudio triton pytorch-triton pytorch-triton-rocm    --index-url https://download.pytorch.org/whl/nightly/rocm5.7

            cd $installation_path
            rm -rf bitsandbytes-rocm-5.6
            git clone https://github.com/arlo-phoenix/bitsandbytes-rocm-5.6.git
            cd bitsandbytes-rocm-5.6/
            BUILD_CUDA_EXT=0 pip install -r requirements.txt --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7
            make hip ROCM_TARGET=gfx1100 ROCM_HOME=/opt/rocm-5.7.2/
            pip install . --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7

            pip install -U --index-url https://aiinfra.pkgs.visualstudio.com/PublicPackages/_packaging/Triton-Nightly/pypi/simple/ triton-nightly

            pip install cmake ninja

            cd $installation_path
            rm -rf flash-attention
            git clone https://github.com/ROCmSoftwarePlatform/flash-attention.git
            cd flash-attention
            pip install . --offload-arch $arch

            cd $installation_path/text-generation-webui
            sed -i "s@bitsandbytes==@bitsandbytes>=@g" requirements_amd.txt 
            pip install -r requirements_amd.txt 

            git clone https://github.com/turboderp/exllama repositories/exllama
            git clone https://github.com/turboderp/exllamav2 repositories/exllamav2

            tee --append run.sh <<EOF
#!/bin/bash
source $installation_path/text-generation-webui/.venv/bin/activate
python server.py --listen --loader=exllama  \
  --auto-devices --extensions sd_api_pictures send_pictures gallery 
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
