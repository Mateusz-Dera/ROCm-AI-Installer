
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

# Version
version="8.4"

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
    # Create the keyrings directory if it does not exist
    if [ ! -d /etc/apt/keyrings ]; then
        sudo mkdir --parents --mode=0755 /etc/apt/keyrings
    fi

    #TODO
    # Add the ROCm repository
    #wget https://repo.radeon.com/rocm/rocm.gpg.key -O - |
    #gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null

    #TODO
    # Add the ROCm repository to the sources list
    # echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/6.4.3 jammy main" \
    # | sudo tee /etc/apt/sources.list.d/rocm.list

    echo "deb [arch=amd64 trusted=yes] https://repo.radeon.com/rocm/apt/6.4.3 jammy main" \
    | sudo tee /etc/apt/sources.list.d/rocm.list

    # Add the AMDGPU repository
    echo -e 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600' \
    | sudo tee /etc/apt/preferences.d/rocm-pin-600

    # Update the package list
    sudo apt update

    # Install the ROCm packages
    sudo apt install -y -t jammy rocm rocminfo rocm-utils rocm-cmake hipcc hipify-clang rocm-hip-runtime rocm-hip-runtime-dev
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

    sudo apt install -y python3-dev
    sudo apt install -y nodejs npm
    sudo apt install -y ffmpeg
    sudo apt install -y cmake
    sudo apt install -y curl
    sudo apt install -y git git-lfs

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