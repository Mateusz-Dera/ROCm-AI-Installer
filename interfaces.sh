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
    GPU_CLAUSE=""
    [ -n "${GPU_APP:-}" ] && GPU_CLAUSE="$(gpu_pin_clause)"
    unset GPU_APP

    if ! podman ps -a --format "{{.Names}}" | grep -q "^rocm$"; then
        echo "Error: Container 'rocm' does not exist."
        echo "Please create the container first using option '2. Create a container' from the main menu."
        read -p "Press Enter to continue..."
        return 1
    fi

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
    local PYTHON=${2:-3.14}
    local FOLDER=${3:-$(basename "$REPO")}

    podman exec -it rocm bash -c "cd /AI/$FOLDER && uv venv --python $PYTHON"
}

ROCM_WHEEL_ARCHS="gfx1010 gfx1011 gfx1012 gfx1030 gfx1031 gfx1032 gfx1033 \
gfx1034 gfx1035 gfx1036 gfx1100 gfx1101 gfx1102 gfx1103 gfx1150 gfx1151 \
gfx1152 gfx1153 gfx1200 gfx1201 gfx908 gfx90a gfx942 gfx950"

rocm_device_extras() {
    local req=$1 pkg ver arch extras
    for pkg in torch torchvision; do
        ver=$(grep -m1 "^$pkg==" "$req" | cut -d= -f3)
        [ -z "$ver" ] && continue
        extras=""
        for arch in $(echo "${TARGET_GFX_ALL:-${TARGET_GFX:-}}" | tr ';' ' '); do
            case " $ROCM_WHEEL_ARCHS " in
                *" $arch "*) extras="$extras,device-$arch" ;;
            esac
        done
        [ -z "$extras" ] && continue
        echo "$pkg[${extras#,}]==$ver"
    done
}

rocm_torch_spec() {
    local extras="" arch pkg out=""
    for arch in $(echo "${TARGET_GFX_ALL:-${TARGET_GFX:-}}" | tr ';' ' '); do
        case " $ROCM_WHEEL_ARCHS " in
            *" $arch "*) extras="$extras,device-$arch" ;;
        esac
    done
    for pkg in "$@"; do
        case "$pkg" in
            torch|torchvision|torch[=\<\>]*|torchvision[=\<\>]*)
                local name=${pkg%%[=\<\>]*}
                [ -n "$extras" ] && pkg="'$name[${extras#,}]${pkg#"$name"}'"
                ;;
        esac
        out="$out $pkg"
    done
    printf '%s' "${out# }"
}

# REQUIREMENTS
basic_requirements(){
    local REPO=$1
    local FOLDER=${2:-$(basename "$REPO")}
    local BASENAME=$(basename "$REPO")
    local UV_TOML="${3:-$SCRIPT_DIR/uv.toml}"

    local REQ_TMP
    REQ_TMP=$(mktemp)
    awk 1 "$SCRIPT_DIR/requirements/$BASENAME.txt" > "$REQ_TMP"
    rocm_device_extras "$SCRIPT_DIR/requirements/$BASENAME.txt" >> "$REQ_TMP"

    podman cp "$UV_TOML" "rocm:/AI/$FOLDER/uv.toml"
    podman cp "$REQ_TMP" "rocm:/AI/$FOLDER/requirements.txt"
    rm -f "$REQ_TMP"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install --override requirements.txt -r requirements.txt"
}

