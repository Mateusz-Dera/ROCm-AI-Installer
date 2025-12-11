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

FROM ubuntu:24.04

# Set environment variables to prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Define build argument for AI user (can be overridden during build)
ARG AI_USER=ai

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
    npm
    # && rm -rf /var/lib/apt/lists/*

# Download and install AMD GPU installer package for ROCm 7.1.1
RUN wget https://repo.radeon.com/amdgpu-install/7.1.1/ubuntu/noble/amdgpu-install_7.1.1.70101-1_all.deb \
    && apt-get update \
    && apt-get install -y ./amdgpu-install_7.1.1.70101-1_all.deb \
    && rm amdgpu-install_7.1.1.70101-1_all.deb

# Update package list with AMD repositories
RUN apt-get update

# AMDGPU
# RUN apt install -y "linux-headers-$(uname -r)"
RUN apt install -y amdgpu-dkms 

# ROCM
RUN apt-get install -y \
    rocm rocminfo rocm-cmake rocm-smi rocm-smi-lib rocm-hip-sdk rocm-hip-runtime rocm-hip-runtime-dev \
    hipblas hipcc hipify-clang hiprand hiprand-dev hipfft hipfft-dev hipsparse hipsparse-dev \
    hipcub hipcub-dev hipsolver hipsolver-dev hipsparselt hipsparselt-dev \
    amd-smi-lib \
    rocrand rocrand-dev rocfft rocfft-dev rocprim rocprim-dev rocthrust rocthrust-dev rocprofiler-sdk hsa-amd-aqlprofile \
    miopen-hip miopen-hip-dev
    # && rm -rf /var/lib/apt/lists/*

# Create render group if it doesn't exist (for GPU access)
RUN getent group render || groupadd -r render

# Create AI user with GPU access and no password
# Adding user to video and render groups for ROCm GPU access
# User can run sudo without password for system administration
RUN useradd -m -s /bin/bash ${AI_USER} && \
    usermod -a -G video,render,sudo ${AI_USER} && \
    echo "${AI_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Folder
RUN mkdir -p /home/${AI_USER}/AI
RUN chown -R ${AI_USER}:${AI_USER} /home/${AI_USER}
RUN chown -R ${AI_USER}:${AI_USER} /home/${AI_USER}/AI

# Set ROCm environment variables
ENV PATH="/opt/rocm/bin:/opt/rocm/opencl/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/rocm/lib:/opt/rocm/lib64:${LD_LIBRARY_PATH}"
ENV ROCM_PATH="/opt/rocm"

# Set working directory
WORKDIR /home/${AI_USER}

# Switch to AI user
USER ${AI_USER}

# Install uv via pipx and add to PATH
RUN pipx install uv --force && \
    pipx ensurepath --force

# Add pipx binaries to PATH for this user
ENV PATH="/home/${AI_USER}/.local/bin:${PATH}"

EXPOSE 5000 7860 7865 8000 8003 8080 8188 11434

# Default command to verify ROCm installation
CMD ["/bin/bash"]
