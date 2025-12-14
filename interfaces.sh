#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

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

    podman exec -t rocm bash -c "cd /AI && echo $FOLDER && if [ -d $FOLDER ]; then rm -rf $FOLDER; fi"
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
    REQUIREMENTS=$(tr '\n' ' ' < "$SCRIPT_DIR/requirements/$FOLDER.txt")

    podman exec -t rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install $REQUIREMENTS"
}

# RUN
basic_run(){
    local REPO=$1
    local COMMAND="$2"
    FOLDER=$(basename "$REPO")

    podman exec -t rocm bash -c "cat > /AI/$FOLDER/run.sh << RUNEOF
#!/bin/bash
podman exec -t rocm bash -c \"cd /AI/$FOLDER && source .venv/bin/activate && $COMMAND\"
RUNEOF
chmod +x /AI/$FOLDER/run.sh"
}

# PIP
basic_pip(){
    local REPO=$1
    local LINK=$2
    FOLDER=$(basename "$REPO")

    podman exec -t rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install $LINK"
}

# KoboldCPP
install_koboldcpp() {
    REPO="https://github.com/YellowRoseCx/koboldcpp-rocm"
    COMMIT="b4fa4f897f0c75a1e8d45e8247a14c6053548a61"
    COMMAND="uv run koboldcpp.py"
    FOLDER=$(basename "$REPO")

    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"
    podman exec -t rocm bash -c "cd /AI/$FOLDER && make LLAMA_HIPBLAS=1 -j\$(nproc)"
    basic_run "$REPO" "$COMMAND"
}

# llama.cpp
install_llama_cpp() {
    REPO="https://github.com/ggml-org/llama.cpp"
    COMMIT="9e6649ecf244a99749dacc28fc4f49f7d6ad6f60"
    COMMAND="./build/bin/llama-server -m model.gguf --host 0.0.0.0 --port 8080 --ctx-size 32768 --gpu-layers 1"
    FOLDER=$(basename "$REPO")
    
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    PODMAN='HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" cmake -S . -B build -DLLAMA_CURL=OFF -DGGML_HIP=ON -DAMDGPU_TARGETS=$GFX -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release -- -j$(($(nproc) - 1))'
    podman exec -t rocm bash -c "cd /AI/$FOLDER && $PODMAN"
    basic_run "$REPO" "$COMMAND"
}

# Text generation web UI
install_text_generation_web_ui() {
    REPO="https://github.com/oobabooga/text-generation-webui"
    COMMIT="bb004bacb1c8d2ee48a734a154c716ef27d9bc40"
    COMMAND="uv run server.py --api --listen --extensions sd_api_pictures send_pictures gallery"
    FOLDER=$(basename "$REPO")
    
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"

    # bitsandbytes
    basic_pip "$REPO" "git+https://github.com/ROCm/bitsandbytes.git@4fa939b3883ca17574333de2935beaabf71b2dba"

    # ExLlamaV2
    basic_pip "$REPO" "https://github.com/turboderp-org/exllamav2/releases/download/v0.3.2/exllamav2-0.3.2+rocm6.4.torch2.8.0-cp313-cp313-linux_x86_64.whl"

    # llama_cpp
    basic_pip "$REPO" "https://github.com/oobabooga/llama-cpp-binaries/releases/download/v0.69.0/llama_cpp_binaries-0.69.0+rocm6.4.4-py3-none-linux_x86_64.whl"

    basic_run "$REPO" "$COMMAND"
}
