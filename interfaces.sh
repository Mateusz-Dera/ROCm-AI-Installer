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

# ----- llama.cpp -----

LLAMA_REPO="https://github.com/ggml-org/llama.cpp"
LLAMA_COMMIT="da296d6e726654949bce10d7cae9a2195d292bfc"

install_llama_cpp() {
    REPO="$LLAMA_REPO"
    COMMIT="$LLAMA_COMMIT"
    FOLDER=$(basename "$REPO")
    # Router server: serve every GGUF in models/ and switch between them from the
    # WebUI model selector (or the OpenAI `model` field) without a restart.
    # --models-max 1 keeps a single model resident (loading another unloads the LRU
    # one, freeing VRAM). Inference args below apply to whichever model is loaded.
    COMMAND="./build/bin/llama-server --models-dir user-models --models-max 1 --models-autoload --host 0.0.0.0 --port 8080 -c 131072 -ngl auto -fa on --cache-type-k q8_0 --cache-type-v q8_0"

    local HF_REPO="https://huggingface.co/unsloth/gemma-4-12b-it-GGUF"
    local MODEL_FILE="gemma-4-12b-it-Q8_0.gguf"

    basic_container
    basic_git "$REPO" "$COMMIT"
    PODMAN='HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" cmake -S . -B build -DLLAMA_CURL=OFF -DGGML_HIP=ON -DAMDGPU_TARGETS=$GFX -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release -- -j$(($(nproc) - 1))'
    podman exec -it rocm bash -c "cd /AI/$FOLDER && $PODMAN"

    # Default model goes into models/ so the router lists it; drop more GGUFs there
    # to pick them from the WebUI.
    podman exec -it rocm bash -c "mkdir -p '/AI/$FOLDER/user-models' && wget -q '${HF_REPO}/resolve/main/${MODEL_FILE}' -O '/AI/$FOLDER/user-models/${MODEL_FILE}'"

    basic_run "$REPO" "$COMMAND" "&&"
}

install_llama_cpp_vulkan() {
    REPO="$LLAMA_REPO"
    COMMIT="$LLAMA_COMMIT"
    FOLDER="llama.cpp-vulkan"
    # Router server (see install_llama_cpp): pick/switch models from the WebUI.
    COMMAND="./build/bin/llama-server --models-dir user-models --models-max 1 --models-autoload --host 0.0.0.0 --port 8080 -c 131072 -ngl auto -fa on --cache-type-k q8_0 --cache-type-v q8_0"

    local HF_REPO="https://huggingface.co/unsloth/gemma-4-12b-it-GGUF"
    local MODEL_FILE="gemma-4-12b-it-Q8_0.gguf"

    basic_container
    podman exec -it rocm bash -c "apt-get install -y libvulkan-dev vulkan-tools glslc"
    podman exec -t rocm bash -c "cd /AI && if [ -d $FOLDER ]; then rm -rf $FOLDER; fi"
    podman exec -it rocm bash -c "cd /AI && git clone $REPO $FOLDER && cd $FOLDER && git checkout $COMMIT"
    PODMAN='cmake -S . -B build -DLLAMA_CURL=OFF -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release -- -j$(($(nproc) - 1))'
    podman exec -it rocm bash -c "cd /AI/$FOLDER && $PODMAN"

    podman exec -it rocm bash -c "mkdir -p '/AI/$FOLDER/user-models' && wget -q '${HF_REPO}/resolve/main/${MODEL_FILE}' -O '/AI/$FOLDER/user-models/${MODEL_FILE}'"

    basic_run "$REPO" "$COMMAND" "&&" "$FOLDER"
}

# ----- turboquant-rocm-llamacpp -----

LLAMA_TQ_REPO="https://github.com/jagsan-cyber/turboquant-rocm-llamacpp"
LLAMA_TQ_COMMIT="22cce31b6e58f3e945fbc7f2f5eb06a509e64fcc"

