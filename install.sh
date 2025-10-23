
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

# ROCm
URL="https://repo.radeon.com/amdgpu-install/7.0.2/ubuntu/noble/amdgpu-install_7.0.2.70002-1_all.deb"
DEB_FILE=$(basename "$URL")

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
    sudo apt purge -y amdgpu-install

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

install_rocm() {

    cd /tmp

    if [ -f "$DEB_FILE" ]; then
        rm -f "$DEB_FILE"
    fi

    wget "$URL"

    sudo apt install -y ./$DEB_FILE

    sudo apt update -y
    sudo apt install -y "linux-headers-$(uname -r)"
    sudo apt install -y amdgpu-dkms rocm rocminfo rocm-utils rocm-cmake hipcc hipify-clang rocm-hip-runtime rocm-hip-runtime-dev
}

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

    sudo apt install -y python3-dev python3-setuptools python3-wheel
    sudo apt install -y nodejs npm
    sudo apt install -y ffmpeg
    sudo apt install -y cmake
    sudo apt install -y curl wget
    sudo apt install -y git git-lfs
    sudo apt install -y espeak

    install_rocm

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