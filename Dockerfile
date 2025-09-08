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

# Set user and home directory
ENV APP_USER=aiuser
ENV APP_HOME=/home/${APP_USER}

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

# Add video and render groups for GPU access
RUN groupadd --gid 109 gender && groupadd --gid 108 render

# Create the non-root application user and add to groups
RUN useradd --create-home --uid 1000 --gid gender --shell /bin/bash -G video,render ${APP_USER}

RUN apt-get update && \
    apt-get install -y pipx && \
    pipx install uv --force && \
    pipx upgrade uv && \
    pipx ensurepath

# Instala uv para o root e garante que está no PATH
RUN pipx install uv --force --include-in-path && \
    ln -s ~/.local/bin/uv /usr/local/bin/uv || true

ENV PATH=$PATH:/root/.local/bin

# Configure Debian 12 (Bookworm) fallback for compatibility
COPY install.sh /tmp/
RUN /bin/bash -c "source /tmp/install.sh && debian_fallback"

# Switch to the non-root user
USER ${APP_USER}
WORKDIR ${APP_HOME}

# Install uv using pipx
RUN pipx install uv --force && pipx ensurepath

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
WORKDIR ${APP_HOME}

# --- Data Persistence ---
# Define volumes to persist models, configs, outputs, and other user data.
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
    "${APP_HOME}/.ollama" \
]

# --- Networking ---
# Expose the default ports for the installed applications
EXPOSE 7860 8188 8000 8080 5000 11434

# --- Runtime ---
# Copy the entrypoint script to launch applications
COPY --chown=${APP_USER}:${APP_USER} entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Default command shows help message
CMD ["--help"]