install_turboquant_rocm_llamacpp() {
    REPO="$LLAMA_TQ_REPO"
    COMMIT="$LLAMA_TQ_COMMIT"
    FOLDER=$(basename "$REPO")
    # Router server (see install_llama_cpp): pick/switch models from the WebUI. Keeps
    # TurboQuant's q4_0 KV-cache compression as the global cache type.
    COMMAND="./build/bin/llama-server --models-dir user-models --models-max 1 --models-autoload --host 0.0.0.0 --port 8080 -c 131072 --flash-attn on --cache-type-k q4_0 --cache-type-v q4_0 -ngl 99"

    local HF_REPO="https://huggingface.co/unsloth/gemma-4-12b-it-GGUF"
    local MODEL_FILE="gemma-4-12b-it-Q8_0.gguf"

    basic_container
    basic_git "$REPO" "$COMMIT"
    PODMAN='HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" cmake -S . -B build -DLLAMA_CURL=OFF -DGGML_HIP=ON -DAMDGPU_TARGETS=$GFX -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release -- -j$(($(nproc) - 1))'
    podman exec -it rocm bash -c "cd /AI/$FOLDER && $PODMAN"

    podman exec -it rocm bash -c "mkdir -p '/AI/$FOLDER/user-models' && wget -q '${HF_REPO}/resolve/main/${MODEL_FILE}' -O '/AI/$FOLDER/user-models/${MODEL_FILE}'"

    basic_run "$REPO" "$COMMAND" "&&"
}

# ----- vLLM Gemma 4 -----

# Gemma 4 31B on a 24 GB card with a compressed KV cache: 150k tokens in one
# session, or two concurrent sessions of 150k each, with full needle recall at
# five depths. Plain fp8 KV fits 111k on the same card.
#
# The saving comes from compressing only the ten full-attention layers. Gemma 4
# cycles five sliding layers per full one, and a sliding layer's KV is capped by
# its 1024-token window, so it does not grow with context and there is nothing
# to win there - compressing it only breaks the window. The full layers are the
# ones whose cache grows, and they are also unusually cheap to compress here:
# they have no v_proj at all (verified on the checkpoint - 60 layers carry
# k_proj, 50 carry v_proj, and the ten without are exactly the full-attention
# ones), so K and V come from one projection. The store keeps V alone and
# rebuilds K on read, which halves it again. Net: 7.5 KB/token against fp8's
# 51.6 for those layers.
#
# This uses 0xSero/turboquant, a pure PyTorch+Triton plugin that hooks the
# runner, NOT TheTom's vLLM fork. The fork's approach - marking layers through
# --kv-cache-dtype-skip-layers - makes the per-layer KV specs non-uniform, and
# vLLM then rewrites every SlidingWindowSpec into a FullAttentionSpec, so the
# 50 windowed layers stop being capped and the cache jumps to ~596 KB/token.
# Isolated cleanly: fp8 with the skip list engaged could not fit 50 000 tokens
# where fp8 without it fit 57 337, same dtype on every layer.
#
# vLLM comes from the prebuilt ROCm wheel rather than a source build: same
# engine, no ~40 minute compile.
VLLM_G4_INDEX="https://wheels.vllm.ai/rocm/"
VLLM_G4_VLLM="0.26.0+rocm723"
VLLM_G4_TQ_REPO="https://github.com/0xSero/turboquant"
VLLM_G4_TQ_COMMIT="7ac9b8d165a3f7d5e6df33b0450bc1f88ec0d4d5"

