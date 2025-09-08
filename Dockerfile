# Base Image: Debian Trixie as requested
FROM debian:trixie-20250811

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

# Instala uv para o root e garante que está no PATH
RUN pipx install uv --force --include-in-path && \
    ln -s ~/.local/bin/uv /usr/local/bin/uv || true

RUN ln -sf /home/${APP_USER}/.local/bin/uv /usr/local/bin/uv || true
ENV PATH="/home/${APP_USER}/.local/bin:${PATH}"

# Configure Debian 12 (Bookworm) fallback for compatibility
COPY install.sh /tmp/
RUN /bin/bash -c "source /tmp/install.sh && debian_fallback"

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
COPY --chown=${APP_USER}:${APP_USER} . ${AI_PATH}/installer/

# As root, install system-wide components
USER root
COPY --chown=root:root interfaces.sh /tmp/
COPY --chown=root:root install.sh /tmp/
COPY --chown=root:root menu.sh /tmp/
COPY --chown=root:root backup.sh /tmp/
RUN /bin/bash -c "source /tmp/install.sh && install"
RUN /bin/bash -c "source /tmp/interfaces.sh && install_triposg"

# Switch back to the application user
USER ${APP_USER}
WORKDIR ${CUSTOM_FILES_DIR}

# --- Data Persistence ---
# Define volumes to persist models, configs, outputs, and other user data.
# Note: These are now managed in the docker-compose.yml for better host mapping.
VOLUME [ \
    "${AI_PATH}/text-generation-webui/models", \
    "${AI_PATH}/text-generation-webui/loras", \
    "${AI_PATH}/text-generation-webui/presets", \
    "${AI_PATH}/text-generation-webui/characters", \
    "${AI_PATH}/text-generation-webui/logs", \
    "${AI_PATH}/ComfyUI/models", \
    "${AI_PATH}/ComfyUI/input", \
    "${AI_PATH}/ComfyUI/output", \
    "${AI_PATH}/ComfyUI/custom_nodes", \
    "${AI_PATH}/SillyTavern/data", \
    "${AI_PATH}/llama.cpp/models", \
    "${CUSTOM_FILES_DIR}/.ollama" \
]

# --- Networking ---
# Expose the default ports for the installed applications
EXPOSE 7860 8188 8000 8080 5000 11434

# --- Runtime ---
# The container is designed to be run via docker-compose, with each service specifying its own command.
# See the docker-compose.yml file for available services.
CMD ["/bin/bash", "-c", "echo 'This image is designed to be used with the provided docker-compose.yml. Please start a service, e.g., `docker-compose up comfyui`'"]
