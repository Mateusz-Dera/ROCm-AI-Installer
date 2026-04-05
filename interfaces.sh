#!/bin/bash

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

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# CONTAINER
basic_container(){
    # Check if rocm container exists
    if ! podman ps -a --format "{{.Names}}" | grep -q "^rocm$"; then
        echo "Error: Container 'rocm' does not exist."
        echo "Please create the container first using option '2. Create a container' from the main menu."
        read -p "Press Enter to continue..."
        return 1
    fi

    # Check if rocm container is running
    if ! podman ps --format "{{.Names}}" | grep -q "^rocm$"; then
        echo "Container rocm is not running. Starting..."
        podman start rocm
    fi
}

# GIT
basic_git(){
    local REPO=$1
    local COMMIT=$2
    local SUBFOLDER=${3:-/}
    local FOLDER=$(basename "$REPO")

    podman exec -t rocm bash -c "cd /AI$SUBFOLDER && echo $FOLDER && if [ -d $FOLDER ]; then rm -rf $FOLDER; fi"
    podman exec -it rocm bash -c "cd /AI$SUBFOLDER && git clone $REPO $FOLDER && cd $FOLDER && git checkout $COMMIT"
}

# VENV
basic_venv(){
    local REPO=$1
    local PYTHON=${2:-3.13}
    local FOLDER=${3:-$(basename "$REPO")}

    podman exec -it rocm bash -c "cd /AI/$FOLDER && uv venv --python $PYTHON"
}

# REQUIREMENTS
basic_requirements(){
    local REPO=$1
    local FOLDER=${2:-$(basename "$REPO")}
    local BASENAME=$(basename "$REPO")
    REQUIREMENTS=$(tr '\n' ' ' < "$SCRIPT_DIR/requirements/$BASENAME.txt")

    podman cp "$SCRIPT_DIR/uv.toml" "rocm:/AI/$FOLDER/uv.toml"
    podman cp "$SCRIPT_DIR/requirements/$BASENAME.txt" "rocm:/AI/$FOLDER/requirements.txt"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install --override requirements.txt $REQUIREMENTS"
}

# RUN
basic_run(){
    local REPO=$1
    local COMMAND="$2"
    local VENV=${3:-"&& source .venv/bin/activate &&"}
    local FOLDER=${4:-$(basename "$REPO")}

    podman exec -t rocm bash -c "cat > /AI/$FOLDER/run.sh << RUNEOF
#!/bin/bash
# Check if rocm container exists
if ! podman ps -a --format \"{{.Names}}\" | grep -q \"^rocm\\\$\"; then
    echo \"Error: Container 'rocm' does not exist.\"
    echo \"Please create the container first.\"
    exit 1
fi

# Check if rocm container is running
if ! podman ps --format \"{{.Names}}\" | grep -q \"^rocm\\\$\"; then
    echo \"Container rocm is not running. Starting...\"
    podman start rocm
fi
podman exec -it rocm bash -c \"cd /AI/$FOLDER $VENV $COMMAND\"
RUNEOF
chmod +x /AI/$FOLDER/run.sh"
}

# PIP
basic_pip(){
    local REPO=$1
    local LINK=$2
    local FOLDER=${3:-$(basename "$REPO")}

    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install $LINK"
}

# KoboldCPP
install_koboldcpp() {
    REPO="https://github.com/YellowRoseCx/koboldcpp-rocm"
    COMMIT="64d9d01c57cb4d0c58c530bc5fc053196da566fa"
    COMMAND="DISPLAY=\\\$DISPLAY uv run koboldcpp.py"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && make LLAMA_HIPBLAS=1 -j\$(nproc)"
    basic_run "$REPO" "$COMMAND"
}