detect_gpus() {
    local v major minor step props
    for props in /sys/class/kfd/kfd/topology/nodes/*/properties; do
        [ -r "$props" ] || continue
        awk '$1=="simd_count"{s=$2} $1=="gfx_target_version"{v=$2}
             END{if (s+0 > 0 && v+0 > 0) print v}' "$props"
    done | while read -r v; do
        major=$((v / 10000)); minor=$(((v / 100) % 100)); step=$((v % 100))
        printf 'gfx%d%x%x\n' "$major" "$minor" "$step"
    done
}

gpu_pin_clause() {
    local gpus=() cand=() entries=() idx=0 tag desc chosen archs
    mapfile -t gpus < <(detect_gpus)
    [ ${#gpus[@]} -eq 0 ] && return 0

    archs=";${TARGET_GFX_ALL:-${TARGET_GFX:-}};"
    for tag in "${gpus[@]}"; do
        [[ "$archs" == *";$tag;"* ]] && cand+=("$idx|$tag")
        idx=$((idx + 1))
    done

    [ ${#cand[@]} -eq 0 ] && return 0

    if [ -n "${GPU_PIN_INDEX:-}" ]; then
        printf '&& export HIP_VISIBLE_DEVICES=%s' "$GPU_PIN_INDEX"
        return 0
    fi

    if [ ${#cand[@]} -eq 1 ]; then
        printf '&& export HIP_VISIBLE_DEVICES=%s' "${cand[0]%%|*}"
        return 0
    fi

    for entry in "${cand[@]}"; do
        tag="${entry#*|}"; desc="$tag"
        for known in "${KNOWN_GFX[@]}"; do
            [ "${known%%|*}" = "$tag" ] && desc="${known#*|}" && break
        done
        entries+=("${entry%%|*}" "$tag - $desc" "$([ "${entry%%|*}" = "${cand[0]%%|*}" ] && echo ON || echo OFF)")
    done

    chosen=$(whiptail --title "GPU for this application" --separate-output \
        --radiolist "Which card should this application use?\n\nThe answer is written into its run.sh, so different applications can\nuse different cards. Numbers are device indexes as ROCm sees them." \
        18 78 "${#cand[@]}" "${entries[@]}" 2>&1 > /dev/tty) || true

    [ -z "$chosen" ] && chosen="${cand[0]%%|*}"
    printf '&& export HIP_VISIBLE_DEVICES=%s' "$chosen"
}

# RUN
basic_run(){
    local REPO=$1
    local COMMAND="$2"
    local VENV=${3:-"&& source .venv/bin/activate &&"}
    local FOLDER=${4:-$(basename "$REPO")}

    podman exec -t rocm bash -c "cat > /AI/$FOLDER/run.sh << RUNEOF
#!/bin/bash
if ! podman ps -a --format \"{{.Names}}\" | grep -q \"^rocm\\\$\"; then
    echo \"Error: Container 'rocm' does not exist.\"
    echo \"Please create the container first.\"
    exit 1
fi

if ! podman ps --format \"{{.Names}}\" | grep -q \"^rocm\\\$\"; then
    echo \"Container rocm is not running. Starting...\"
    podman start rocm
fi
podman exec -it rocm bash -c \"cd /AI/$FOLDER ${GPU_CLAUSE:-} $VENV $COMMAND\"
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

# ----- llama.cpp -----

LLAMA_TQ_REPO="https://github.com/TheTom/llama-cpp-turboquant"
LLAMA_TQ_COMMIT="2168b0cd8b87c75c29a1e6588692ebbb805b9bd2"

LLAMA_TQ_HF="https://huggingface.co/unsloth/gemma-4-26B-A4B-it-qat-GGUF/resolve/main"
LLAMA_TQ_MODEL="gemma-4-26B-A4B-it-qat-UD-Q4_K_XL.gguf"
LLAMA_TQ_MTP="mtp-gemma-4-26B-A4B-it-Q8_0.gguf"

llama_tq_command() {
    printf '%s' "${1:-}./build/bin/llama-server --host 0.0.0.0 --port 8080 \
        --models-dir user-models --models-preset models.ini \
        --models-max 1 --models-autoload"
}

llama_tq_preset() {
    local FOLDER="$1"
    local FA="${2:-on}"

    podman exec -t rocm bash -c "cat > /AI/$FOLDER/models.ini << INIEOF
version = 1

[*]
c = 262144
n-gpu-layers = 999
flash-attn = $FA
cache-type-k = turbo3
cache-type-v = turbo3

[${LLAMA_TQ_MODEL%.gguf}]
model-draft = /AI/$FOLDER/drafts/$LLAMA_TQ_MTP
INIEOF"
}

llama_tq_models() {
    local FOLDER="$1"
    podman exec -it rocm bash -c "mkdir -p '/AI/$FOLDER/user-models' && \
        wget -q --show-progress -O '/AI/$FOLDER/user-models/$LLAMA_TQ_MODEL' \
            '$LLAMA_TQ_HF/$LLAMA_TQ_MODEL'"
    podman exec -it rocm bash -c "mkdir -p '/AI/$FOLDER/drafts' && \
        wget -q --show-progress -O '/AI/$FOLDER/drafts/$LLAMA_TQ_MTP' \
            '$LLAMA_TQ_HF/MTP/$LLAMA_TQ_MTP'"
}

install_llama_cpp_turboquant() {
    REPO="$LLAMA_TQ_REPO"
    COMMIT="$LLAMA_TQ_COMMIT"
    FOLDER="llama.cpp-turboquant"
    COMMAND="$(llama_tq_command 'GGML_CUDA_DISABLE_GRAPHS=1 ')"

    GPU_APP=1

    basic_container
    podman exec -t rocm bash -c "cd /AI && if [ -d $FOLDER ]; then rm -rf $FOLDER; fi"
    podman exec -it rocm bash -c "cd /AI && git clone $REPO $FOLDER && cd $FOLDER && git checkout $COMMIT"

    podman exec -it rocm bash -c "cd /AI/$FOLDER && \
        HIPCXX=\"\$(hipconfig -l)/clang\" HIP_PATH=\"\$(hipconfig -R)\" \
        cmake -S . -B build -DLLAMA_CURL=OFF -DGGML_HIP=ON \
            -DAMDGPU_TARGETS=\"\${TARGET_GFX_ALL:-\$TARGET_GFX}\" \
            -DCMAKE_BUILD_TYPE=Release && \
        cmake --build build --config Release -- -j\$((\$(nproc) - 1))"

    llama_tq_preset "$FOLDER" on
    llama_tq_models "$FOLDER"

    basic_run "$REPO" "$COMMAND" "&&" "$FOLDER"
}

install_llama_cpp_turboquant_vulkan() {
    REPO="$LLAMA_TQ_REPO"
    COMMIT="$LLAMA_TQ_COMMIT"
    FOLDER="llama.cpp-turboquant-vulkan"
    COMMAND="$(llama_tq_command)"

    GPU_APP=1

    basic_container
    podman exec -it rocm bash -c "apt-get install -y libvulkan-dev vulkan-tools glslc"
    podman exec -t rocm bash -c "cd /AI && if [ -d $FOLDER ]; then rm -rf $FOLDER; fi"
    podman exec -it rocm bash -c "cd /AI && git clone $REPO $FOLDER && cd $FOLDER && git checkout $COMMIT"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && \
        cmake -S . -B build -DLLAMA_CURL=OFF -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release && \
        cmake --build build --config Release -- -j\$((\$(nproc) - 1))"

    llama_tq_preset "$FOLDER" auto
    llama_tq_models "$FOLDER"

    basic_run "$REPO" "$COMMAND" "&&" "$FOLDER"
}

# ----- KoboldCPP -----

install_koboldcpp() {
    REPO="https://github.com/YellowRoseCx/koboldcpp-rocm"
    COMMIT="d31a4f28eba0e33b867dfcf803efd1dce0e5ce3d"
    COMMAND="DISPLAY=\\\$DISPLAY uv run koboldcpp.py"
    FOLDER=$(basename "$REPO")

    GPU_APP=1

    basic_container
    basic_git "$REPO" "$COMMIT"
    podman exec -t rocm bash -c "cd /AI/$FOLDER && \
        sed -i '/if args.checkforupdates:/,+1d' koboldcpp.py"
    basic_venv "$REPO"
    basic_requirements "$REPO"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && \
        make LLAMA_HIPBLAS=1 \
            GPU_TARGETS=\"\$(echo \"\${TARGET_GFX_ALL:-\$TARGET_GFX}\" | tr ';' ' ')\" \
            -j\$((\$(nproc) - 1))"
    basic_run "$REPO" "$COMMAND"
}

# ----- vLLM Gemma 4 -----

VLLM_ROCM_BASE="https://rocm.frameworks.amd.com/whl-multi-arch"
VLLM_ROCM_WHEEL="vllm-0.23.1.dev1%2Brocm7.14.0.g9ddef7117.d20260715-cp314-cp314-linux_x86_64.whl"
VLLM_ROCM_FLASH="flash_attn-2.8.3-py3-none-any.whl"
VLLM_ROCM_TORCH="2.11.0+rocm7.14.0"
VLLM_ROCM_TORCHVISION="0.26.0+rocm7.14.0"
VLLM_ROCM_TORCHAUDIO="2.11.0+rocm7.14.0"

VLLM_G4_TQ_REPO="https://github.com/0xSero/turboquant"
VLLM_G4_TQ_COMMIT="7ac9b8d165a3f7d5e6df33b0450bc1f88ec0d4d5"

vllm_rocm_family() {
    case "${TARGET_GFX:-gfx1100}" in
        gfx9*) echo cdna ;;
        *)     echo rdna ;;
    esac
}

vllm_rocm_install() {
    local FOLDER=$1
    local FAMILY
    FAMILY=$(vllm_rocm_family)

    podman cp "$SCRIPT_DIR/uv.toml" "rocm:/AI/$FOLDER/uv.toml"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install $(rocm_torch_spec "torch==$VLLM_ROCM_TORCH" \
            "torchvision==$VLLM_ROCM_TORCHVISION") 'torchaudio==$VLLM_ROCM_TORCHAUDIO'"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install $VLLM_ROCM_BASE/vllm-$FAMILY/flash-attn/$VLLM_ROCM_FLASH && \
        uv pip install $VLLM_ROCM_BASE/vllm-$FAMILY/vllm/$VLLM_ROCM_WHEEL"
}

install_vllm_gemma4() {
    REPO="$VLLM_G4_TQ_REPO"
    COMMIT="$VLLM_G4_TQ_COMMIT"

    case "${TARGET_GFX:-gfx1100}" in
        gfx1100|gfx1101|gfx1150|gfx1151|gfx1200|gfx1201|gfx942|gfx950) ;;
        *)
            echo "Error: the prebuilt vLLM ROCm wheel has no kernels for ${TARGET_GFX}."
            echo "Supported: gfx1100 gfx1101 gfx1150 gfx1151 gfx1200 gfx1201 gfx942 gfx950"
            echo "Building vLLM from source for this GPU would be needed instead."
            read -p "Press Enter to continue..."
            return 1
            ;;
    esac
    FOLDER="vllm-gemma4"

    GPU_APP=1

    local MODEL="/AI/models/gemma-4-31B-qat-W4A16-sym-g128"

    local SMI="/AI/$FOLDER/.venv/lib/python3.14/site-packages/_rocm_sdk_core/share/amd_smi"
    local SERVE="PYTHONPATH=$SMI TQ_KV_SHARE=1 TQ_VALUE_BITS=4 TQ_CAPACITY=262144 python tq_serve.py --model $MODEL --served-model-name gemma-4-31b --max-model-len 262144 --max-num-seqs 1 --max-num-batched-tokens 512 --kv-cache-memory-bytes 2200000000 --kv-cache-dtype fp8 --enforce-eager --no-enable-prefix-caching --enable-auto-tool-choice --tool-call-parser gemma4 --reasoning-parser gemma4 --default-chat-template-kwargs '{\\\"enable_thinking\\\":true}' --allowed-origins '[\\\"*\\\"]' --host 0.0.0.0 --port 8000"
    COMMAND="$SERVE"

    basic_container

    podman exec -it rocm bash -c "apt-get install -y libopenmpi40"
    podman exec -t rocm bash -c "
cat > /tmp/mpi_cxx_stub.cpp << 'EOF'
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

    podman exec -t rocm bash -c "cd /AI && if [ -d $FOLDER ]; then rm -rf $FOLDER; fi"
    podman exec -it rocm bash -c "cd /AI && git clone $REPO $FOLDER && cd $FOLDER && git checkout $COMMIT"

    basic_venv "$REPO" "3.14" "$FOLDER"
    vllm_rocm_install "$FOLDER"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install 'transformers==5.14.1'"

    podman cp "$SCRIPT_DIR/custom_files/vllm-gemma4/tq-sero-rocm-gemma4.patch" \
        "rocm:/AI/$FOLDER/tq-sero-rocm-gemma4.patch"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && git apply tq-sero-rocm-gemma4.patch"

    podman cp "$SCRIPT_DIR/custom_files/vllm-gemma4/tq_fused.py" \
        "rocm:/AI/$FOLDER/turboquant/fused.py"

    podman cp "$SCRIPT_DIR/custom_files/vllm-gemma4/tq_store.py" \
        "rocm:/AI/$FOLDER/turboquant/store.py"

    podman cp "$SCRIPT_DIR/custom_files/vllm-gemma4/tq_reqids_patch.py" \
        "rocm:/AI/$FOLDER/tq_reqids_patch.py"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        python tq_reqids_patch.py"

    podman cp "$SCRIPT_DIR/custom_files/vllm-gemma4/tq_serve.py" \
        "rocm:/AI/$FOLDER/tq_serve.py"
    podman cp "$SCRIPT_DIR/custom_files/vllm-gemma4/tq_multi.py" \
        "rocm:/AI/$FOLDER/tq_multi.py"

    if podman exec rocm test -f "$MODEL/config.json"; then
        echo "Quantized model already present, skipping."
    else
        podman exec -it rocm bash -c "cd /AI && mkdir -p gemma4-quant && cd gemma4-quant && uv venv --clear --python 3.12"
        podman cp "$SCRIPT_DIR/uv.toml" "rocm:/AI/gemma4-quant/uv.toml"
        podman exec -it rocm bash -c "cd /AI/gemma4-quant && source .venv/bin/activate && \
            uv pip install $(rocm_torch_spec torch)"
        podman exec -it rocm bash -c "cd /AI/gemma4-quant && source .venv/bin/activate && \
            uv pip install llmcompressor accelerate datasets"
        podman cp "$SCRIPT_DIR/custom_files/gemma4-quant/quantize_w4a16_sym.py" \
            "rocm:/AI/gemma4-quant/quantize_w4a16_sym.py"
        podman exec -it rocm bash -c "cd /AI/gemma4-quant && source .venv/bin/activate && \
            mkdir -p /AI/models && CUDA_VISIBLE_DEVICES= HIP_VISIBLE_DEVICES= \
            python quantize_w4a16_sym.py"
        if ! podman exec rocm test -f "$MODEL/config.json"; then
            echo "Error: quantization did not produce $MODEL."
            read -p "Press Enter to continue..."
            return 1
        fi
    fi

    basic_run "$REPO" "$COMMAND" "&& source .venv/bin/activate &&" "$FOLDER"
}

# ----- Fine-tuning -----

# Unsloth
install_unsloth() {
    FOLDER="unsloth"
    COMMAND="unsloth studio -p 8888 -H 0.0.0.0"

    GPU_APP=1
    basic_container

    podman exec -t rocm bash -c "if [ -d /AI/$FOLDER ]; then rm -rf /AI/$FOLDER; fi && mkdir -p /AI/$FOLDER"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && uv venv --python 3.12"

    podman cp "$SCRIPT_DIR/uv.toml" "rocm:/AI/$FOLDER/uv.toml"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install $(rocm_torch_spec torch torchvision) && uv pip install unsloth"

    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        curl -fsSL https://unsloth.ai/install.sh -o /tmp/unsloth_install.sh && \
        printf 'n\n' | sh /tmp/unsloth_install.sh --no-torch --skip-autostart --python /AI/$FOLDER/.venv/bin/python; \
        rm -f /tmp/unsloth_install.sh"

    basic_run "unsloth" "$COMMAND" "&&"
}

# SillyTavern
install_sillytavern(){
    REPO="https://github.com/SillyTavern/SillyTavern"
    COMMIT="8172dcd0ee672d3cd9a5e5f7af134f91a45cd2b8"
    COMMAND="bash start.sh"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_run "$REPO" "$COMMAND" "&&"

    podman exec -t rocm bash -c "cd $FOLDER/default && sed -i 's/listen: false/listen: true/' config.yaml"
    podman exec -t rocm bash -c "cd $FOLDER/default && sed -i 's/whitelistMode: true/whitelistMode: false/' config.yaml"
    podman exec -t rocm bash -c "cd $FOLDER/default && sed -i 's/basicAuthMode: false/basicAuthMode: true/' config.yaml"
}

_COMFY_DL_QUEUE=()

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

    for (( i=0; i<n; i++ )); do
        ( podman exec -i rocm bash -c \
            "wget -q -P \"${dirs[$i]}\" \"${urls[$i]}\""; echo $? > "$tmpdir/s$i" ) &
    done

    local -a spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local si=0 bar_width=40
    local -a done_flags=() statuses=()
    for (( i=0; i<n; i++ )); do done_flags[$i]=0; statuses[$i]=0; done

    local stat_cmd=""
    for (( i=0; i<n; i++ )); do
        stat_cmd+="stat -c%s '${destpaths[$i]}' 2>/dev/null || echo 0; "
    done

    printf "\n  Downloading %d file(s) simultaneously...\n\n" "$n"

    local first=1
    while true; do
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

        local downloaded=0
        local -a cur=()
        while IFS= read -r line; do
            line=$(tr -d '[:space:]' <<< "$line")
            [[ "$line" =~ ^[0-9]+$ ]] || line=0
            cur+=("$line")
            downloaded=$(( downloaded + line ))
        done < <(podman exec -i rocm bash -c "$stat_cmd" 2>/dev/null)
        while (( ${#cur[@]} < n )); do cur+=(0); done

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
    REPO="https://github.com/Comfy-Org/ComfyUI"
    COMMIT="bf4c9a08fc854df6d3b2bef1b92b509e2ef2d2c9"
    TUNABLEOP=""
    COMMAND="PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512 TORCH_BLAS_PREFER_HIPBLASLT=1 $TUNABLEOP uv run main.py --listen 0.0.0.0 --enable-dynamic-vram --enable-manager --preview-method auto --dont-upcast-attention --bf16-vae --use-pytorch-cross-attention --reserve-vram 2.0"
    FOLDER=$(basename "$REPO")
    ADDONS="$@"

    GPU_APP=1
    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"

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

    podman exec -t rocm bash -c "python3 - << 'PYEOF'
import pathlib
path = next(pathlib.Path('/AI/$FOLDER/.venv/lib').glob('python3.*/site-packages/torchaudio/_torchcodec.py'))
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

    podman exec -it rocm bash -c "cd /AI/$FOLDER/custom_nodes && git clone https://github.com/city96/ComfyUI-GGUF && cd ComfyUI-GGUF && git checkout 6ea2651e7df66d7585f6ffee804b20e92fb38b8a"

    if [[ "$ADDONS" == *"1"* ]] || [[ "$ADDONS" == *"2"* ]]; then
        comfy_download "$FOLDER/models/vae/" "https://huggingface.co/Comfy-Org/z_image_turbo" "d24c4cf2a0cd98a42f23467e27e3d76ee9438b8e" "split_files/vae/ae.safetensors"
        comfy_download "$FOLDER/models/text_encoders/" "https://huggingface.co/SeeSee21/Z-Anime" "0f5fb51464638a2f7328a1d74590281e63e1fde2" "text_encoder/qwen_3_4b-bf16.safetensors"
    fi

    if [[ "$ADDONS" == *"1"* ]]; then
        comfy_download "$FOLDER/models/diffusion_models/" "https://huggingface.co/Comfy-Org/z_image_turbo" "d24c4cf2a0cd98a42f23467e27e3d76ee9438b8e" "split_files/diffusion_models/z_image_turbo_bf16.safetensors"
    fi

    if [[ "$ADDONS" == *"2"* ]]; then
        comfy_download "$FOLDER/models/diffusion_models/" "https://huggingface.co/SeeSee21/Z-Anime" "0f5fb51464638a2f7328a1d74590281e63e1fde2" "diffusion_models/z-anime-distill-4step-bf16.safetensors"
    fi

    if [[ "$ADDONS" == *"3"* ]]; then
        WAN_REPO="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged"
        WAN_COMMIT="fb1388adc906ab39ffc26ee40e96b22886b56bc4"
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
    COMMIT="6d467e4b5081ccb0abf1ec1bf4fdf9051a2d34b0"
    COMMAND="ACESTEP_LM_BACKEND=pt MIOPEN_FIND_MODE=FAST python -m acestep.acestep_v15_pipeline --server-name 0.0.0.0 --port 7860 --config_path acestep-v15-turbo --lm_model_path acestep-5Hz-lm-4B --init_service true --backend pt"
    FOLDER=$(basename "$REPO")

    GPU_APP=1
    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"

    podman cp "$SCRIPT_DIR/custom_files/ACE-Step-1.5/generation_advanced_output_controls.py" \
        "rocm:/AI/$FOLDER/acestep/ui/gradio/interfaces/generation_advanced_output_controls.py"

    podman exec -t rocm bash -c "python3 - << 'PYEOF'
import pathlib
path = next(pathlib.Path('/AI/$FOLDER/.venv/lib').glob('python3.*/site-packages/torchaudio/_torchcodec.py'))
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

# Soprano
install_soprano(){
    REPO="https://github.com/Mateusz-Dera/soprano-rocm"
    COMMIT="e4b3dd66641cc22c8f97f167ad1bfd75e04292e5"
    COMMAND="PYTHONPATH=/AI/soprano-rocm/.venv/lib/python3.14/site-packages/_rocm_sdk_core/share/amd_smi TORCH_BLAS_PREFER_HIPBLASLT=1 soprano-webui --backend vllm"
    FOLDER=$(basename "$REPO")

    GPU_APP=1
    basic_container
    podman exec -it rocm bash -c "apt-get install -y libopenmpi40"
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
    basic_venv "$REPO"

    vllm_rocm_install "$FOLDER"

    basic_requirements "$REPO"

    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install -e ."

    basic_run "$REPO" "$COMMAND"
}

# OmniVoice
install_omnivoice(){
    REPO="https://github.com/k2-fsa/OmniVoice"
    COMMIT="38e992bc60f85548faeb77e8fa70158ba71deb30"
    COMMAND="omnivoice-demo --ip 0.0.0.0 --port 7860"
    FOLDER=$(basename "$REPO")

    GPU_APP=1
    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && uv pip install --no-deps  -e ."

    podman exec -t rocm bash -c "python3 - << 'PYEOF'
import glob
path = glob.glob('/AI/$FOLDER/.venv/lib/python3.*/site-packages/torchaudio/_torchcodec.py')[0]
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

    podman exec -t rocm bash -c "sed -i 's/dtype=torch\.float16/dtype=torch.float32/' /AI/$FOLDER/omnivoice/cli/demo.py"

    basic_run "$REPO" "$COMMAND"
}

# Parakeet
install_parakeet(){
    FOLDER="parakeet"
    COMMAND="python app.py --ip 0.0.0.0 --port 7860"

    GPU_APP=1
    basic_container

    podman exec -t rocm bash -c "rm -rf /AI/$FOLDER && mkdir -p /AI/$FOLDER"
    podman cp "$SCRIPT_DIR/custom_files/parakeet/app.py" "rocm:/AI/$FOLDER/app.py"

    basic_venv "$FOLDER" "3.13"
    basic_requirements "$FOLDER"

    basic_run "$FOLDER" "$COMMAND"
}

# PartCrafter
install_partcrafter(){
    REPO="https://github.com/wgsxm/PartCrafter"
    COMMIT="3d773bf02fad51c7ab31a5615573fec93b287b30"
    COMMAND="uv run partcrafter_webui.py"
    FOLDER=$(basename "$REPO")

    GPU_APP=1
    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"

    podman cp "$SCRIPT_DIR/custom_files/partcrafter/inference_partcrafter.py" "rocm:/AI/$FOLDER/scripts/inference_partcrafter.py"
    podman cp "$SCRIPT_DIR/custom_files/partcrafter/render_utils.py" "rocm:/AI/$FOLDER/src/utils/render_utils.py"
    podman cp "$SCRIPT_DIR/custom_files/partcrafter/partcrafter_webui.py" "rocm:/AI/$FOLDER/partcrafter_webui.py"
    podman cp "$SCRIPT_DIR/custom_files/partcrafter/autoencoder_kl_triposg.py" "rocm:/AI/$FOLDER/src/models/autoencoders/autoencoder_kl_triposg.py"

    basic_requirements "$REPO" 

    podman exec -it rocm bash -c "cd /AI/$FOLDER && git clone https://github.com/Mateusz-Dera/pytorch_cluster_rocm && cd pytorch_cluster_rocm && git checkout 6be490d08df52755684b7ccfe10d55463070f13d"
    podman exec -it rocm bash -c "cd /AI/$FOLDER/pytorch_cluster_rocm && rm -rf requirements.txt && touch requirements.txt && source ../.venv/bin/activate && uv pip install ."

    basic_run "$REPO" "$COMMAND"
}

# ----- trellis.cpp -----

TRELLIS_CPP_REPO="https://github.com/pwilkin/trellis.cpp"
TRELLIS_CPP_COMMIT="1f2e1e71bef9a7a933d504dd3f9b64cba8556d91"
TRELLIS_CPP_HF="ilintar/trellis2-gguf"
TRELLIS_CPP_DIR="/AI/trellis.cpp"
TRELLIS_CPP_MODELS="/AI/trellis2-gguf"
TRELLIS_CPP_PORT="8081"

trellis_cpp_ask_weights() {
    whiptail --title "trellis.cpp weights" --radiolist \
        "Which weight set to download?" 14 72 3 \
        "q8"   "10.0 GB - default"          ON \
        "full" "16.5 GB - bf16/f16 originals" OFF \
        "q4"   "6.5 GB - smallest"          OFF \
        3>&1 1>&2 2>&3
}

install_trellis_cpp() {
    local BACKEND="${1:-vulkan}"
    local BUILD_DIR RUN_LAUNCH WEIGHTS
    FOLDER="trellis.cpp"

    if [ "$BACKEND" = "hip" ]; then
        BUILD_DIR="build-hip"
    else
        BACKEND="vulkan"
        BUILD_DIR="build-vulkan"
    fi

    if [ -n "${TRELLIS_CPP_WEIGHTS:-}" ]; then
        WEIGHTS="$TRELLIS_CPP_WEIGHTS"
    else
        WEIGHTS=$(trellis_cpp_ask_weights) || return 0
    fi
    [ -z "$WEIGHTS" ] && return 0

    GPU_APP=1
    basic_container

    podman exec -it rocm bash -c "cd /AI && \
        if [ ! -d $FOLDER/.git ]; then \
            git clone $TRELLIS_CPP_REPO $FOLDER; \
        fi && \
        cd $FOLDER && git fetch --all && git checkout $TRELLIS_CPP_COMMIT && \
        git submodule update --init --recursive"

    if [ "$BACKEND" = "hip" ]; then
        podman exec -it rocm bash -c "cd $TRELLIS_CPP_DIR && \
            export ROCM_PATH=/opt/rocm PATH=/opt/rocm/bin:\$PATH && \
            cmake -B $BUILD_DIR -DCMAKE_BUILD_TYPE=Release -DGGML_HIP=ON \
                -DAMDGPU_TARGETS=\"${TARGET_GFX_ALL:-${TARGET_GFX:-}}\" && \
            cmake --build $BUILD_DIR -j\$(nproc)"
    else
        podman exec -it rocm bash -c "cd $TRELLIS_CPP_DIR && \
            cmake -B $BUILD_DIR -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON && \
            cmake --build $BUILD_DIR -j\$(nproc)"
    fi

    local HF_FILTER FLATTEN
    if [ "$WEIGHTS" = "full" ]; then
        HF_FILTER="--include '*.gguf' --exclude 'q4/*' 'q8/*'"
        FLATTEN="true"
    else
        HF_FILTER="--include '$WEIGHTS/*'"
        FLATTEN="mv $TRELLIS_CPP_MODELS/$WEIGHTS/*.gguf $TRELLIS_CPP_MODELS/ && rmdir $TRELLIS_CPP_MODELS/$WEIGHTS"
    fi
    podman exec -it rocm bash -c "if [ ! -f $TRELLIS_CPP_MODELS/ss_flow.gguf ]; then \
        hf download $TRELLIS_CPP_HF --local-dir $TRELLIS_CPP_MODELS $HF_FILTER && $FLATTEN; \
      else echo 'trellis.cpp weights already present - reusing'; fi"

    local GPU_IDX
    GPU_IDX=$(printf '%s' "${GPU_CLAUSE:-}" | grep -oE 'HIP_VISIBLE_DEVICES=[0-9]+' | grep -oE '[0-9]+$')

    if [ "$BACKEND" = "hip" ]; then
        RUN_LAUNCH="cd $TRELLIS_CPP_DIR && export ROCM_PATH=/opt/rocm GGML_CUDA_DISABLE_GRAPHS=1 && mkdir -p output"
    else
        RUN_LAUNCH="cd $TRELLIS_CPP_DIR && export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json \
GGML_VK_VISIBLE_DEVICES=${GPU_IDX:-0} && mkdir -p output"
    fi
    RUN_LAUNCH="$RUN_LAUNCH && ./$BUILD_DIR/trellis-server --models $TRELLIS_CPP_MODELS --host 0.0.0.0 --port $TRELLIS_CPP_PORT"

    COMMAND="$RUN_LAUNCH"
    basic_run "$TRELLIS_CPP_REPO" "$COMMAND" "&&"
}

# ARDY
install_ardy() {
    REPO="https://github.com/nv-tlabs/ardy"
    COMMIT="693f74d13b3d04a0a22ce127ee79c929dd89756b"
    FOLDER=$(basename "$REPO")

    GPU_APP=1
    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO" "3.11"

    podman cp "$SCRIPT_DIR/uv.toml" "rocm:/AI/$FOLDER/uv.toml"

    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install -e '.[demo]'"

    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install --reinstall $(rocm_torch_spec torch torchvision) && uv pip install 'numpy<2'"

    podman exec -t rocm bash -c "chown -R root:root /AI/$FOLDER/ 2>/dev/null || true"

    podman exec -t rocm bash -c "cat > /AI/$FOLDER/run.sh << 'RUNEOF'
#!/bin/bash
if ! podman ps -a --format '{{.Names}}' | grep -q '^rocm\$'; then
    echo 'Error: Container rocm does not exist.'
    exit 1
fi
if ! podman ps --format '{{.Names}}' | grep -q '^rocm\$'; then
    echo 'Container rocm is not running. Starting...'
    podman start rocm
fi
podman exec -t rocm bash -c 'chown -R root:root /AI/ardy/ 2>/dev/null || true'
podman exec -it rocm bash -c 'cd /AI/ardy ${GPU_CLAUSE:-} && source .venv/bin/activate && \
    export PYTORCH_HIP_ALLOC_CONF=expandable_segments:True && \
    { python scripts/run_text_encoder_server.py --device cpu & } && \
    sleep 20 && python scripts/run_demo.py'
podman exec -t rocm bash -c 'chown -R root:root /AI/ardy/ 2>/dev/null || true'
RUNEOF
chmod +x /AI/$FOLDER/run.sh"
}

# TripoSplat
install_triposplat(){
    REPO="https://github.com/VAST-AI-Research/TripoSplat"
    COMMIT="a78fa12d06dbf1381ca548bfac32bb68cb8c451d"
    COMMAND="python run_gradio.py"
    FOLDER=$(basename "$REPO")

    GPU_APP=1
    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"
    basic_run "$REPO" "$COMMAND"

    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && hf download VAST-AI/TripoSplat --local-dir ckpts/ --exclude 'vae/triposplat_vae_encoder_fp16.safetensors'"

    triposplat_vendor_viewer "$FOLDER"
}

triposplat_vendor_viewer() {
    local folder="$1"
    local three="https://cdnjs.cloudflare.com/ajax/libs/three.js/0.180.0"
    local unpkg="https://unpkg.com"

    podman exec -t rocm bash -c "cd /AI/${folder}/static/viewer && mkdir -p vendor/controls && \
        wget -q -O vendor/three.module.js ${three}/three.module.js && \
        wget -q -O vendor/three.core.js ${three}/three.core.js && \
        wget -q -O vendor/controls/OrbitControls.js ${unpkg}/three@0.180.0/examples/jsm/controls/OrbitControls.js && \
        wget -q -O vendor/spark.module.js ${unpkg}/@sparkjsdev/spark@2.0.0/dist/spark.module.js && \
        sed -i 's#${three}/three.module.js#./vendor/three.module.js#; \
                s#${unpkg}/three@0.180.0/examples/jsm/#./vendor/#; \
                s#${unpkg}/@sparkjsdev/spark@2.0.0/dist/spark.module.js#./vendor/spark.module.js#' viewer.html"

    if podman exec -t rocm bash -c "sed -n '/<script type=\"importmap\">/,/<\/script>/p' /AI/${folder}/static/viewer/viewer.html | grep -q 'https\?://'"; then
        echo "Error: the TripoSplat viewer still points at a remote host."
        return 1
    fi
}

# AutoRemesher
install_autoremesher() {
    REPO="https://github.com/huxingyi/autoremesher"
    COMMIT="525acf5c156120257383a5cb8a7d13cdedaf4c42"
    FOLDER=$(basename "$REPO")

    basic_container

    podman exec -t rocm bash -c "apt-get update && apt-get install -y \
        qt5-qmake qtbase5-dev qttools5-dev-tools libqt5svg5-dev libqt5opengl5-dev \
        libtbb-dev libgl1-mesa-dev"

    basic_git "$REPO" "$COMMIT"

    podman exec -it rocm bash -c "cd /AI/$FOLDER && qmake && make -j\$(nproc)"

    local RUNSH
    RUNSH=$(mktemp)
    cat > "$RUNSH" << 'RUNEOF'
#!/bin/bash
if ! podman ps -a --format '{{.Names}}' | grep -q '^rocm$'; then
    echo 'Error: Container rocm does not exist.'
    exit 1
fi
if ! podman ps --format '{{.Names}}' | grep -q '^rocm$'; then
    echo 'Container rocm is not running. Starting...'
    podman start rocm
fi
command -v xhost >/dev/null 2>&1 && xhost +local: >/dev/null 2>&1 || true
podman exec -it rocm bash -c "cd /AI/autoremesher && ./autoremesher"
RUNEOF
    podman cp "$RUNSH" "rocm:/AI/$FOLDER/run.sh"
    podman exec -t rocm bash -c "chmod +x /AI/$FOLDER/run.sh"
    rm -f "$RUNSH"
}

# Krea 2 Turbo
install_krea2() {
    FOLDER="Krea-2-Turbo"
    COMMAND="PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512 TORCH_BLAS_PREFER_HIPBLASLT=1 python app.py"

    GPU_APP=1
    basic_container

    podman exec -t rocm bash -c "if [ -d /AI/$FOLDER ]; then rm -rf /AI/$FOLDER; fi && mkdir -p /AI/$FOLDER/loras"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && uv venv --python 3.14"

    podman cp "$SCRIPT_DIR/uv.toml" "rocm:/AI/$FOLDER/uv.toml"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install $(rocm_torch_spec torch torchvision)"

    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install 'git+https://github.com/huggingface/diffusers' \
        'transformers>=4.57.0' accelerate sentencepiece bitsandbytes peft gradio"

    podman cp "$SCRIPT_DIR/custom_files/Krea-2-Turbo/app.py" "rocm:/AI/$FOLDER/app.py"

    basic_run "$FOLDER" "$COMMAND"
}

# Backup and Restore Manager
run_backup() {
    bash "$SCRIPT_DIR/backup.sh"
}
