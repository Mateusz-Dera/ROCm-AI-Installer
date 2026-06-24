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
    local UV_TOML="${3:-$SCRIPT_DIR/uv.toml}"

    podman cp "$UV_TOML" "rocm:/AI/$FOLDER/uv.toml"
    podman cp "$SCRIPT_DIR/requirements/$BASENAME.txt" "rocm:/AI/$FOLDER/requirements.txt"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install --override requirements.txt -r requirements.txt"
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

# ----- llama.cpp -----

LLAMA_REPO="https://github.com/ggml-org/llama.cpp"
LLAMA_COMMIT="721354fbdfb7743e2be2183d918a3cdb9276c70f"

install_llama_cpp() {
    REPO="$LLAMA_REPO"
    COMMIT="$LLAMA_COMMIT"
    FOLDER=$(basename "$REPO")
    COMMAND="./build/bin/llama-server -m model.gguf --spec-draft-model model_mtp.gguf --spec-type draft-mtp --spec-draft-n-max 4 --host 0.0.0.0 --port 8080 -c 131072 -ngl auto -fa on --cache-type-k q8_0 --cache-type-v q8_0"

    local HF_REPO="https://huggingface.co/unsloth/gemma-4-12b-it-GGUF"
    local MODEL_FILE="gemma-4-12b-it-Q8_0.gguf"
    local MTP_FILE="mtp-gemma-4-12b-it.gguf"

    basic_container
    basic_git "$REPO" "$COMMIT"
    PODMAN='HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" cmake -S . -B build -DLLAMA_CURL=OFF -DGGML_HIP=ON -DAMDGPU_TARGETS=$GFX -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release -- -j$(($(nproc) - 1))'
    podman exec -it rocm bash -c "cd /AI/$FOLDER && $PODMAN"

    podman exec -it rocm bash -c "wget -q '${HF_REPO}/resolve/main/${MODEL_FILE}' -O '/AI/$FOLDER/model.gguf'"
    podman exec -it rocm bash -c "wget -q '${HF_REPO}/resolve/main/${MTP_FILE}' -O '/AI/$FOLDER/model_mtp.gguf'"

    basic_run "$REPO" "$COMMAND" "&&"
}

install_llama_cpp_vulkan() {
    REPO="$LLAMA_REPO"
    COMMIT="$LLAMA_COMMIT"
    FOLDER="llama.cpp-vulkan"
    COMMAND="./build/bin/llama-server -m model.gguf --spec-draft-model model_mtp.gguf --spec-type draft-mtp --spec-draft-n-max 4 --host 0.0.0.0 --port 8080 -c 131072 -ngl auto -fa on --cache-type-k q8_0 --cache-type-v q8_0"

    local HF_REPO="https://huggingface.co/unsloth/gemma-4-12b-it-GGUF"
    local MODEL_FILE="gemma-4-12b-it-Q8_0.gguf"
    local MTP_FILE="mtp-gemma-4-12b-it.gguf"

    basic_container
    podman exec -it rocm bash -c "apt-get install -y libvulkan-dev vulkan-tools glslc"
    podman exec -t rocm bash -c "cd /AI && if [ -d $FOLDER ]; then rm -rf $FOLDER; fi"
    podman exec -it rocm bash -c "cd /AI && git clone $REPO $FOLDER && cd $FOLDER && git checkout $COMMIT"
    PODMAN='cmake -S . -B build -DLLAMA_CURL=OFF -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release -- -j$(($(nproc) - 1))'
    podman exec -it rocm bash -c "cd /AI/$FOLDER && $PODMAN"

    podman exec -it rocm bash -c "wget -q '${HF_REPO}/resolve/main/${MODEL_FILE}' -O '/AI/$FOLDER/model.gguf'"
    podman exec -it rocm bash -c "wget -q '${HF_REPO}/resolve/main/${MTP_FILE}' -O '/AI/$FOLDER/model_mtp.gguf'"

    basic_run "$REPO" "$COMMAND" "&&" "$FOLDER"
}

# ----- turboquant-rocm-llamacpp -----

LLAMA_TQ_REPO="https://github.com/jagsan-cyber/turboquant-rocm-llamacpp"
LLAMA_TQ_COMMIT="22cce31b6e58f3e945fbc7f2f5eb06a509e64fcc"