# TabbyAPI
install_tabbyapi() {
    REPO="https://github.com/theroyallab/tabbyAPI"
    COMMIT="41511f56c65ff0d5d7d7fca2adc07a0b0a7a508a"
    EXLLAMA_REPO="https://github.com/turboderp-org/exllamav2"
    EXLLAMA_COMMIT="6a2d8311408aa23af34e8ec32e28085ea68dada7"
    COMMAND="python main.py"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"

    # Install tabbyAPI core deps from pyproject.toml (without exllamav2 extras)
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install -e . --override requirements.txt"

    # Clone and build exllamav2 from source for ROCm
    podman exec -it rocm bash -c "cd /AI/$FOLDER && git clone $EXLLAMA_REPO && cd exllamav2 && git checkout $EXLLAMA_COMMIT"
    # Patch: warpSize is a runtime variable in HIP, unusable as __shared__ array size.
    # For gfx10xx/gfx11xx (RDNA) wave32 mode, warpSize == 32 == CUDA constant.
    podman exec -it rocm bash -c "
      BASE=/AI/$FOLDER/exllamav2/exllamav2/exllamav2_ext
      for f in \$BASE/cuda/layer_norm.cu \$BASE/cuda/rms_norm.cu; do
        sed -i 's|#define NUM_WARPS (1024 / warpSize)|#define NUM_WARPS 32|' \"\$f\"
        sed -i 's|#define WARP_SIZE (warpSize)|#define WARP_SIZE 32|' \"\$f\"
      done
    "
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install ./exllamav2 --no-build-isolation --override requirements.txt"

    podman exec -t rocm bash -c "mkdir -p /AI/$FOLDER/models/example-model"

    podman exec -t rocm bash -c "cat > /AI/$FOLDER/config.yml << 'EOF'
network:
  host: 0.0.0.0
  port: 5000

model:
  model_dir: models
  model_name: example-model
  max_seq_len: -1
EOF"

    basic_run "$REPO" "$COMMAND"
}

# llama.cpp
install_llama_cpp() {
    REPO="https://github.com/ggml-org/llama.cpp"
    COMMIT="c08d28d08871715fd68accffaeeb76ddcaede658"
    COMMAND="./build/bin/llama-server -m model.gguf --host 0.0.0.0 --port 8080 --ctx-size 32768 --gpu-layers 31"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    PODMAN='HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" cmake -S . -B build -DLLAMA_CURL=OFF -DGGML_HIP=ON -DAMDGPU_TARGETS=$GFX -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release -- -j$(($(nproc) - 1))'
    podman exec -it rocm bash -c "cd /AI/$FOLDER && $PODMAN"
    basic_run "$REPO" "$COMMAND" "&&"
}

# llama.cpp Vulkan
install_llama_cpp_vulkan() {
    REPO="https://github.com/ggml-org/llama.cpp"
    COMMIT="c08d28d08871715fd68accffaeeb76ddcaede658"
    FOLDER="llama.cpp-vulkan"
    COMMAND="./build/bin/llama-server -m model.gguf --host 0.0.0.0 --port 8080 --ctx-size 32768 --gpu-layers 31"

    basic_container
    podman exec -it rocm bash -c "apt-get install -y libvulkan-dev vulkan-tools glslc"
    podman exec -t rocm bash -c "cd /AI && if [ -d $FOLDER ]; then rm -rf $FOLDER; fi"
    podman exec -it rocm bash -c "cd /AI && git clone $REPO $FOLDER && cd $FOLDER && git checkout $COMMIT"
    PODMAN='cmake -S . -B build -DLLAMA_CURL=OFF -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release -- -j$(($(nproc) - 1))'
    podman exec -it rocm bash -c "cd /AI/$FOLDER && $PODMAN"
    basic_run "$REPO" "$COMMAND" "&&" "$FOLDER"
}

# SillyTavern
install_sillytavern(){
    REPO="https://github.com/SillyTavern/SillyTavern"
    COMMIT="004f1336e6e59d476c1043f1dc94c92d028ac5d0"
    COMMAND="bash start.sh"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_run "$REPO" "$COMMAND" "&&"

    podman exec -t rocm bash -c "cd $FOLDER/default && sed -i 's/listen: false/listen: true/' config.yaml"
    podman exec -t rocm bash -c "cd $FOLDER/default && sed -i 's/whitelistMode: true/whitelistMode: false/' config.yaml"
    podman exec -t rocm bash -c "cd $FOLDER/default && sed -i 's/basicAuthMode: false/basicAuthMode: true/' config.yaml"
}

