#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 15: RUN AND VERIFY – ComfyUI (startup + API ready)
# ============================================================
phase15_verify_comfyui() {
    info "============================================="
    info "PHASE 15: RUN AND VERIFY (ComfyUI startup)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local app_dir="/AI/ComfyUI"
    local app_port=8188
    local app_log="/tmp/comfyui_server.log"

    # --- Kill old instances and clear log ---
    podman exec -t rocm bash -c \
        "pkill -f 'main\.py' 2>/dev/null; pkill -f 'comfyui' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; sleep 1; : > '${app_log}'" || true

    # --- Start ComfyUI ---
    info "Starting ComfyUI on port ${app_port}..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512 TORCH_BLAS_PREFER_HIPBLASLT=1 \
         uv run main.py --listen 0.0.0.0 --enable-manager --normalvram \
         --preview-method auto --dont-upcast-attention --bf16-vae \
         --use-pytorch-cross-attention --reserve-vram 2.0 \
         >> '${app_log}' 2>&1"

    # --- Wait for /system_stats (ComfyUI ready) ---
    info "Waiting for ComfyUI to become ready (up to 300s)..."
    local waited rc
    wait_for_http \
        "curl -sf http://localhost:${app_port}/system_stats | grep -q 'python_version'" \
        "main\.py" \
        "${app_log}" \
        300 \
        "Starting server"
    rc=$?
    if [ $rc -eq 1 ]; then
        podman exec -t rocm bash -c "cat '${app_log}'" 2>/dev/null || true
        abort "ComfyUI process died before becoming ready"
    elif [ $rc -eq 2 ]; then
        podman exec -t rocm bash -c "tail -30 '${app_log}'" 2>/dev/null || true
        abort "ComfyUI did not become ready within 300s"
    fi
    pass "ComfyUI API ready on port ${app_port}"

    # --- Quick sanity check: /object_info returns known node types ---
    local node_count
    node_count=$(podman exec -t rocm bash -c \
        "curl -sf http://localhost:${app_port}/object_info | python3 -c 'import sys,json; d=json.load(sys.stdin); print(len(d))'" \
        | tr -d '\r\n') || node_count=0
    if [ "${node_count:-0}" -lt 50 ]; then
        abort "ComfyUI /object_info returned only ${node_count} node types (expected >=50)"
    fi
    pass "ComfyUI /object_info OK (${node_count} node types)"

    # --- Stop server ---
    info "Stopping ComfyUI..."
    podman exec -t rocm bash -c \
        "pkill -f 'main\.py' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c \
            "fuser ${app_port}/tcp > /dev/null 2>&1" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "ComfyUI stopped"

    info "Phase 15 DONE"
}

main() { phase15_verify_comfyui; }
main "$@"
