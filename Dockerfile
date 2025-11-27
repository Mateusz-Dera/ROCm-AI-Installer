# Base Image: Debian Trixie as requested
FROM debian:trixie-20251117

# Set non-interactive frontend for package managers
ENV DEBIAN_FRONTEND=noninteractive

# --- Build-time Arguments ---
# GFX allows specifying the target AMD GPU architecture during build.
# Examples: "gfx1100" for RDNA3, "gfx1030" for RDNA2, "gfx906" for Vega
ARG GFX="gfx1100"
ARG GFX_VERSION="11.0.0"

# --- Environment Variables ---
# Set GPU environment variables for ROCm and PyTorch
ENV HSA_OVERRIDE_GFX_VERSION=${GFX_VERSION}
ENV PYTORCH_ROCM_ARCH=${GFX}
ENV GFX=${GFX}

# Define the main installation path
ENV AI_PATH=/AI
ENV PATH="${AI_PATH}/.local/bin:${PATH}"
ENV installation_path="${AI_PATH}"

# Backup
ENV SCRIPT_DIR=/AI
ENV source="$SCRIPT_DIR/backup.sh"

# Set user and home directory
ENV APP_USER=aiuser
ENV REQUIREMENTS_DIR="$SCRIPT_DIR/requirements"
ENV CUSTOM_FILES_DIR="$SCRIPT_DIR/custom_files"

# --- System Setup and Dependency Installation (as root) ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utilities
    git \
    sudo \
    curl \
    wget \
    gpg \
    # Build tools
    cmake \
    # Python and Node.js
    python3-dev \
    nodejs \
    npm \
    pipx \
    # Media
    ffmpeg \
    # ROCm dependencies
    libnuma-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y pipx && \
    pipx install uv --force && \
    pipx upgrade uv && \
    pipx ensurepath

RUN apt-get install -y build-essential

# Install uv as root and ensure it is in PATH
RUN pipx install uv --force --include-in-path && \
    ln -s ~/.local/bin/uv /usr/local/bin/uv || true

RUN ln -sf /home/${APP_USER}/.local/bin/uv /usr/local/bin/uv || true
ENV PATH="/home/${APP_USER}/.local/bin:${PATH}"

# Add video and render groups for GPU access
RUN groupadd --gid 109 aiuser && groupadd --gid 108 render

# Create the non-root application user and add to groups
RUN useradd --create-home --uid 1000 --gid aiuser --shell /bin/bash -G video,render ${APP_USER}
# Allow passwordless sudo
RUN echo "${APP_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/aiuser && chmod 0440 /etc/sudoers.d/aiuser

# Switch to the non-root user
USER ${APP_USER}
WORKDIR ${CUSTOM_FILES_DIR}

# Install uv using pipx
RUN pipx install uv --force && pipx ensurepath
RUN ln -sf /home/${APP_USER}/.local/bin/uv /usr/local/bin/uv || true
ENV PATH="/home/${APP_USER}/.local/bin:${PATH}"

# Copy installer scripts into the container
COPY --chown=${APP_USER}:${APP_USER} . ${AI_PATH}/

# As root, install system-wide components
USER root
COPY --chown=root:root interfaces.sh /tmp/
COPY --chown=root:root install.sh /tmp/
COPY --chown=root:root menu.sh /tmp/
COPY --chown=root:root backup.sh /tmp/

##############################################
# Please Select your first app before build
##############################################
ARG INSTALL_APP="install_partcrafter"
# install_comfyui
# install_text_generation_web_ui
# install_sillytavern
# install_llama_cpp
# install_koboldcpp
# install_ollama
# install_whisperspeech_web_ui
# install_ace_step
# install_f5_tts
# install_matcha_tts
# install_dia
# install_ims_toucan
# install_chatterbox
# install_partcrafter
##############################################

# Run the Interactive installer during build
RUN /bin/bash -c "source /tmp/install.sh && install"
ENV INSTALL_APP=${INSTALL_APP}
RUN bash -c "if [ -n \"$INSTALL_APP\" ]; then \
    echo 'Auto-installing $INSTALL_APP...' && \
    source /tmp/interfaces.sh && \
    $INSTALL_APP; \
    else \
    echo 'No INSTALL_APP specified. Skipping installation.'; \
    fi"

##############################################
# Please Select your Second app before build
##############################################
# ARG INSTALL_APP="install_dia"
# install_comfyui
# install_text_generation_web_ui
# install_sillytavern
# install_llama_cpp
# install_koboldcpp
# install_ollama
# install_whisperspeech_web_ui
# install_ace_step
# install_f5_tts
# install_matcha_tts
# install_dia
# install_ims_toucan
# install_chatterbox
# install_partcrafter
##############################################

# # Run the Interactive installer during build
# ENV INSTALL_APP=${INSTALL_APP}
# RUN bash -c "if [ -n \"$INSTALL_APP\" ]; then \
#     echo 'Auto-installing $INSTALL_APP...' && \
#     source /tmp/interfaces.sh && \
#     $INSTALL_APP; \
#     else \
#     echo 'No INSTALL_APP specified. Skipping installation.'; \
#     fi"

##############################################
# Please Select your third app before build
##############################################
# ARG INSTALL_APP="install_ollama"
# install_comfyui
# install_text_generation_web_ui
# install_sillytavern
# install_llama_cpp
# install_koboldcpp
# install_ollama
# install_whisperspeech_web_ui
# install_ace_step
# install_f5_tts
# install_matcha_tts
# install_dia
# install_ims_toucan
# install_chatterbox
# install_partcrafter
##############################################

# # Run the Interactive installer during build
# ENV INSTALL_APP=${INSTALL_APP}
# RUN bash -c "if [ -n \"$INSTALL_APP\" ]; then \
#     echo 'Auto-installing $INSTALL_APP...' && \
#     source /tmp/interfaces.sh && \
#     $INSTALL_APP; \
#     else \
#     echo 'No INSTALL_APP specified. Skipping installation.'; \
#     fi"
##############################################

# --- Networking ---
# Ports (ComfyUI, Gradio, APIs, etc.)
EXPOSE 5000 7860 7865 8000 8003 8080 8188 11434

# --- Runtime ---
CMD ["/bin/bash", "-c", "echo 'This image is designed to be used with the provided docker compose.yml. Please start a service, e.g., `docker compose up comfyui`'"]