# SillyTavern WhisperSpeech web UI
install_sillytavern_whisperspeech_web_ui() {
    REPO="https://github.com/Mateusz-Dera/whisperspeech-webui"
    COMMIT="5b23874177548f17690385faeae6c7e6dd9b3ba4"

    basic_container

    # Check if SillyTavern is installed
    if ! podman exec -t rocm bash -c "[ -d /AI/SillyTavern ]"; then
        echo "SillyTavern is not installed. Please install SillyTavern first."
        return 1
    fi

    # Install WhisperSpeech web UI extension
    podman exec -it rocm bash -c "cd /AI/SillyTavern/public/scripts/extensions/third-party && \
        if [ -d whisperspeech-webui ]; then rm -rf whisperspeech-webui; fi && \
        git clone $REPO && \
        mv ./whisperspeech-webui ./whisperspeech-webui-temp && \
        cd whisperspeech-webui-temp && \
        git checkout $COMMIT && \
        mv ./whisperspeech-webui ../ && \
        cd .. && \
        rm -rf whisperspeech-webui-temp"
}

# Download
comfy_download() {
    echo "$2/resolve/$3/$4 $1"
    podman exec -it rocm bash -c "wget -P $1 $2/resolve/$3/$4"
}

# ComfyUI
install_comfyui() {
    REPO="https://github.com/comfyanonymous/ComfyUI"
    COMMIT="caa43d2395a69e93e52fe903da515fb2adbbb677"
    TUNABLEOP=""
    #if [[ "$GFX_VERSION" == gfx110* ]]; then
    #    TUNABLEOP="PYTORCH_TUNABLEOP_ENABLED=1 PYTORCH_TUNABLEOP_TUNING=1"
    #fi
    COMMAND="PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512 TORCH_BLAS_PREFER_HIPBLASLT=1 $TUNABLEOP uv run main.py --listen 0.0.0.0 --enable-manager --normalvram --preview-method auto --dont-upcast-attention --bf16-vae --use-pytorch-cross-attention --reserve-vram 2.0"
    FOLDER=$(basename "$REPO")
    ADDONS="$@"

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"

    basic_run "$REPO" "$COMMAND"

    # Extensions
    podman exec -it rocm bash -c "cd /AI/$FOLDER/custom_nodes && git clone https://github.com/city96/ComfyUI-GGUF && cd ComfyUI-GGUF && git checkout 6ea2651e7df66d7585f6ffee804b20e92fb38b8a"

    # Qwen-Image (shared text encoder + vae for Qwen models)
    if [[ "$ADDONS" == *"1"* ]] || [[ "$ADDONS" == *"2"* ]]; then
        comfy_download "$FOLDER/models/text_encoders" "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI" "c232bcb51c1523899c62d6dcaa960b2627668de5" "split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"
        comfy_download "$FOLDER/models/vae" "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI" "c232bcb51c1523899c62d6dcaa960b2627668de5" "split_files/vae/qwen_image_vae.safetensors"
    fi

    # 1 - Qwen-Image-2512
    if [[ "$ADDONS" == *"1"* ]]; then
        comfy_download "$FOLDER/models/unet/" "https://huggingface.co/unsloth/Qwen-Image-2512-GGUF" "1626d7531f84b4d2ea1cd6d2e69f41ec027dd354" "qwen-image-2512-Q5_0.gguf"
        comfy_download "$FOLDER/models/loras" "https://huggingface.co/Wuli-art/Qwen-Image-2512-Turbo-LoRA-2-Steps" "85afdc701a730b8866d9aa7c7a2eb5bf019b8c00" "Wuli-Qwen-Image-2512-Turbo-LoRA-2steps-V1.0-bf16.safetensors"
    fi

    # 2 - Qwen-Image-2511-Edit
    if [[ "$ADDONS" == *"2"* ]]; then
        comfy_download "$FOLDER/models/unet/" "https://huggingface.co/unsloth/Qwen-Image-Edit-2511-GGUF" "0d33d9692b4b26212297240d87b0d4719aa4fd06" "qwen-image-edit-2511-Q5_0.gguf"
        comfy_download "$FOLDER/models/loras/" "https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning" "d74eba145674fd7e31b949324e148e21e7118abd" "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors"
    fi

    # 3 - Z-Image-Turbo
    if [[ "$ADDONS" == *"3"* ]]; then
        comfy_download "$FOLDER/models/diffusion_models/" "https://huggingface.co/Comfy-Org/z_image_turbo" "2f862278568d3f0a83167a16e5f11094da6dee72" "split_files/diffusion_models/z_image_turbo_bf16.safetensors"
        comfy_download "$FOLDER/models/text_encoders/" "https://huggingface.co/Comfy-Org/z_image_turbo" "2f862278568d3f0a83167a16e5f11094da6dee72" "split_files/text_encoders/qwen_3_4b.safetensors"
        comfy_download "$FOLDER/models/vae/" "https://huggingface.co/Comfy-Org/z_image_turbo" "2f862278568d3f0a83167a16e5f11094da6dee72" "split_files/vae/ae.safetensors"
    fi

    # 4 - Wan 2.2 TI2V 5B
    if [[ "$ADDONS" == *"4"* ]]; then
        WAN_REPO="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged"
        WAN_COMMIT="f97505f0d38bea4897c970db66cb5f97f73676de"
        comfy_download "$FOLDER/models/text_encoders/" "$WAN_REPO" "$WAN_COMMIT" "split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
        comfy_download "$FOLDER/models/vae/" "$WAN_REPO" "$WAN_COMMIT" "split_files/vae/wan_2.1_vae.safetensors"
        comfy_download "$FOLDER/models/vae/" "$WAN_REPO" "$WAN_COMMIT" "split_files/vae/wan2.2_vae.safetensors"
        comfy_download "$FOLDER/models/diffusion_models/" "$WAN_REPO" "$WAN_COMMIT" "split_files/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors"
    fi
}

