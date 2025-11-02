
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

# GPU Variables
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export GFX=gfx1100

#? Preparing for future support for ZLUDA
#? https://github.com/vosen/ZLUDA
#?
#? ZLUDA
#? ZLUDA_URL="https://github.com/vosen/ZLUDA/releases/download/v6-preview.8/zluda-linux-f2504cb.tar.gz"
#? ZLUDA_FILE=$(basename "$ZLUDA_URL")
#? export ZLUDA_PATH="/opt/zluda"

# Version
version="9.0"

# Default installation path
default_installation_path="$HOME/AI"
# Global variable for installation path
installation_path="$default_installation_path"

# Get the directory of the script
SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
# Requirements directory
REQUIREMENTS_DIR="$SCRIPT_DIR/requirements"
CUSTOM_FILES_DIR="$SCRIPT_DIR/custom_files"

# Check if whiptail is installed
if ! command -v whiptail &> /dev/null; then
    sudo apt update
    sudo apt install -y whiptail
fi

source ./menu.sh
source ./interfaces.sh

# Remove old ROCm
uninstall_rocm() {
    # Remove old ROCm packages
    sudo apt purge -y rocm*
    sudo apt purge -y hip*
    sudo apt purge -y amdgpu*

    # Remove old ROCm directories
    if [ -d /opt/rocm* ]; then
        sudo rm -r /opt/rocm*
    fi

    # Remove old ROCm keyrings and sources
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

    # Clean up the package cache
    sudo rm -rf /var/cache/apt/*
    sudo apt clean all
    sudo apt autoremove -y
}

#? Uninstall ZLUDA
#? uninstall_zluda() {
#?    sudo rm -rf $ZLUDA_PATH
#? }

# Install ROCm
install_rocm() {
    ROCM_VERSION="7.1"

    # Create the keyrings directory if it does not exist
    if [ ! -d /etc/apt/keyrings ]; then
        sudo mkdir --parents --mode=0755 /etc/apt/keyrings
    fi

    wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
        gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null

    # Register AMD GPU packages
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/$ROCM_VERSION/ubuntu noble main" \
    | sudo tee /etc/apt/sources.list.d/amdgpu.list

    # Register ROCm packages
    sudo tee /etc/apt/sources.list.d/rocm.list << EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/$ROCM_VERSION noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/$ROCM_VERSION/ubuntu noble main
EOF

    sudo tee /etc/apt/preferences.d/rocm-pin-600 << EOF
# Prefer AMD ROCm packages
Package: rocm* hip* rocminfo rocm-cmake amdgpu*
Pin: version *~24.04
Pin-Priority: 1001
EOF

    sudo apt update -y
    sudo apt install -y "linux-headers-$(uname -r)"
    sudo apt install -y amdgpu rocminfo rocm-cmake hipblas hipcc hipify-clang rocm-hip-runtime rocm-hip-runtime-dev 
}

#? Install ZLUDA
#? install_zluda() {
#?    cd /tmp
#?
#?    if [ -d "zluda" ]; then
#?        rm -rf "zluda"
#?    fi
#?
#?    if [ -f $ZLUDA_FILE ]; then
#?        rm -f $ZLUDA_FILE
#?    fi
#?
#?    wget $ZLUDA_URL || { echo "Failed to download ZLUDA from $ZLUDA_URL" >&2; exit 1; }
#?
#?    tar -xvzf $ZLUDA_FILE
#?
#?    sudo mv zluda $ZLUDA_PATH || { echo "Failed to move ZLUDA to $ZLUDA_PATH" >&2; exit 1; }
#?}

set_installation_path() {
    new_path=$(whiptail --title "Set Installation Path" --inputbox "Enter the installation path:" 10 60 "$installation_path" 3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$new_path" ]; then
        installation_path="$new_path"
        whiptail --title "Installation Path Updated" --msgbox "Installation path set to: $installation_path" 8 60
    fi
}

install_uv() {
    sudo apt install -y pipx
    pipx install uv --force
    pipx upgrade uv
    pipx ensurepath
    source ~/.bashrc
}

install(){
    command -v sudo >/dev/null || { echo "sudo not installed" >&2; exit 1; }
    sudo -n true 2>/dev/null || sudo -v || { echo "no sudo access" >&2; exit 1; }
    
    sudo adduser `whoami` video
    sudo adduser `whoami` render

    uninstall_rocm
    #? uninstall_zluda

    sudo apt install -y python3-dev python3-setuptools python3-wheel python3-tk
    sudo apt install -y nodejs
    sudo apt install -y ffmpeg
    sudo apt install -y cmake
    sudo apt install -y curl wget
    sudo apt install -y git git-lfs
    sudo apt install -y tar
    sudo apt install -y espeak

    nvm install 22

    prefer_noble
    install_rocm
    #? install_zluda

    if [ -f /etc/ld.so.conf.d/rocm.conf ]; then
        sudo rm /etc/ld.so.conf.d/rocm.conf
    fi

    sudo tee --append /etc/ld.so.conf.d/rocm.conf <<EOF
/opt/rocm/lib
/opt/rocm/lib64
EOF
    sudo ldconfig

    install_uv
}

# Main loop
while show_menu; do
    :
done