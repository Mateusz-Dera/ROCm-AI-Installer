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

# Set environment variables to prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Update and install basic dependencies
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
    pipx \
    cmake \
    make \
    ffmpeg \
    espeak \
    nodejs \
    npm \
    libsparsehash-dev \
    libxml2-16 \
    libopenmpi40 \
    libdw1 \
    g++ \
    build-essential \
    cargo \
    unzip \
    libgl1 \
    libglib2.0-0t64

    # && rm -rf /var/lib/apt/lists/*

# Add AMD ROCm repositories
RUN mkdir -p /etc/apt/keyrings && \
    wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | gpg --dearmor | tee /etc/apt/keyrings/rocm.gpg > /dev/null
RUN echo "deb [arch=amd64,i386 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/31.20/ubuntu noble main" \
        > /etc/apt/sources.list.d/amdgpu.list && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2.2 noble main" \
        > /etc/apt/sources.list.d/rocm.list && \
    printf 'Package: *\nPin: origin repo.radeon.com\nPin-Priority: 1001\n' \
        > /etc/apt/preferences.d/rocm-pin

RUN apt-get update

# ROCM
RUN apt-get install -y \
    rocm rocminfo rocm-cmake rocm-smi rocm-smi-lib rocm-hip-sdk rocm-hip-runtime rocm-hip-runtime-dev \
    hipblas hipcc hipify-clang hiprand hiprand-dev hipfft hipfft-dev hipsparse hipsparse-dev \
    hipcub hipcub-dev hipsolver hipsolver-dev hipsparselt hipsparselt-dev \
    amd-smi-lib \
    rocrand rocrand-dev rocfft rocfft-dev rocprim rocprim-dev rocthrust rocthrust-dev rocprofiler-sdk hsa-amd-aqlprofile \
    miopen-hip miopen-hip-dev

# libxml2 symlink: ROCm lld was built against libxml2.so.2 (Ubuntu 24.04 soname),
# Ubuntu 26.04 ships libxml2.so.16 — create compat symlink
RUN ln -sf /usr/lib/x86_64-linux-gnu/libxml2.so.16 /usr/lib/x86_64-linux-gnu/libxml2.so.2

# Vulkan
RUN apt-get install -y \
    libvulkan-dev vulkan-tools glslc spirv-headers

# Create render group if it doesn't exist (for GPU access)
RUN getent group render || groupadd -r render

# Remove default ubuntu user to avoid UID conflicts in rootless podman
RUN userdel -r ubuntu 2>/dev/null || true

# Create AI directory
# In rootless podman, root in container (UID 0) is mapped to host user
# Files created here will be owned by host user outside container
RUN mkdir -p /AI && \
    chmod 777 /AI

# Copy entrypoint script
COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/

# Set ROCm environment variables
ENV PATH="/opt/rocm/bin:/opt/rocm/opencl/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/rocm/lib:/opt/rocm/lib64:${LD_LIBRARY_PATH}"
ENV ROCM_PATH="/opt/rocm"
ENV ROCM_HOME="/opt/rocm"
ENV VLLM_TARGET_DEVICE="rocm"

# Set GPU and PyTorch environment variables
ENV HIP_VISIBLE_DEVICES=0
ENV TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1
ENV TORCH_BLAS_PREFER_HIPBLASLT=0
ENV FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE
ENV MIOPEN_LOG_LEVEL=3

# Set working directory
WORKDIR /AI

# Install uv for root user
# In rootless podman, this root user is mapped to host user
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install uv
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install 'huggingface_hub[cli]==1.12.0'

# Add uv to PATH
ENV PATH="/usr/local/bin:${PATH}"

# Set entrypoint to fix permissions on startup
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Default command
CMD ["/bin/bash"]