# ACE-Step
install_ace_step() {
    REPO="https://github.com/ace-step/ACE-Step"
    COMMIT="6ae0852b1388de6dc0cca26b31a86d711f723cb3"
    COMMAND="MIOPEN_FIND_MODE=3 PYTORCH_TUNABLEOP_ENABLED=1 uv run acestep --checkpoint_path ./checkpoints --server_name 0.0.0.0 --bf16 True"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"

    # Modify requirements.txt from repo (used by pip install -e .)
    podman exec -t rocm bash -c "cd /AI/$FOLDER && \
        sed -i 's/spacy==3\.8\.4/spacy/g' requirements.txt && \
        sed -i 's/datasets==3\.4\.1/datasets/g' requirements.txt && \
        sed -i 's/matplotlib==3\.10\.1/matplotlib/g' requirements.txt && \
        sed -i 's/transformers==4\.50\.0/transformers/g' requirements.txt"

    basic_requirements "$REPO"

    # Install package in editable mode
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install -e ."

    # Fix Gradio 6.x compatibility (show_download_button removed)
    # Fix port binding (use None default so Gradio auto-finds free port)
    podman exec -t rocm bash -c "cd /AI/$FOLDER && \
        sed -i 's/, show_download_button=True//g' acestep/ui/components.py && \
        sed -i '/show_download_button=True,/d' acestep/ui/components.py && \
        sed -i 's/\"--port\", type=int, default=7865/\"--port\", type=int, default=None/' acestep/gui.py"

    # Apply ROCm patches for pipeline
    podman cp "$SCRIPT_DIR/custom_files/ace-step/patch_rocm.py" "rocm:/AI/$FOLDER/patch_rocm.py"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && python patch_rocm.py"

    basic_run "$REPO" "$COMMAND"
}

