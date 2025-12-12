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

# GIT
basic_git(){
    local REPO=$1
    local COMMIT=$2
    FOLDER=$(basename "$REPO")

    podman exec -t rocm bash -c "cd /AI && [ -d $FOLDER ] && rm -rf $FOLDER"
    podman exec -t rocm bash -c "cd /AI && git clone $REPO && cd $FOLDER && git checkout $COMMIT"
}

# VENV
basic_venv(){
    local REPO=$1
    local PYTHON=${2:-3.13}
    FOLDER=$(basename "$REPO")

    podman exec -t rocm bash -c "cd /AI/$FOLDER && uv venv --python $PYTHON"
}

# REQUIREMENTS
basic_requirements(){
    local REPO=$1
    FOLDER=$(basename "$REPO")
    REQUIREMENTS="$(< $SCRIPT_DIR/requirements/$FOLDER.txt)"

    podman exec -t rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install $REQUIREMENTS"
}

# RUN
basic_run(){
    local REPO=$1
    local COMMAND=$2
    FOLDER=$(basename "$REPO")
    EXP='SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\nsource $SCRIPT_DIR/.venv/bin/activate\nexport HIP_VISIBLE_DEVICES=0\nexport PYTORCH_ROCM_ARCH=$GFX\nexport TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1\nexport TORCH_BLAS_PREFER_HIPBLASLT=0\nexport FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"\nexport MIOPEN_LOG_LEVEL=3\n'

    podman exec -t rocm bash -c "cd /AI/$FOLDER && echo -e $EXP > ./run.sh && echo -e $COMMAND >> ./run.sh && chmod +x ./run.sh"
}

# KoboldCPP
install_koboldcpp() {
    REPO="https://github.com/YellowRoseCx/koboldcpp-rocm"
    COMMIT="b4fa4f897f0c75a1e8d45e8247a14c6053548a61"
    COMMAND="uv run koboldcpp.py"
    FOLDER=$(basename "$REPO")

    basic_git $REPO $COMMIT
    basic_venv $REPO
    basic_requirements $REPO
    podman exec -t rocm bash -c "cd /AI/$FOLDER && make LLAMA_HIPBLAS=1 -j$(($(nproc) - 1))"
    basic_run $REPO $COMMAND
}