install_vllm_gemma4() {
    REPO="$VLLM_G4_TQ_REPO"
    COMMIT="$VLLM_G4_TQ_COMMIT"
    FOLDER="vllm-gemma4"

    # gemma-4-31B as 4-bit W4A16 compressed-tensors, quantized locally further
    # down. Every published 4-bit Gemma 4 is a worse trade on a 24 GiB card:
    #   ebircak/...-GPTQ            19.2 GB  asymmetric, group 128
    #   google/...-qat-w4a16-ct     23.3 GB  group 32 + untied lm_head -> 576 (!)
    #   ours                        17.9 GB  symmetric, group 128
    # The 1.3 GB saved over ebircak is all KV cache, which is why the context
    # goes up for the same card.
    local MODEL="/AI/models/gemma-4-31B-it-W4A16-sym-g128"

    # Settings that are load-bearing, each measured:
    #   --max-model-len 262000     sizes the KV pool: vLLM requires the pool to
    #                              hold this many tokens for one request, so it
    #                              scales pool capacity. Setting it near the
    #                              prompt length instead cost 40% of the pool
    #                              (104000 -> 179 952 tokens, 262000 -> 300 410)
    #                              and forced the scheduler to serialise the two
    #                              sessions. It is a per-request cap, so raising
    #                              it does not force sessions to be longer.
    #                              Ceiling is the model's own 262 144 positions.
    #   --max-num-seqs 2           two concurrent sessions, verified isolated.
    #   --max-num-batched-tokens   512 is the measured optimum; 768 and 1024
    #                              fail on prefill activations.
    #   --kv-cache-memory-bytes    caps the pool explicitly. Sizing it from
    #                              --gpu-memory-utilization leaves nothing for
    #                              long-context attention scratch and the engine
    #                              dies on the first big prompt though it booted.
    #   --enforce-eager            graph capture does not fit beside ~18 GiB of
    #                              weights.
    #   --no-enable-prefix-caching REQUIRED, not a preference. A prefix-cache hit
    #                              skips the forward pass, so the plugin never
    #                              captures and its store stays empty - the model
    #                              then answers with no context at all. Silent
    #                              wrong answers, not an error.
    # TQ_KV_SHARE=1 rebuilds K from the shared projection (halves the store).
    # expandable_segments keeps long-context prefill from dying of fragmentation.
    local SERVE="HIP_VISIBLE_DEVICES=0 TQ_KV_SHARE=1 PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True python tq_serve.py --model $MODEL --served-model-name gemma-4-31b --max-model-len 262000 --max-num-seqs 2 --max-num-batched-tokens 512 --kv-cache-memory-bytes 2200000000 --kv-cache-dtype fp8 --enforce-eager --no-enable-prefix-caching --allowed-origins '[\"*\"]' --host 0.0.0.0 --port 8000"
    # Two-pane chat in front of the API on :8080 - vLLM ships no UI of its own.
    COMMAND="python -m http.server 8080 --directory demo >/dev/null 2>&1 & $SERVE"

    basic_container

    # libmpi_cxx.so.40: OpenMPI 4.x dropped the C++ bindings but the torch builds
    # on the vLLM index still link against them. Same stub as install_soprano.
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

    # The plugin is imported from the working directory, so it is cloned as the
    # app folder itself rather than into a subdirectory.
    podman exec -t rocm bash -c "cd /AI && if [ -d $FOLDER ]; then rm -rf $FOLDER; fi"
    podman exec -it rocm bash -c "cd /AI && git clone $REPO $FOLDER && cd $FOLDER && git checkout $COMMIT"

    # vllm 0.26 on the ROCm index is cp312 only, and so is the torch there.
    basic_venv "$REPO" "3.12" "$FOLDER"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install --index-strategy unsafe-best-match --extra-index-url $VLLM_G4_INDEX \
        'vllm==$VLLM_G4_VLLM' 'torch==2.11.0' 'torchvision==0.24.1+d801a34' 'triton==3.6.0'"

    # Everything that makes the plugin work on Gemma 4 / ROCm. Upstream runs
    # neither: prefill ignored history, a fallback returned literal zeros,
    # chunked prefill dropped tokens, decode double-counted the current token,
    # and every concurrent session after the first read the first one's history.
    # The patch also adds turboquant/fused.py - one Triton kernel doing
    # dequantise + RMSNorm + RoPE, which nearly doubled decode speed (6.5 ->
    # 12.2 tok/s at 32k). Full account in .images/VLLM.md.
    podman cp "$SCRIPT_DIR/custom_files/vllm-gemma4/tq-sero-rocm-gemma4.patch" \
        "rocm:/AI/$FOLDER/tq-sero-rocm-gemma4.patch"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && git apply tq-sero-rocm-gemma4.patch"

    # The fused kernel ships as a file rather than inside the patch, so it stays
    # readable and editable in the repo instead of existing twice.
    podman cp "$SCRIPT_DIR/custom_files/vllm-gemma4/tq_fused.py" \
        "rocm:/AI/$FOLDER/turboquant/fused.py"

    # vllm serve cannot be used directly: the plugin installs its hooks through
    # enable_no_alloc(), which has to run in the serving process before the model
    # is built. tq_serve.py does that and then hands over to vLLM's own server,
    # so every serve flag still works.
    podman cp "$SCRIPT_DIR/custom_files/vllm-gemma4/tq_serve.py" \
        "rocm:/AI/$FOLDER/tq_serve.py"
    podman exec -t rocm bash -c "mkdir -p /AI/$FOLDER/demo"
    podman cp "$SCRIPT_DIR/custom_files/vllm-gemma4/demo/index.html" \
        "rocm:/AI/$FOLDER/demo/index.html"
    # Acceptance test. Keep it: five of the concurrency bugs produced answers
    # that looked correct, and only a run with a separate code alphabet per
    # session plus the peak-store counter distinguishes real isolation from a
    # shared store or from sessions the scheduler quietly serialised.
    podman cp "$SCRIPT_DIR/custom_files/vllm-gemma4/tq_multi.py" \
        "rocm:/AI/$FOLDER/tq_multi.py"

    # Build the 4-bit checkpoint. No published Gemma 4 has the combination we
    # need (symmetric, group 128, embeddings left tied), so it is quantized here
    # from the bf16 release. Needs ~63 GB of download, ~50 GB of RAM and ~18 GB
    # of output; llm-compressor gets its own venv because it pins
    # transformers<=5.10.1, older than the one vLLM runs on.
    # RTN, not GPTQ: no calibration set, and it stays on the CPU, so it does not
    # evict a running server from the GPU. Pass --gptq for a slower, more
    # accurate pass.
    if podman exec rocm test -f "$MODEL/config.json"; then
        echo "Quantized model already present, skipping."
    else
        podman exec -it rocm bash -c "cd /AI && mkdir -p gemma4-quant && cd gemma4-quant && uv venv --python 3.12"
        podman exec -it rocm bash -c "cd /AI/gemma4-quant && source .venv/bin/activate && \
            uv pip install --index-strategy unsafe-best-match --extra-index-url $VLLM_G4_INDEX \
            'torch==2.11.0' 'triton==3.6.0'"
        podman exec -it rocm bash -c "cd /AI/gemma4-quant && source .venv/bin/activate && \
            uv pip install llmcompressor accelerate datasets"
        podman cp "$SCRIPT_DIR/custom_files/gemma4-quant/quantize_w4a16_sym.py" \
            "rocm:/AI/gemma4-quant/quantize_w4a16_sym.py"
        podman exec -it rocm bash -c "cd /AI/gemma4-quant && source .venv/bin/activate && \
            mkdir -p /AI/models && CUDA_VISIBLE_DEVICES= HIP_VISIBLE_DEVICES= \
            python quantize_w4a16_sym.py"
    fi

    basic_run "$REPO" "$COMMAND" "&& source .venv/bin/activate &&" "$FOLDER"
}