# HeartMuLa
install_heartmula() {
    REPO="https://github.com/HeartMuLa/heartlib"
    COMMIT="adabcf5791926efd1a6c34b22cccd3f87d643c13"
    COMMAND="python webui.py --listen"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO" "3.12"

    # Copy custom webui
    podman cp "$SCRIPT_DIR/custom_files/heartlib/webui.py" "rocm:/AI/$FOLDER/webui.py"

    basic_requirements "$REPO"

    # Install package in editable mode
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install -e . --no-deps"

    # Download model checkpoints
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        hf download --local-dir './ckpt/HeartMuLa-oss-3B' 'HeartMuLa/HeartMuLa-RL-oss-3B-20260123' && \
        hf download --local-dir './ckpt/HeartCodec-oss' 'HeartMuLa/HeartCodec-oss-20260123' && \
        hf download --local-dir './ckpt' 'HeartMuLa/HeartMuLaGen' tokenizer.json gen_config.json"

    # Apply fixes for torchtune compatibility (rope_init and setup_caches)
    podman cp "$SCRIPT_DIR/custom_files/heartlib/patch_heartmula.py" "rocm:/AI/$FOLDER/patch_heartmula.py"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        python patch_heartmula.py src/heartlib/heartmula/modeling_heartmula.py"

    # Fix ignore_mismatched_sizes for HeartCodec
    podman exec -t rocm bash -c "cd /AI/$FOLDER && \
        sed -i 's/dtype=self.codec_dtype,\$/dtype=self.codec_dtype, ignore_mismatched_sizes=True,/g' src/heartlib/pipelines/music_generation.py"

    # Fix audio save using soundfile instead of torchaudio
    podman exec -t rocm bash -c "cd /AI/$FOLDER && \
        sed -i 's/torchaudio.save(save_path, wav.to(torch.float32).cpu(), 48000)/import soundfile as sf; wav_numpy = wav.to(torch.float32).cpu().numpy(); wav_numpy = wav_numpy.T if wav_numpy.ndim == 2 else wav_numpy; sf.write(save_path, wav_numpy, 48000)/g' src/heartlib/pipelines/music_generation.py"

    basic_run "$REPO" "$COMMAND"
}

# WhisperSpeech web UI
install_whisperspeech_web_ui(){
    REPO="https://github.com/Mateusz-Dera/whisperspeech-webui"
    COMMIT="5b23874177548f17690385faeae6c7e6dd9b3ba4"
    COMMAND="uv run --extra rocm webui.py --listen --api"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"

    # Install dependencies with ROCm support using uv sync
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv sync --extra rocm"

    basic_run "$REPO" "$COMMAND"
}

# F5-TTS
install_f5_tts(){
    REPO="https://github.com/SWivid/F5-TTS"
    COMMIT="54c50eb8f655590ff6d7ad64aa065e61946621be"
    COMMAND="f5-tts_infer-gradio --host 0.0.0.0"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"

    # Initialize git submodules
    podman exec -it rocm bash -c "cd /AI/$FOLDER && git submodule update --init --recursive"

    basic_requirements "$REPO"

    # Install package in editable mode
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install -e ."

    basic_run "$REPO" "$COMMAND"
}

# Soprano
install_soprano(){
    REPO="https://github.com/Mateusz-Dera/soprano-rocm"
    COMMIT="e4b3dd66641cc22c8f97f167ad1bfd75e04292e5"
    COMMAND="TORCH_BLAS_PREFER_HIPBLASLT=1 soprano-webui"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"

    basic_requirements "$REPO"

    basic_pip "$REPO" "/opt/rocm/share/amd_smi"

    podman exec -it rocm bash -c "cd /AI/$FOLDER && git clone https://github.com/vllm-project/vllm"
    podman exec -it rocm bash -c "cd /AI/$FOLDER/vllm && git checkout 37c9859fab60bbc346be20a662387479eb0760de"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && cd ./vllm && TORCH_BLAS_PREFER_HIPBLASLT=1 python setup.py develop"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install -e ."

    basic_run "$REPO" "$COMMAND"
}