install_turboquant_rocm_llamacpp() {
    REPO="$LLAMA_TQ_REPO"
    COMMIT="$LLAMA_TQ_COMMIT"
    FOLDER=$(basename "$REPO")
    COMMAND="./build/bin/llama-server -m model.gguf --host 0.0.0.0 --port 8080 -c 131072 --flash-attn on --cache-type-k q4_0 --cache-type-v q4_0 -ngl 99"

    local HF_REPO="https://huggingface.co/unsloth/gemma-4-12b-it-GGUF"
    local MODEL_FILE="gemma-4-12b-it-Q8_0.gguf"

    basic_container
    basic_git "$REPO" "$COMMIT"
    PODMAN='HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" cmake -S . -B build -DLLAMA_CURL=OFF -DGGML_HIP=ON -DAMDGPU_TARGETS=$GFX -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release -- -j$(($(nproc) - 1))'
    podman exec -it rocm bash -c "cd /AI/$FOLDER && $PODMAN"

    podman exec -it rocm bash -c "wget -q '${HF_REPO}/resolve/main/${MODEL_FILE}' -O '/AI/$FOLDER/model.gguf'"

    basic_run "$REPO" "$COMMAND" "&&"
}

# SillyTavern
install_sillytavern(){
    REPO="https://github.com/SillyTavern/SillyTavern"
    COMMIT="51ad27fb86d39a3daca3adaa970375c9670c12df"
    COMMAND="bash start.sh"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_run "$REPO" "$COMMAND" "&&"

    podman exec -t rocm bash -c "cd $FOLDER/default && sed -i 's/listen: false/listen: true/' config.yaml"
    podman exec -t rocm bash -c "cd $FOLDER/default && sed -i 's/whitelistMode: true/whitelistMode: false/' config.yaml"
    podman exec -t rocm bash -c "cd $FOLDER/default && sed -i 's/basicAuthMode: false/basicAuthMode: true/' config.yaml"
}

# WhisperSpeech
WS_REPO="https://github.com/Mateusz-Dera/whisperspeech-webui"
WS_COMMIT="55368e08774e3ea6ab0a864aafa2a3506b7c7059"