# ----- Fine-tuning -----

# Unsloth - LoRA/QLoRA/full fine-tuning + RL for LLMs, 2x faster / 70% less VRAM,
# with production-ready AMD/ROCm support (full RDNA3/gfx1100). Ships Unsloth Studio,
# a web UI for training and inference. CLI: unsloth train/inference/chat/export.
install_unsloth() {
    FOLDER="unsloth"
    # Studio web UI on 0.0.0.0:8888 like every other app. Adding -H 0.0.0.0 exposes
    # the raw port to the LAN (the Studio prints an API key on start for tool access).
    COMMAND="export HSA_OVERRIDE_GFX_VERSION=\$HSA_OVERRIDE_GFX_VERSION; unsloth studio -p 8888 -H 0.0.0.0"

    basic_container

    podman exec -t rocm bash -c "if [ -d /AI/$FOLDER ]; then rm -rf /AI/$FOLDER; fi && mkdir -p /AI/$FOLDER"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && uv venv --python 3.12"

    # ROCm torch first (uv.toml -> ROCm manylinux index), then unsloth. unsloth pulls
    # ROCm-aware triton/xformers automatically on this torch.
    podman cp "$SCRIPT_DIR/uv.toml" "rocm:/AI/$FOLDER/uv.toml"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install torch torchvision && uv pip install unsloth"

    # Set up Unsloth Studio (the web UI) into ~/.unsloth via the official installer.
    # --no-torch keeps our ROCm torch; --skip-autostart so it does not launch here;
    # --python points it at this venv. It also fetches ROCm (repo.radeon.com) wheels.
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        curl -fsSL https://unsloth.ai/install.sh | sh -s -- --no-torch --skip-autostart --python /AI/$FOLDER/.venv/bin/python"

    basic_run "unsloth" "$COMMAND" "&&"
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
    COMMIT="a449f5f987d49ecce18245d1402e4ec68513e7c0"
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

# trellis2.c - shared clone + weights, then a per-backend build.
# $1 = backend: "vulkan" (Mesa RADV, ROCm-independent) or "hip" (ROCm/HIP, faster).
# Both build the raylib GUI (trellis-gui): pick an image in the window, generate,
# preview the 3D result; GLBs land in output/.
COMMIT_TRELLIS2_C="51b364e3a4dbc1ea076b186bcf86665f507bfde4"

# Clone trellis2.c (shared by the ROCm, Vulkan and Pixal3D installers) and apply
# the OOM patch. Idempotent: skips the clone if the tree already exists. The patch
# (custom_files/trellis2.c/pixal3d-oom-fixes.patch) chunks the explicit attention
# score matrix and lazily allocates the sparse C2S decoder temporaries so the heavy
# Pixal3D 1024_cascade pipeline fits in 24 GB; it is numerically identical for
# TRELLIS.2 as well.
_trellis2_c_clone_and_patch() {
    local REPO="https://github.com/Wimacs/trellis2.c"
    local FOLDER="trellis2.c"
    local PATCH="$SCRIPT_DIR/custom_files/trellis2.c/pixal3d-oom-fixes.patch"

    podman exec -t rocm bash -c "if [ ! -d /AI/$FOLDER/.git ]; then \
        cd /AI && rm -rf $FOLDER && \
        git clone --recursive $REPO $FOLDER && \
        cd $FOLDER && git checkout $COMMIT_TRELLIS2_C && git submodule update --init --recursive; \
      else echo 'trellis2.c already cloned - reusing'; fi"

    # Apply the OOM patch only if it is not already applied (reverse-check succeeds
    # when it is), so re-running any of the three installers stays idempotent.
    podman cp "$PATCH" "rocm:/tmp/pixal3d-oom-fixes.patch"
    podman exec -t rocm bash -c "cd /AI/$FOLDER && \
        if git apply --check --reverse /tmp/pixal3d-oom-fixes.patch 2>/dev/null; then \
            echo 'trellis2.c OOM patch already applied'; \
        else \
            git apply /tmp/pixal3d-oom-fixes.patch && echo 'trellis2.c OOM patch applied'; \
        fi"
}

install_trellis2_c() {
    local BACKEND="${1:-vulkan}"
    FOLDER="trellis2.c"

    local BUILD_DIR RUN_LAUNCH
    if [ "$BACKEND" = "hip" ]; then
        BUILD_DIR="build-hip"
    else
        BACKEND="vulkan"
        BUILD_DIR="build-vulkan"
    fi

    basic_container

    _trellis2_c_clone_and_patch

    # Build the selected backend. The raylib GUI viewer (trellis-gui) is built ON -
    # it renders an X11 window on the host (X socket + DISPLAY come from
    # podman-compose; X11/OpenGL dev packages come from the Dockerfile).
    #   vulkan -> compute on Mesa RADV (no ROCm needed)
    #   hip    -> compute on ROCm/HIP (rocBLAS/hipBLAS), gfx target = $TARGET_GFX.
    #             The repo ships a native HIP backend + a CUDA->HIP compat shim, so
    #             the hand-written kernels build unchanged (no hipify step).
    if [ "$BACKEND" = "hip" ]; then
        podman exec -it rocm bash -c "cd /AI/$FOLDER && \
            export ROCM_PATH=/opt/rocm PATH=/opt/rocm/bin:\$PATH && \
            cmake -S . -B $BUILD_DIR -DCMAKE_BUILD_TYPE=Release \
                -DTRELLIS2_C_BACKEND=hip \
                -DCMAKE_HIP_ARCHITECTURES=$TARGET_GFX \
                -DTRELLIS2_C_BUILD_RAYLIB_VIEWER=ON \
                -DTRELLIS2_C_BUILD_TESTS=OFF && \
            cmake --build $BUILD_DIR -j\$(nproc)"
    else
        podman exec -it rocm bash -c "cd /AI/$FOLDER && \
            cmake -S . -B $BUILD_DIR -DCMAKE_BUILD_TYPE=Release \
                -DTRELLIS2_C_BACKEND=vulkan \
                -DTRELLIS2_C_BUILD_RAYLIB_VIEWER=ON \
                -DTRELLIS2_C_BUILD_TESTS=OFF && \
            cmake --build $BUILD_DIR -j\$(nproc)"
    fi

    # Weights: camenduru mirrors are public (no HuggingFace token needed), unlike the
    # gated facebook/dinov3. Layout goes to /AI/TRELLIS.2.
    # download_weights.py only needs huggingface_hub -> throwaway venv just for it.
    # Skip if already present (shared between the two backend variants).
    podman exec -it rocm bash -c "if [ ! -f /AI/TRELLIS.2/TRELLIS.2-4B/pipeline.json ]; then \
        cd /AI/$FOLDER && uv venv --python 3.13 && \
        source .venv/bin/activate && uv pip install huggingface_hub && \
        python tools/download_weights.py \
            --trellis-repo camenduru/TRELLIS.2-4B \
            --dino-repo camenduru/dinov3-vitl16-pretrain-lvd1689m \
            -o /AI/TRELLIS.2; \
      else echo 'TRELLIS.2 weights already present - reusing'; fi"

    # Custom run.sh: launches the raylib GUI (trellis-gui) for the selected backend.
    # Written on host then copied in to avoid nested-quote escaping.
    if [ "$BACKEND" = "hip" ]; then
        # ROCm/HIP: rocBLAS on the AMD device (HSA_OVERRIDE_GFX_VERSION from compose).
        RUN_LAUNCH="cd /AI/trellis2.c && export ROCM_PATH=/opt/rocm && mkdir -p output && ./build-hip/trellis-gui --model /AI/TRELLIS.2/TRELLIS.2-4B --dino /AI/TRELLIS.2/dinov3-vitl16-pretrain-lvd1689m --birefnet /AI/TRELLIS.2/BiRefNet/BiRefNet-F16.gguf --out-dir /AI/trellis2.c/output --pipeline 512"
    else
        # Vulkan: pin the RADV ICD so compute + window use the discrete AMD GPU.
        RUN_LAUNCH="cd /AI/trellis2.c && export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json && mkdir -p output && ./build-vulkan/trellis-gui --model /AI/TRELLIS.2/TRELLIS.2-4B --dino /AI/TRELLIS.2/dinov3-vitl16-pretrain-lvd1689m --birefnet /AI/TRELLIS.2/BiRefNet/BiRefNet-F16.gguf --out-dir /AI/trellis2.c/output --pipeline 512"
    fi
    local RUNSH
    RUNSH=$(mktemp)
    cat > "$RUNSH" << RUNEOF
#!/bin/bash
if ! podman ps -a --format '{{.Names}}' | grep -q '^rocm\$'; then
    echo 'Error: Container rocm does not exist.'
    exit 1
fi
if ! podman ps --format '{{.Names}}' | grep -q '^rocm\$'; then
    echo 'Container rocm is not running. Starting...'
    podman start rocm
fi
# Allow the container to reach the host X server so the GUI window can open.
command -v xhost >/dev/null 2>&1 && xhost +local: >/dev/null 2>&1 || true
podman exec -it rocm bash -c "$RUN_LAUNCH"
RUNEOF
    podman cp "$RUNSH" "rocm:/AI/$FOLDER/run.sh"
    podman exec -t rocm bash -c "chmod +x /AI/$FOLDER/run.sh"
    rm -f "$RUNSH"
}

# Pixal3D Experimental - the Pixal3D image-to-3D model running through trellis2.c's
# ROCm/HIP backend. Higher-fidelity than TRELLIS.2 but far heavier: 1024_cascade only
# (~1.5M voxels, ~9-10 min/asset on a 7900XTX). It only fits in 24 GB thanks to the
# OOM patch (chunked attention + lazy sparse-decoder temporaries) plus the runtime
# flags baked into run.sh below. CLI only (the raylib GUI is TRELLIS.2-only).
install_pixal3d_c() {
    FOLDER="trellis2.c"

    basic_container

    _trellis2_c_clone_and_patch

    # Build the ROCm/HIP backend (reuses the build dir / ccache if already built for
    # the trellis2.c ROCm variant). GUI stays ON so a single build serves both.
    podman exec -it rocm bash -c "cd /AI/$FOLDER && \
        export ROCM_PATH=/opt/rocm PATH=/opt/rocm/bin:\$PATH && \
        cmake -S . -B build-hip -DCMAKE_BUILD_TYPE=Release \
            -DTRELLIS2_C_BACKEND=hip \
            -DCMAKE_HIP_ARCHITECTURES=$TARGET_GFX \
            -DTRELLIS2_C_BUILD_RAYLIB_VIEWER=ON \
            -DTRELLIS2_C_BUILD_TESTS=OFF && \
        cmake --build build-hip -j\$(nproc)"

    # Shared conditioning weights (DINOv3 + BiRefNet) live under /AI/TRELLIS.2, same
    # as the trellis2.c variants. Download them if a trellis2.c install has not
    # already fetched them (public camenduru mirrors, no HuggingFace token).
    podman exec -it rocm bash -c "if [ ! -f /AI/TRELLIS.2/dinov3-vitl16-pretrain-lvd1689m/model.safetensors ] || [ ! -f /AI/TRELLIS.2/BiRefNet/BiRefNet-F16.gguf ]; then \
        cd /AI/$FOLDER && uv venv --python 3.13 && \
        source .venv/bin/activate && uv pip install huggingface_hub && \
        python tools/download_weights.py --only dino \
            --dino-repo camenduru/dinov3-vitl16-pretrain-lvd1689m -o /AI/TRELLIS.2 && \
        python tools/download_weights.py --only birefnet -o /AI/TRELLIS.2; \
      else echo 'DINOv3 + BiRefNet already present - reusing'; fi"

    # Pixal3D model weights (~24 GB, public TencentARC/Pixal3D - no HF token). The C
    # engine reads its own model.json manifest from the --model dir, so copy the
    # trellis2.c pixal3d manifest alongside the downloaded ckpts.
    podman exec -it rocm bash -c "if [ ! -f /AI/Pixal3D/Pixal3D/ckpts/ss_flow_img_dit_1_3B_64_bf16.safetensors ]; then \
        cd /AI/$FOLDER && source .venv/bin/activate 2>/dev/null || { uv venv --python 3.13 && source .venv/bin/activate && uv pip install huggingface_hub; }; \
        mkdir -p /AI/Pixal3D && \
        hf download TencentARC/Pixal3D --local-dir /AI/Pixal3D/Pixal3D; \
      else echo 'Pixal3D weights already present - reusing'; fi"
    podman exec -t rocm bash -c "cp /AI/$FOLDER/models/pixal3d/model.json /AI/Pixal3D/Pixal3D/model.json"

    # NAF (Neighborhood Attention Filtering) upsampler - a small ValeoAI checkpoint
    # (Apache 2.0) that Pixal3D needs. Fetch + convert to safetensors with the
    # repo's converter (needs torch + safetensors in the venv).
    podman exec -it rocm bash -c "if [ ! -f /AI/Pixal3D/Pixal3D/ckpts/naf_release.safetensors ]; then \
        cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install torch safetensors && \
        curl -L -o /tmp/naf_release.pth https://github.com/valeoai/NAF/releases/download/model/naf_release.pth && \
        python tools/convert_naf_weights.py /tmp/naf_release.pth /AI/Pixal3D/Pixal3D/ckpts/naf_release.safetensors && \
        rm -f /tmp/naf_release.pth; \
      else echo 'NAF weights already present - reusing'; fi"

    # Custom run.sh (CLI: ./run.sh [input_image] [output.glb]). The three runtime
    # flags are what make Pixal3D 1024_cascade fit in 24 GB:
    #   --no-ggml-flash-attn        : flash bf16 produces NaN on RDNA3; use the
    #                                 (patched, query-chunked) explicit SDPA path.
    #   --model-cache-budget-mib    : evict the ~19 GB of flow weights before decode.
    #   --vkmesh-gpu-workspace-...  : raise the mesh-remesh workspace budget.
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
IMAGE="${1:-example_image/T.png}"
OUTPUT="${2:-output/pixal3d.glb}"
podman exec -it rocm bash -c "cd /AI/trellis2.c && export ROCM_PATH=/opt/rocm && mkdir -p output && ./build-hip/pixal3d-image-to-gltf --model /AI/Pixal3D/Pixal3D --dino /AI/TRELLIS.2/dinov3-vitl16-pretrain-lvd1689m --birefnet /AI/TRELLIS.2/BiRefNet/BiRefNet-F16.gguf --image \"$IMAGE\" --no-ggml-flash-attn --model-cache-budget-mib 2048 --vkmesh-gpu-workspace-budget-mib 12288 --output \"$OUTPUT\""
RUNEOF
    # run.sh lives in /AI/Pixal3D (its own interface folder) so it does not clash
    # with the trellis2.c GUI run.sh; it drives the shared /AI/trellis2.c build.
    podman exec -t rocm bash -c "mkdir -p /AI/Pixal3D"
    podman cp "$RUNSH" "rocm:/AI/Pixal3D/run.sh"
    podman exec -t rocm bash -c "chmod +x /AI/Pixal3D/run.sh"
    rm -f "$RUNSH"
}

# ARDY - NVIDIA nv-tlabs autoregressive-diffusion interactive human/robot motion
# generation from text + kinematic constraints. Sibling of Kimodo (same lab, same
# kimodo-viser frontend, same gated Llama-3 text encoder); ARDY is the newer,
# real-time/online autoregressive evolution. Interactive viser demo on :2333 plus a
# separate LLM2Vec text-encoder server. Requires a HuggingFace token with access to
# the gated meta-llama/Meta-Llama-3-8B-Instruct model (same as Kimodo).
install_ardy() {
    REPO="https://github.com/nv-tlabs/ardy"
    COMMIT="693f74d13b3d04a0a22ce127ee79c929dd89756b"
    FOLDER=$(basename "$REPO")

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO" "3.11"

    # uv.toml points uv at the ROCm manylinux index; without it in the working dir,
    # uv would pull the default CUDA torch wheel the upstream README uses.
    podman cp "$SCRIPT_DIR/uv.toml" "rocm:/AI/$FOLDER/uv.toml"

    # Editable install with the [demo] extra only (viser + gradio); the [trt] extra
    # is CUDA/TensorRT-only and is skipped. This also builds the MotionCorrection
    # C++ CMake extension (cmake + g++ from the base image; no CUDA in it). The
    # dependency resolution here pulls the CUDA torch wheel...
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install -e '.[demo]'"

    # ...so reinstall torch/torchvision from the ROCm index LAST, overriding the CUDA
    # wheel. Verified on a 7900XTX (gfx1100): torch 2.10.0+rocm7.2.4, GPU visible.
    # The torchvision resolution drags numpy up to 2.x, which violates ardy's
    # numpy<2 pin - force it back down afterwards.
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install --reinstall torch torchvision && uv pip install 'numpy<2'"

    # viser extracts a node-v20 tarball lazily on first server start as UID 1000
    # inside the container (-> ~101000 on the host via rootless podman remapping),
    # making the files undeletable from the host. Fix: chown at install time and on
    # every run. Same issue/fix as Kimodo (shared kimodo-viser frontend).
    podman exec -t rocm bash -c "chown -R root:root /AI/$FOLDER/ 2>/dev/null || true"

    # Custom run.sh: start the text-encoder server in the background, then the viser
    # demo (http://localhost:2333). Text encoder on CPU keeps the ~16 GB Llama-3 off
    # the GPU so the 24 GB card has room for the motion model. Checkpoints download
    # automatically on first use.
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
# Text encoder (Llama-3) forced to CPU so the full 24 GB VRAM stays for the motion
# model; expandable_segments avoids HIP allocator fragmentation.
podman exec -it rocm bash -c 'cd /AI/ardy && source .venv/bin/activate && \
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

    basic_container
    basic_git "$REPO" "$COMMIT"
    basic_venv "$REPO"
    basic_requirements "$REPO"
    basic_run "$REPO" "$COMMAND"

    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && hf download VAST-AI/TripoSplat --local-dir ckpts/"
}

# AutoRemesher - NOT an AI model: a classical (CPU/TBB) automatic quad-remeshing
# tool. Included as a helper for retopologizing the triangle-soup meshes that the
# 3D-generation apps (TRELLIS, trellis2.c, Pixal3D, PartCrafter, TripoSplat) output
# into clean quad topology for animation/modeling. Qt5 GUI + headless CLI.
install_autoremesher() {
    REPO="https://github.com/huxingyi/autoremesher"
    COMMIT="6b6e9adb59c4cf2abdd398173a97d030b566226e"
    FOLDER=$(basename "$REPO")

    basic_container

    # Qt5 + TBB build/runtime dependencies. The container is Ubuntu-based, so install
    # them here rather than bloating the base image. The .pro only pulls Qt core /
    # widgets / opengl (no multimedia), so the README's libqt5multimedia5-dev is not
    # needed - and it is absent on newer Ubuntu anyway.
    podman exec -t rocm bash -c "apt-get update && apt-get install -y \
        qt5-qmake qtbase5-dev qttools5-dev-tools libqt5svg5-dev libqt5opengl5-dev \
        libtbb-dev libgl1-mesa-dev"

    basic_git "$REPO" "$COMMIT"

    # Build the Qt Widgets GUI + CLI (single ./autoremesher binary). geogram, eigen,
    # isotropicremesher and tbb are bundled under thirdparty/. CPU-only (TBB).
    podman exec -it rocm bash -c "cd /AI/$FOLDER && qmake && make -j\$(nproc)"

    # Custom run.sh: launch the GUI for interactive retopology. Load a mesh (e.g. an
    # OBJ exported from a 3D-generation app) and remesh it to clean quads. Written on
    # host then copied in; xhost opens the host X server for the GUI window.
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
# Allow the container to reach the host X server so the GUI window can open.
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

    basic_container

    podman exec -t rocm bash -c "if [ -d /AI/$FOLDER ]; then rm -rf /AI/$FOLDER; fi && mkdir -p /AI/$FOLDER/loras"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && uv venv --python 3.13"

    podman cp "$SCRIPT_DIR/uv.toml" "rocm:/AI/$FOLDER/uv.toml"
    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install torch torchvision"

    podman exec -it rocm bash -c "cd /AI/$FOLDER && source .venv/bin/activate && \
        uv pip install 'git+https://github.com/huggingface/diffusers.git' \
        'transformers>=4.57.0' accelerate sentencepiece bitsandbytes peft gradio"

    podman cp "$SCRIPT_DIR/custom_files/Krea-2-Turbo/app.py" "rocm:/AI/$FOLDER/app.py"

    basic_run "$FOLDER" "$COMMAND"
}

# Backup and Restore Manager
run_backup() {
    bash "$SCRIPT_DIR/backup.sh"
}
