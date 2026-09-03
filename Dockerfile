# ROCM-AI-Installer
# Copyright © 2023-2026 Mateusz Dera

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

FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    nano \
    wget \
    curl \
    tar \
    git \
    git-lfs \
    gnupg2 \
    ca-certificates \
    sudo \
    python3-dev \
    python3-setuptools \
    python3-wheel \
    python3-tk \
    rsync \
    pipx \
    cmake \
    make \
    ffmpeg \
    espeak \
    nodejs \
    npm \
    libsparsehash-dev \
    libnuma-dev \
    libxml2-16 \
    libopenmpi40 \
    libdw1 \
    g++ \
    build-essential \
    cargo \
    unzip \
    libgl1 \
    libglib2.0-0t64

RUN mkdir -p /etc/apt/keyrings && \
    wget https://stable.repo.amd.com/rocm/gpg/packages.gpg -O - | gpg --dearmor | tee /etc/apt/keyrings/amdrocm.gpg > /dev/null
RUN echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/amdrocm.gpg] https://stable.repo.amd.com/rocm/core/packages/ubuntu2604 stable main" \
        > /etc/apt/sources.list.d/rocm.list

RUN apt-get update

ARG TARGET_GFX_ALL=gfx1100

RUN set -eu; \
    pkgs=""; \
    for arch in $(echo "$TARGET_GFX_ALL" | tr ';' ' '); do \
        pkgs="$pkgs amdrocm10.0-$arch amdrocm-core-dev10.0-$arch"; \
    done; \
    echo "ROCm packages:$pkgs"; \
    apt-get install -y $pkgs

RUN for d in bin lib include share libexec; do \
        [ -d "/opt/rocm/core-10.0/$d" ] && ln -sfn "core-10.0/$d" "/opt/rocm/$d"; \
    done; true

# Vulkan
RUN apt-get install -y \
    libvulkan-dev vulkan-tools glslc spirv-headers

RUN apt-get install -y \
    libgl1-mesa-dev libglu1-mesa-dev \
    libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev

RUN getent group render || groupadd -r render

RUN userdel -r ubuntu 2>/dev/null || true

RUN mkdir -p /AI && \
    chmod 777 /AI

COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/

ENV PATH="/opt/rocm/bin:/opt/rocm/opencl/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/rocm/lib:/opt/rocm/lib64:${LD_LIBRARY_PATH}"
ENV ROCM_PATH="/opt/rocm"
ENV ROCM_HOME="/opt/rocm"
ENV VLLM_TARGET_DEVICE="rocm"

ENV TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1
ENV TORCH_BLAS_PREFER_HIPBLASLT=0
ENV FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE
ENV MIOPEN_LOG_LEVEL=3
ENV HF_HUB_DISABLE_UPDATE_CHECK=1

WORKDIR /AI

RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install uv
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install 'huggingface_hub[cli]==1.29.0' && \
    PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx inject huggingface-hub click

ENV PATH="/usr/local/bin:${PATH}"

# Every interpreter the installers ask for, baked into the image. Without this
# uv downloads them into the container filesystem on first use, and recreating
# the container leaves every venv pointing at an interpreter that no longer
# exists - the packages under /AI survive, the interpreter does not.
ENV UV_PYTHON_INSTALL_DIR="/root/.local/share/uv/python"
ENV UV_PYTHON_PREFERENCE="only-managed"
RUN uv python install 3.11 3.12 3.13 3.14

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

CMD ["/bin/bash"]