# SillyTavern WhisperSpeech web UI
install_sillytavern_whisperspeech_web_ui() {
    REPO="$WS_REPO"
    COMMIT="$WS_COMMIT"

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

# Queue for parallel downloads (dir|repo|commit|file)
_COMFY_DL_QUEUE=()

# Queue a model download – actual transfer starts in comfy_wait
comfy_download() {
    _COMFY_DL_QUEUE+=("$1|$2|$3|$4")
}

_comfy_fmt_size() {
    local b=$1
    if   (( b >= 1073741824 )); then awk "BEGIN{printf \"%.1f GB\", $b/1073741824}"
    elif (( b >= 1048576    )); then awk "BEGIN{printf \"%.0f MB\",  $b/1048576}"
    else                             awk "BEGIN{printf \"%.0f KB\",  $b/1024}"
    fi
}

# Run all queued downloads simultaneously with a live overall progress bar
comfy_wait() {
    local n=${#_COMFY_DL_QUEUE[@]}
    [[ $n -eq 0 ]] && return 0

    local tmpdir
    tmpdir=$(mktemp -d)
    local -a names=() dirs=() urls=() destpaths=()
    local idx=0

    for entry in "${_COMFY_DL_QUEUE[@]}"; do
        local dir repo commit file filename
        IFS='|' read -r dir repo commit file <<< "$entry"
        filename=$(basename "$file")
        names+=("$filename")
        dirs+=("$dir")
        urls+=("$repo/resolve/$commit/$file")
        destpaths+=("/AI/$dir/$filename")
        (( idx++ )) || true
    done

    # Fetch file sizes in parallel (curl HEAD inside container)
    printf "\n  Fetching file sizes...\n"
    for (( i=0; i<n; i++ )); do
        ( s=$(podman exec -i rocm bash -c \
                "curl -sIL '${urls[$i]}' 2>/dev/null \
                 | grep -i '^content-length:' | tail -1 \
                 | tr -d '[:space:]\r' | cut -d: -f2")
          [[ "$s" =~ ^[0-9]+$ ]] && echo "$s" || echo 0 ) > "$tmpdir/size$i" &
    done
    wait

    local -a sizes=()
    local total_size=0
    for (( i=0; i<n; i++ )); do
        local s; s=$(cat "$tmpdir/size$i" 2>/dev/null); [[ "$s" =~ ^[0-9]+$ ]] || s=0
        sizes+=("$s")
        total_size=$(( total_size + s ))
    done

    # Start all downloads in background
    for (( i=0; i<n; i++ )); do
        ( podman exec -i rocm bash -c \
            "wget -q -P \"${dirs[$i]}\" \"${urls[$i]}\""; echo $? > "$tmpdir/s$i" ) &
    done

    local -a spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local si=0 bar_width=40
    local -a done_flags=() statuses=()
    for (( i=0; i<n; i++ )); do done_flags[$i]=0; statuses[$i]=0; done

    # Build stat one-liner to check all dest files in one podman exec
    local stat_cmd=""
    for (( i=0; i<n; i++ )); do
        stat_cmd+="stat -c%s '${destpaths[$i]}' 2>/dev/null || echo 0; "
    done

    printf "\n  Downloading %d file(s) simultaneously...\n\n" "$n"

    local first=1
    while true; do
        # Check completions
        local all_done=1
        for (( i=0; i<n; i++ )); do
            if [[ ${done_flags[$i]} -eq 0 ]]; then
                if [[ -f "$tmpdir/s$i" ]]; then
                    done_flags[$i]=1; statuses[$i]=$(cat "$tmpdir/s$i")
                else
                    all_done=0
                fi
            fi
        done

        # Get current downloaded sizes in one exec
        local downloaded=0
        local -a cur=()
        while IFS= read -r line; do
            line=$(tr -d '[:space:]' <<< "$line")
            [[ "$line" =~ ^[0-9]+$ ]] || line=0
            cur+=("$line")
            downloaded=$(( downloaded + line ))
        done < <(podman exec -i rocm bash -c "$stat_cmd" 2>/dev/null)
        # pad cur[] if podman returned fewer lines than expected
        while (( ${#cur[@]} < n )); do cur+=(0); done

        # Calculate percentage and bar
        local pct=0
        [[ $total_size -gt 0 ]] && pct=$(( downloaded * 100 / total_size ))
        [[ $pct -gt 100 ]] && pct=100

        local bar=""
        local filled=$(( pct * bar_width / 100 ))
        for (( j=0; j<bar_width; j++ )); do
            (( j < filled )) && bar+="█" || bar+="░"
        done

        local dl_hr total_hr
        dl_hr=$(_comfy_fmt_size "$downloaded")
        total_hr=$(_comfy_fmt_size "$total_size")

        # Redraw: move up (bar line + blank line + N file lines) = N+2, skip on first pass
        if [[ $first -eq 1 ]]; then first=0; else printf "\033[%dA" $(( n + 2 )); fi

        printf "  \033[36m[%s]\033[0m  \033[1m%3d%%\033[0m   %s / %s\n" \
               "$bar" "$pct" "$dl_hr" "$total_hr"
        printf "\n"
        for (( i=0; i<n; i++ )); do
            if   [[ ${done_flags[$i]} -eq 1 && ${statuses[$i]} -eq 0 ]]; then
                printf "    \033[32m✓\033[0m %-65s\n" "${names[$i]}"
            elif [[ ${done_flags[$i]} -eq 1 ]]; then
                printf "    \033[31m✗\033[0m %-65s\n" "${names[$i]}"
            else
                printf "    \033[33m%s\033[0m %-65s\n" "${spin[$si]}" "${names[$i]}"
            fi
        done

        [[ $all_done -eq 1 ]] && break
        si=$(( (si + 1) % 10 ))
        sleep 0.5
    done

    printf "\n"
    wait
    rm -rf "$tmpdir"
    _COMFY_DL_QUEUE=()

    for s in "${statuses[@]}"; do [[ "$s" -ne 0 ]] && return 1; done
    return 0
}

# ComfyUI
install_comfyui() {
    REPO="https://github.com/comfyanonymous/ComfyUI"
    COMMIT="b0f9e326af0bf88ea901d0481f581a791a58ccbb"
    TUNABLEOP=""
    #if [[ "$GFX_VERSION" == gfx110* ]]; then
    #    TUNABLEOP="PYTORCH_TUNABLEOP_ENABLED=1 PYTORCH_TUNABLEOP_TUNING=1"
    #fi
    COMMAND="PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512 TORCH_BLAS_PREFER_HIPBLASLT=1 $TUNABLEOP uv run main.py --listen 0.0.0.0 --enable-manager --preview-method auto --dont-upcast-attention --bf16-vae --use-pytorch-cross-attention --reserve-vram 2.0"
    FOLDER=$(basename "$REPO")
    ADDONS="$@"

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"

    # comfy_aimdo is NVIDIA-only; install a stub package so all imports succeed on AMD
    podman exec -it rocm bash -c "
mkdir -p /AI/ComfyUI/comfy_aimdo
cat > /AI/ComfyUI/comfy_aimdo/__init__.py << 'PYEOF'
PYEOF
cat > /AI/ComfyUI/comfy_aimdo/control.py << 'PYEOF'
def init(): pass
def init_device(index): return False
def set_log_debug(): pass
def set_log_critical(): pass
def set_log_error(): pass
def set_log_warning(): pass
def set_log_info(): pass
def get_total_vram_usage(): return 0
PYEOF
cat > /AI/ComfyUI/comfy_aimdo/model_vbar.py << 'PYEOF'
class _VbarSlot:
    pass
class ModelVBAR:
    def __init__(self, size, device_index): pass
    def alloc(self, size): return _VbarSlot()
    def loaded_size(self): return 0
def vbars_analyze(): return 0
def vbar_fault(v): return None
def vbar_signature_compare(signature, v): return False
def vbar_unpin(v): pass
def vbars_reset_watermark_limits(): pass
PYEOF
cat > /AI/ComfyUI/comfy_aimdo/vram_buffer.py << 'PYEOF'
class VRAMBuffer:
    def __init__(self, size, device_index):
        raise RuntimeError('comfy_aimdo stub: VRAMBuffer not available on AMD')
    def get(self, size, offset=0): return None
    def size(self): return 0
PYEOF
cat > /AI/ComfyUI/comfy_aimdo/host_buffer.py << 'PYEOF'
class HostBuffer:
    def __init__(self, size):
        raise RuntimeError('comfy_aimdo stub: HostBuffer not available on AMD')
PYEOF
cat > /AI/ComfyUI/comfy_aimdo/torch.py << 'PYEOF'
def hostbuf_to_tensor(hostbuf): return None
def aimdo_to_tensor(obj, device): return None
PYEOF
cat > /AI/ComfyUI/comfy_aimdo/model_mmap.py << 'PYEOF'
import mmap, ctypes, os
class ModelMMAP:
    def __init__(self, path):
        self._f = open(path, 'rb')
        size = os.path.getsize(path)
        self._mm = mmap.mmap(self._f.fileno(), size, access=mmap.ACCESS_READ)
        self._arr = (ctypes.c_uint8 * size).from_buffer(self._mm)
    def get(self):
        return ctypes.addressof(self._arr)
    def __del__(self):
        try:
            del self._arr
            self._mm.close()
            self._f.close()
        except Exception:
            pass
PYEOF
"

    # torchaudio 2.10+ uses torchcodec (CUDA-only) – patch to soundfile fallback
    podman exec -t rocm bash -c "python3 - << 'PYEOF'
import pathlib
path = pathlib.Path('/AI/$FOLDER/.venv/lib/python3.13/site-packages/torchaudio/_torchcodec.py')
src = path.read_text()
OLD = '''    # Import torchcodec here to provide clear error if not available
    try:
        from torchcodec.decoders import AudioDecoder
    except ImportError as e:
        raise ImportError(
            \"TorchCodec is required for load_with_torchcodec. \" \"Please install torchcodec to use this function.\"
        ) from e'''
NEW = '''    # Import torchcodec; fall back to soundfile if unavailable (torchcodec is CUDA-only)
    try:
        from torchcodec.decoders import AudioDecoder
        _USE_SF = False
    except (ImportError, RuntimeError):
        _USE_SF = True
    if _USE_SF:
        import soundfile as sf, numpy as np, torch
        data, sr = sf.read(str(uri), dtype=\"float32\", always_2d=True)
        w = torch.from_numpy(data.T)
        if frame_offset > 0: w = w[:, frame_offset:]
        if num_frames != -1: w = w[:, :num_frames]
        if not channels_first: w = w.T
        return w, sr'''
if OLD in src:
    path.write_text(src.replace(OLD, NEW))
    print('torchaudio soundfile patch applied')
else:
    print('WARNING: torchaudio patch target not found - may already be patched')
PYEOF"

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

    # Z-Image / Z-Anime shared (vae + text encoder used by both)
    if [[ "$ADDONS" == *"3"* ]] || [[ "$ADDONS" == *"4"* ]]; then
        comfy_download "$FOLDER/models/vae/" "https://huggingface.co/Comfy-Org/z_image_turbo" "2f862278568d3f0a83167a16e5f11094da6dee72" "split_files/vae/ae.safetensors"
        comfy_download "$FOLDER/models/text_encoders/" "https://huggingface.co/SeeSee21/Z-Anime" "0f5fb51464638a2f7328a1d74590281e63e1fde2" "text_encoder/qwen_3_4b-bf16.safetensors"
    fi

    # 3 - Z-Image-Turbo
    if [[ "$ADDONS" == *"3"* ]]; then
        comfy_download "$FOLDER/models/diffusion_models/" "https://huggingface.co/Comfy-Org/z_image_turbo" "2f862278568d3f0a83167a16e5f11094da6dee72" "split_files/diffusion_models/z_image_turbo_bf16.safetensors"
    fi

    # 4 - Z-Anime
    if [[ "$ADDONS" == *"4"* ]]; then
        comfy_download "$FOLDER/models/diffusion_models/" "https://huggingface.co/SeeSee21/Z-Anime" "0f5fb51464638a2f7328a1d74590281e63e1fde2" "diffusion_models/z-anime-distill-4step-bf16.safetensors"
    fi

    # 5 - Wan 2.2 TI2V 5B
    if [[ "$ADDONS" == *"5"* ]]; then
        WAN_REPO="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged"
        WAN_COMMIT="f97505f0d38bea4897c970db66cb5f97f73676de"
        comfy_download "$FOLDER/models/text_encoders/" "$WAN_REPO" "$WAN_COMMIT" "split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
        comfy_download "$FOLDER/models/vae/" "$WAN_REPO" "$WAN_COMMIT" "split_files/vae/wan_2.1_vae.safetensors"
        comfy_download "$FOLDER/models/vae/" "$WAN_REPO" "$WAN_COMMIT" "split_files/vae/wan2.2_vae.safetensors"
        comfy_download "$FOLDER/models/diffusion_models/" "$WAN_REPO" "$WAN_COMMIT" "split_files/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors"
    fi

    comfy_wait
}

# ACE-Step-1.5
install_ace_step_1_5() {
    REPO="https://github.com/ace-step/ACE-Step-1.5"
    COMMIT="dce621408bee8c31b4fcf4811682eb9359e1bc94"
    COMMAND="ACESTEP_LM_BACKEND=pt MIOPEN_FIND_MODE=FAST python -m acestep.acestep_v15_pipeline --server-name 0.0.0.0 --port 7860 --config_path acestep-v15-turbo --lm_model_path acestep-5Hz-lm-4B --init_service true --backend pt"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"

    # Fix: torchaudio 2.10+ requires torchcodec for MP3 – change default to WAV
    podman cp "$SCRIPT_DIR/custom_files/ACE-Step-1.5/generation_advanced_output_controls.py" \
        "rocm:/AI/$FOLDER/acestep/ui/gradio/interfaces/generation_advanced_output_controls.py"

    # torchaudio 2.10+ uses torchcodec (CUDA-only) – patch to soundfile fallback
    podman exec -t rocm bash -c "python3 - << 'PYEOF'
import pathlib
path = pathlib.Path('/AI/$FOLDER/.venv/lib/python3.13/site-packages/torchaudio/_torchcodec.py')
src = path.read_text()
OLD = '''    # Import torchcodec here to provide clear error if not available
    try:
        from torchcodec.decoders import AudioDecoder
    except ImportError as e:
        raise ImportError(
            \"TorchCodec is required for load_with_torchcodec. \" \"Please install torchcodec to use this function.\"
        ) from e'''
NEW = '''    # Import torchcodec; fall back to soundfile if unavailable (torchcodec is CUDA-only)
    try:
        from torchcodec.decoders import AudioDecoder
        _USE_SF = False
    except (ImportError, RuntimeError):
        _USE_SF = True
    if _USE_SF:
        import soundfile as sf, numpy as np, torch
        data, sr = sf.read(str(uri), dtype=\"float32\", always_2d=True)
        w = torch.from_numpy(data.T)
        if frame_offset > 0: w = w[:, frame_offset:]
        if num_frames != -1: w = w[:, :num_frames]
        if not channels_first: w = w.T
        return w, sr'''
if OLD in src:
    path.write_text(src.replace(OLD, NEW))
    print('torchaudio soundfile patch applied')
else:
    print('WARNING: torchaudio patch target not found - may already be patched')
PYEOF"

    basic_run "$REPO" "$COMMAND"
}

# WhisperSpeech web UI
install_whisperspeech_web_ui(){
    REPO=$WS_REPO
    COMMIT=$WS_COMMIT
    COMMAND="uv run --extra rocm webui.py --listen --api"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"

    # Install dependencies with ROCm support using uv sync
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv sync --extra rocm"

    basic_run "$REPO" "$COMMAND"
}

# Soprano
install_soprano(){
    REPO="https://github.com/Mateusz-Dera/soprano-rocm"
    COMMIT="e4b3dd66641cc22c8f97f167ad1bfd75e04292e5"
    COMMAND="TORCH_BLAS_PREFER_HIPBLASLT=1 soprano-webui --backend vllm"
    FOLDER=$(basename "$REPO")

    basic_container
    podman exec -it rocm bash -c "apt-get install -y libopenmpi40"
    # libmpi_cxx.so.40: OpenMPI 4.x dropped C++ bindings; torch lw builds still link against them.
    # Create a stub shared library with the 3 C++ symbols torch references (never called at inference time).
    podman exec -t rocm bash -c "
cat > /tmp/mpi_cxx_stub.cpp << 'EOF'
// Stub libmpi_cxx.so.40 for OpenMPI 4.x on Ubuntu 26.04
// These symbols were removed from OpenMPI 4.x but torch lw builds still link against them.
// None are called during single-GPU inference.
extern \"C\" {
    void ompi_mpi_cxx_op_intercept(void*, void*, int*, void*) {}
    void ompi_op_set_cxx_callback(void*, void*) {}
}
namespace MPI {
    class Datatype { public: void Free(); };
    class Win      { public: void Free(); };
    class Comm     { public: Comm(); };
    void Datatype::Free() {}
    void Win::Free()      {}
    Comm::Comm()          {}
}
EOF
g++ -shared -fPIC -Wl,-soname,libmpi_cxx.so.40 \
    -o /usr/lib/x86_64-linux-gnu/libmpi_cxx.so.40 \
    /tmp/mpi_cxx_stub.cpp && ldconfig"
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO" "3.12"

    # vllm must be installed first — it manages torch/torchaudio/torchvision/triton/amd-aiter
    # (vllm 0.23.0+rocm723 bundles its own torch build, not from ROCm manylinux)
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install 'vllm==0.23.0+rocm723' --extra-index-url https://wheels.vllm.ai/rocm/"

    basic_requirements "$REPO"

    basic_pip "$REPO" "/opt/rocm/share/amd_smi"

    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install -e ."

    basic_run "$REPO" "$COMMAND"
}

# OmniVoice
install_omnivoice(){
    REPO="https://github.com/k2-fsa/OmniVoice"
    COMMIT="b2dcccaa9f68fe0255326ce675d24b6d112b685a"
    COMMAND="omnivoice-demo --ip 0.0.0.0 --port 7860"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install --no-deps  -e ."

    # ROCm: HiggsAudioV2TokenizerModel crashes when loaded directly to GPU via device_map='cuda'.
    # Patch from_pretrained to load everything on CPU then move to GPU.
    podman exec -t rocm bash -c "python3 - << 'PYEOF'
path = '/AI/$FOLDER/omnivoice/models/omnivoice.py'
with open(path) as f:
    c = f.read()

old1 = '''    @classmethod
    def from_pretrained(cls, pretrained_model_name_or_path, *args, **kwargs):
        train_mode = kwargs.pop(\"train\", False)
        load_asr = kwargs.pop(\"load_asr\", False)
        asr_model_name = kwargs.pop(\"asr_model_name\", \"openai/whisper-large-v3-turbo\")

        # Suppress noisy INFO logs from transformers/huggingface_hub during loading
        _prev_disable = logging.root.manager.disable
        logging.disable(logging.INFO)

        try:
            model = super().from_pretrained(
                pretrained_model_name_or_path, *args, **kwargs
            )'''
new1 = '''    @classmethod
    def from_pretrained(cls, pretrained_model_name_or_path, *args, **kwargs):
        train_mode = kwargs.pop(\"train\", False)
        load_asr = kwargs.pop(\"load_asr\", False)
        asr_model_name = kwargs.pop(\"asr_model_name\", \"openai/whisper-large-v3-turbo\")

        _target_device_map = kwargs.pop(\"device_map\", None)
        if _target_device_map is not None and str(_target_device_map) not in (\"cpu\", \"auto\"):
            _move_to_device = str(_target_device_map)
        else:
            _move_to_device = None
        kwargs[\"device_map\"] = \"cpu\"

        _prev_disable = logging.root.manager.disable
        logging.disable(logging.INFO)

        try:
            model = super().from_pretrained(
                pretrained_model_name_or_path, *args, **kwargs
            )'''

old2 = '''                # higgs-audio-v2-tokenizer does not support MPS (output channels > 65536)
                tokenizer_device = (
                    \"cpu\" if str(model.device).startswith(\"mps\") else model.device
                )
                model.audio_tokenizer = HiggsAudioV2TokenizerModel.from_pretrained(
                    audio_tokenizer_path, device_map=tokenizer_device
                )'''
new2 = '''                model.audio_tokenizer = HiggsAudioV2TokenizerModel.from_pretrained(
                    audio_tokenizer_path, device_map=\"cpu\"
                )'''

old3 = '''                if load_asr:
                    model.load_asr_model(model_name=asr_model_name)
        finally:
            logging.disable(_prev_disable)

        return model'''
new3 = '''                if load_asr:
                    model.load_asr_model(model_name=asr_model_name)

                if _move_to_device is not None:
                    _td = _move_to_device
                    model = model.to(_td)
                    model.audio_tokenizer = model.audio_tokenizer.to(_td)
        finally:
            logging.disable(_prev_disable)

        return model'''

for old, new in [(old1, new1), (old2, new2), (old3, new3)]:
    if old in c:
        c = c.replace(old, new)
        print('patch applied')
    else:
        print('WARNING: patch not applied - string not found')

with open(path, 'w') as f:
    f.write(c)
PYEOF"

    # torchaudio 2.10+ requires torchcodec (CUDA-only) – patch to use soundfile fallback
    podman exec -t rocm bash -c "python3 - << 'PYEOF'
path = '/AI/$FOLDER/.venv/lib/python3.13/site-packages/torchaudio/_torchcodec.py'
with open(path) as f:
    c = f.read()
old = '''    # Import torchcodec here to provide clear error if not available
    try:
        from torchcodec.decoders import AudioDecoder
    except ImportError as e:
        raise ImportError(
            \"TorchCodec is required for load_with_torchcodec. \" \"Please install torchcodec to use this function.\"
        ) from e'''
new = '''    try:
        from torchcodec.decoders import AudioDecoder
        _USE_SF = False
    except (ImportError, RuntimeError):
        _USE_SF = True
    if _USE_SF:
        import soundfile as sf, numpy as np, torch
        data, sr = sf.read(str(uri), dtype=\"float32\", always_2d=True)
        w = torch.from_numpy(data.T)
        if frame_offset > 0: w = w[:, frame_offset:]
        if num_frames != -1: w = w[:, :num_frames]
        if not channels_first: w = w.T
        return w, sr'''
if old in c:
    c = c.replace(old, new)
    print('torchaudio patch applied')
else:
    print('WARNING: torchaudio patch not found')
with open(path, 'w') as f:
    f.write(c)
PYEOF"

    # Also patch demo.py to use float32 (float16 causes instability on ROCm)
    podman exec -t rocm bash -c "sed -i 's/dtype=torch\.float16/dtype=torch.float32/' /AI/$FOLDER/omnivoice/cli/demo.py"

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

# TRELLIS.2_rocm
install_trellis_2_rocm() {
    REPO="https://github.com/hqnicolas/TRELLIS.2_rocm"
    COMMIT="1eac4201e111755a1b9eafe5edfc1526d4db07c3"
    COMMAND="ROCM_SAFE_SPCONV=1 FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE ATTN_BACKEND=sdpa GRADIO_SERVER_NAME=0.0.0.0 python app.py"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO" "3.11"
    basic_requirements "$REPO" "$FOLDER" "$SCRIPT_DIR/custom_files/$FOLDER/uv.toml"

    # flash-attn has no prebuilt ROCm wheel; build from source using the venv's torch
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        ROCM_PATH=\$ROCM_HOME PYTORCH_ROCM_ARCH=$TARGET_GFX \
        uv pip install 'flash-attn==2.8.3' --no-build-isolation"

    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install git+https://github.com/EasternJournalist/utils3d.git@9a4eb15e4021b67b12c460c7057d642626897ec8"

    podman exec -it rocm bash -c "sed -i 's/hashmap_build_submanifold_conv_neighbour_map_cuda/hashmap_build_submanifold_conv_neighbour_map/g' \
        /AI/$FOLDER/trellis2/modules/sparse/conv/conv_flex_gemm.py"

    # ROCM_SAFE_SPCONV safe path must apply for any N (not just N > ROCM_SAFE_CHUNK),
    # because small inputs (N=59) also trigger segfault in SubmanifoldConv3d HIP kernel.
    podman exec -it rocm bash -c "sed -i \
        's/if sparse_config.ROCM_SAFE_SPCONV and N > ROCM_SAFE_CHUNK:/if sparse_config.ROCM_SAFE_SPCONV:/' \
        /AI/$FOLDER/trellis2/modules/sparse/conv/conv_flex_gemm.py"

    podman exec -it rocm bash -c "
        mkdir -p /AI/$FOLDER/Dependency/CuMesh/third_party/cubvh/third_party && \
        cp -a /AI/$FOLDER/Dependency/eigen /AI/$FOLDER/Dependency/CuMesh/third_party/cubvh/third_party/eigen && \
        mkdir -p /AI/$FOLDER/Dependency/o-voxel/third_party && \
        cp -a /AI/$FOLDER/Dependency/eigen /AI/$FOLDER/Dependency/o-voxel/third_party/eigen"

    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        ROCM_PATH=\$ROCM_HOME PYTORCH_ROCM_ARCH=$TARGET_GFX \
        uv pip install Dependency/nvdiffrast-hip --no-build-isolation"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        ROCM_PATH=\$ROCM_HOME PYTORCH_ROCM_ARCH=$TARGET_GFX \
        uv pip install Dependency/nvdiffrec --no-build-isolation"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        BUILD_TARGET=rocm GPU_ARCHS=$TARGET_GFX ROCM_PATH=\$ROCM_HOME PYTORCH_ROCM_ARCH=$TARGET_GFX \
        uv pip install Dependency/CuMesh --no-build-isolation"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        BUILD_TARGET=rocm GPU_ARCHS=$TARGET_GFX ROCM_PATH=\$ROCM_HOME PYTORCH_ROCM_ARCH=$TARGET_GFX \
        uv pip install Dependency/FlexGEMM-rocm --no-build-isolation"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        BUILD_TARGET=rocm GPU_ARCHS=$TARGET_GFX ROCM_PATH=\$ROCM_HOME PYTORCH_ROCM_ARCH=$TARGET_GFX \
        uv pip install Dependency/o-voxel --no-build-isolation"

    basic_run "$REPO" "$COMMAND"
}

# Kimodo
install_kimodo() {
    REPO="https://github.com/nv-tlabs/kimodo"
    COMMIT="c6c8ba766e52172f1ad34cd1fbe912115c82ce34"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install -e ."
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install 'viser @ git+https://github.com/nv-tlabs/kimodo-viser.git'"

    # viser extracts node-v20 tarball lazily on first server start with UID 1000 inside
    # container (→ ~101000 on host via rootless podman UID remapping), making files
    # undeletable from host. Fix: chown at install time AND at every run.sh invocation.
    podman exec -t rocm bash -c "chown -R root:root /AI/$FOLDER/ 2>/dev/null || true"

    # Custom run.sh: chown before start so viser node files created on any previous run
    # are fixed before the next run, keeping all files deletable from the host.
    podman exec -t rocm bash -c "cat > /AI/$FOLDER/run.sh << 'RUNEOF'
#!/bin/bash
if ! podman ps -a --format '{{.Names}}' | grep -q '^rocm$'; then
    echo 'Error: Container rocm does not exist.'
    exit 1
fi
if ! podman ps --format '{{.Names}}' | grep -q '^rocm$'; then
    echo 'Container rocm is not running. Starting...'
    podman start rocm
fi
podman exec -t rocm bash -c 'chown -R root:root /AI/kimodo/ 2>/dev/null || true'
podman exec -it rocm bash -c 'cd /AI/kimodo && source .venv/bin/activate && TEXT_ENCODER_DEVICE=cpu kimodo_demo'
podman exec -t rocm bash -c 'chown -R root:root /AI/kimodo/ 2>/dev/null || true'
RUNEOF
chmod +x /AI/$FOLDER/run.sh"
}

# TripoSplat
install_triposplat(){
    REPO="https://github.com/VAST-AI-Research/TripoSplat"
    COMMIT="a78fa12d06dbf1381ca548bfac32bb68cb8c451d"
    COMMAND="python run_gradio.py"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"
    basic_run "$REPO" "$COMMAND"

    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && hf download VAST-AI/TripoSplat --local-dir ckpts/"
}

# Backup and Restore Manager
run_backup() {
    bash "$SCRIPT_DIR/backup.sh"
}
