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

# GPU Variables
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export GFX=gfx1100

# Version
version="8.0"

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

source ./menu.sh
source ./interfaces.sh

# Installation path
set_installation_path() {
    # Prompt for installation path, using the default if the user leaves it blank

    new_installation_path=$(whiptail --inputbox "Enter the installation path (default: $default_installation_path):" 10 150 "$installation_path" --cancel-button "Back" 3>&1 1>&2 2>&3)
    status=$?

    if [ $status -ne 0 ]; then
        return 0
    fi

    # If the user leaves it blank, use the default
    new_installation_path=${new_installation_path:-$default_installation_path}

    # Remove trailing "/" if it exists
    new_installation_path=$(echo "$new_installation_path" | sed 's#/$##')

    # Update the installation path variable
    installation_path="$new_installation_path"
}

## INSTALLATION

# Remove old
remove_old() {
    sudo apt purge -y rocm*
    sudo apt purge -y hip*
    # sudo apt purge -y nvidia*

    if [ -d /opt/rocm* ]; then
        sudo rm -r /opt/rocm*
    fi

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

# MAGMA
magma(){
    set -eou pipefail

    # Use CUDA 11.8 as default if no parameter provided
    cuda_version=${1:-"11.8"}
    cuda_version_nodot=${cuda_version/./}

    # Check if we're in a virtual environment
    if [[ -z "${VIRTUAL_ENV:-}" ]]; then
        echo "Error: No virtual environment detected. Please activate your venv first."
        echo "Run: source /path/to/your/venv/bin/activate"
        exit 1
    fi

    # Use VIRTUAL_ENV as the base directory for installation
    venv_dir="${VIRTUAL_ENV}"
    MAGMA_VERSION="2.6.1"
    magma_archive="magma-cuda${cuda_version_nodot}-${MAGMA_VERSION}-1.tar.bz2"

    echo "Installing MAGMA (CUDA ${cuda_version}) to virtual environment: ${venv_dir}"

    (
        set -x
        tmp_dir=$(mktemp -d)
        pushd ${tmp_dir}
        curl -OLs https://ossci-linux.s3.us-east-1.amazonaws.com/${magma_archive}
        tar -xvf "${magma_archive}"
        
        # Create directories if they don't exist
        mkdir -p "${venv_dir}/include"
        mkdir -p "${venv_dir}/lib"
        
        # Move files to virtual environment
        mv include/* "${venv_dir}/include/"
        mv lib/* "${venv_dir}/lib/"
        popd
        rm -rf ${tmp_dir}
    )

    echo "MAGMA installation completed successfully!"
    echo "Headers installed to: ${venv_dir}/include"
    echo "Libraries installed to: ${venv_dir}/lib"
}

# ZLUDA
install_zluda(){
   cd $installation_path
    if [ -d ZLUDA ]; then
        rm -rf ZLUDA
    fi
    git clone https://github.com/lshqqytiger/ZLUDA
    cd ZLUDA

    git checkout 5e717459179dc272b7d7d23391f0fad66c7459cf
    git submodule update --init --recursive

    cargo xtask --release
    
    uv venv --python 3.10
    source .venv/bin/activate
    export CMAKE_PREFIX_PATH="/home/mdera/AI/ZLUDA/.venv"
    export TORCH_CUDA_ARCH_LIST="6.1+PTX"
    export CUDAARCHS=61
    export CMAKE_CUDA_ARCHITECTURES=61
    export USE_SYSTEM_NCCL=1
    export USE_NCCL=0
    export USE_EXPERIMENTAL_CUDNN_V8_API=OFF
    export DISABLE_ADDMM_CUDA_LT=1
    export USE_ROCM=OFF
    export LD_LIBRARY_PATH="/home/mdera/AI/ZLUDA/target/release"
    # export CMAKE_ARGS="-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    
    git clone https://github.com/pytorch/pytorch
    cd pytorch
    git checkout ee1b6804381c57161c477caa380a840a84167676

    git submodule sync
    git submodule update --init --recursive
    uv pip install -U pip
    uv pip install setuptools wheel
    uv pip install cmake ninja
    uv pip install mkl-static mkl-include
    uv pip install -r requirements.txt
    magma

    CMAKE_POLICY_VERSION_MINIMUM=3.5 USE_CUDA=1 python3 setup.py develop
}

# SCALE
# scale() {
#     sudo rm -rf /opt/scale

#     cd /tmp

#     if [ -f scale-free-1.3.1-amd64.tar.xz ]; then
#         rm scale-free-1.3.1-amd64.tar.xz
#     fi
#     wget https://pkgs.scale-lang.com/tar/scale-free-1.3.1-amd64.tar.xz

#     if [ -d scale-free-1.3.1-amd64 ]; then
#         rm -rf scale-free-1.3.1-Linux 
#     fi
#     tar -xf scale-free-1.3.1-amd64.tar.xz

#     sudo mv scale-free-1.3.1-Linux  /opt/scale

#     sudo chown -R root:root /opt/scale
#     sudo find /opt/scale -type d -exec chmod 755 {} \;
#     sudo find /opt/scale -type f -exec chmod 755 {} \;

#     source /opt/scale/bin/scaleenv $GFX
#     export SCALE_DIR="/opt/scale"
#     export LD_LIBRARY_PATH="$SCALE_DIR/lib"
#     export USE_ROCM=OFF
#     export CUDAARCHS=61
#     export CMAKE_CUDA_ARCHITEC
#     export USE_SYSTEM_NCCL=1
#     export USE_NCCL=0
#     export USE_EXPERIMENTAL_CUDNN_V8_API=OFF
#     export DISABLE_ADDMM_CUDA_LT=1

#     cd $installation_path
#     git clone --recursive https://github.com/pytorch/pytorch
#     cd pytorch
#     git submodule sync
#     git submodule update --init --recursive
#     pip install -U pip
#     pip install setuptools wheel
#     pip install cmake ninja
#     pip install -r requirements.txt
#     export CMAKE_ARGS="-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON"
#     python3 setup.py develop

# }

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
    echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/6.4.1/ubuntu noble main' \
    | sudo tee /etc/apt/sources.list.d/amdgpu.list
    sudo apt update -y
    sudo apt install -y amdgpu-dkms

    # ROCm
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/6.4.1 noble main" \
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
    sudo apt install -y python3-openssl
    sudo apt install -y espeak-ng
    sudo apt install -y libomp-dev
    sudo apt install -y libssl-dev build-essential g++ libboost-all-dev libsparsehash-dev git-core perl
    sudo apt install -y cmake
    sudo cp /usr/lib/x86_64-linux-gnu/libomp5.so /usr/lib/x86_64-linux-gnu/libomp.so

    sudo snap install node --classic
  
    sudo snap install astral-uv --classic

    sudo apt purge -y cargo rustc rustup
    sudo snap install rustup --classic
    rustup default stable
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

    # Remove venv if exist
    if [ -d ".venv" ]; then
        rm -rf ".venv"
    fi

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

## MAIN

# Main loop
while show_menu; do
    :
done