# PartCrafter
install_partcrafter(){
    REPO="https://github.com/wgsxm/PartCrafter"
    COMMIT="269bd4164fbe35b17a6e58f8d6934262822082eb"
    COMMAND="uv run partcrafter_webui.py"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"

    # Copy custom files
    podman cp "$SCRIPT_DIR/custom_files/partcrafter/inference_partcrafter.py" "rocm:/AI/$FOLDER/scripts/inference_partcrafter.py"
    podman cp "$SCRIPT_DIR/custom_files/partcrafter/render_utils.py" "rocm:/AI/$FOLDER/src/utils/render_utils.py"
    podman cp "$SCRIPT_DIR/custom_files/partcrafter/partcrafter_webui.py" "rocm:/AI/$FOLDER/partcrafter_webui.py"
    podman cp "$SCRIPT_DIR/custom_files/partcrafter/autoencoder_kl_triposg.py" "rocm:/AI/$FOLDER/src/models/autoencoders/autoencoder_kl_triposg.py"

    basic_requirements "$REPO" 

    # exit 1

    # Clone and install pytorch_cluster_rocm
    podman exec -it rocm bash -c "cd /AI/$FOLDER && git clone https://github.com/Mateusz-Dera/pytorch_cluster_rocm && cd pytorch_cluster_rocm && git checkout 6be490d08df52755684b7ccfe10d55463070f13d"
    podman exec -it rocm bash -c "cd /AI/$FOLDER/pytorch_cluster_rocm && rm -rf requirements.txt && touch requirements.txt && source ../.venv/bin/activate && uv pip install ."

    basic_run "$REPO" "$COMMAND"
}

# TRELLIS-AMD
install_trellis(){
    REPO="https://github.com/CalebisGross/TRELLIS-AMD"
    COMMIT="2ccf54e8ff7aee0c519d37717bee6d95cf75357e"
    COMMAND="ATTN_BACKEND=sdpa XFORMERS_DISABLED=1 SPARSE_BACKEND=torchsparse uv run app.py"
    FOLDER=$(basename "$REPO")
    PYTHON_VERSION="3.11"

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO" "$PYTHON_VERSION"
    basic_requirements "$REPO"

    podman exec -t rocm bash -c "cd /AI/$FOLDER && sed -i 's/demo.launch(server_name=\"0.0.0.0\", share=True)/demo.launch(server_name=\"0.0.0.0\", share=False)/' app.py"
    podman exec -it rocm bash -c "cd /AI/$FOLDER/ && source .venv/bin/activate && uv pip install git+https://github.com/EasternJournalist/utils3d.git@9a4eb15e4021b67b12c460c7057d642626897ec8"
    podman exec -it rocm bash -c "cd /AI/$FOLDER/ && source .venv/bin/activate && cd extensions/nvdiffrast-hip && uv pip install . --no-build-isolation"
    podman exec -it rocm bash -c "cd /AI/$FOLDER/ && source .venv/bin/activate && cd extensions/diff-gaussian-rasterization && chmod +x build_hip.sh && ./build_hip.sh"
    podman exec -it rocm bash -c "cd /AI/$FOLDER/ && source .venv/bin/activate && cd extensions/torchsparse && rm -rf build *.egg-info 2>/dev/null || true && FORCE_CUDA=1 uv pip install . --no-build-isolation"

    # Patch gradio_client for compatibility
    echo "Patching gradio_client for compatibility..."
    podman exec -it rocm bash -c "
cd /AI/$FOLDER
source .venv/bin/activate
PYTHON_VER=\$(python3 -c 'import sys; print(f\"{sys.version_info.major}.{sys.version_info.minor}\")')
UTILS_FILE=\".venv/lib/python\${PYTHON_VER}/site-packages/gradio_client/utils.py\"
if [ -f \"\$UTILS_FILE\" ]; then
    # Patch get_type function to handle boolean schemas
    sed -i 's/def get_type(schema: dict):/def get_type(schema: dict):\\n    # Handle non-dict schemas (e.g., boolean from additionalProperties: true)\\n    if not isinstance(schema, dict):\\n        return \"Any\"/' \"\$UTILS_FILE\"
    # Patch _json_schema_to_python_type function
    sed -i 's/def _json_schema_to_python_type(schema: Any, defs) -> str:/def _json_schema_to_python_type(schema: Any, defs) -> str:\\n    # Handle non-dict schemas (e.g., boolean from additionalProperties: true)\\n    if not isinstance(schema, dict):\\n        return \"Any\"/' \"\$UTILS_FILE\"
    echo 'Successfully patched gradio_client for compatibility'
else
    echo 'Warning: gradio_client utils.py not found at' \"\$UTILS_FILE\"
fi
"

    basic_run "$REPO" "$COMMAND"
}

# Backup and Restore Manager
run_backup() {
    bash "$SCRIPT_DIR/backup.sh"
}
