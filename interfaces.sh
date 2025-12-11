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

    podman exec -u $AI_USERNAME -t rocm bash -c "cd $DEFAULT_AI_DIR && [ -d $FOLDER ] && rm -rf $FOLDER;"
    podman exec -u $AI_USERNAME -t rocm bash -c "cd $DEFAULT_AI_DIR && git clone $REPO && cd $FOLDER && git checkout $COMMIT"
}

# VENV
basic_venv(){
    local REPO=$1
    local PYTHON=${2:-3.13}
    FOLDER=$(basename "$REPO")
    podman exec -u $AI_USERNAME -t rocm bash -c "cd $DEFAULT_AI_DIR/$FOLDER && uv venv --python $PYTHON"
}

# REQUREMENTS
basic_requirements(){
    local REPO=$1
    FOLDER=$(basename "$REPO")
    # REQUREMENTS=""
    # podman exec -t rocm bash -c "cd $DEFAULT_AI_DIR/$FOLDER && uv venv --python $PYTHON"
}

# KoboldCPP
install_koboldcpp() {
    $REPO="https://github.com/YellowRoseCx/koboldcpp-rocm"
    $COMMIT="b4fa4f897f0c75a1e8d45e8247a14c6053548a61"

    basic_git $REPO $COMMIT
    basic_venv $REPO
    
    # uv_base "https://github.com/YellowRoseCx/koboldcpp-rocm" "ee3f39fc7ce391d02eda407f828098f70488a6b7" "uv run koboldcpp.py" "3.13" "rocm6.4" "0"
    # make LLAMA_HIPBLAS=1 -j$(($(nproc) - 1))
}