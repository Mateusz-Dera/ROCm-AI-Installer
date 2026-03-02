#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 18: ComfyUI workflow – Wan-2.2-5B-text-to-video
# ============================================================
phase18_comfyui_wan_t2v() {
    info "============================================="
    info "PHASE 18: ComfyUI – Wan-2.2-5B-text-to-video"
    info "============================================="

    local app_port=8188
    local app_dir="/AI/ComfyUI"
    local app_log="/tmp/comfyui_server.log"
    local workflow_src="${SCRIPT_DIR}/workflows/Wan-2.2-5B-text-to-video.json"
    local workflow_dst="/tmp/comfyui_workflow_18.json"
    local helper_src="${TESTS_DIR}/comfyui_run_workflow.py"
    local helper_dst="/tmp/comfyui_run_workflow.py"

    basic_container || abort "Container 'rocm' is not running."

    # --- Kill old ComfyUI instances ---
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

    info "Waiting for ComfyUI to become ready (up to 300s)..."
    local rc
    wait_for_http \
        "curl -sf http://localhost:${app_port}/system_stats | grep -q 'python_version'" \
        "main\.py" "${app_log}" 300 "Starting server"
    rc=$?
    if [ $rc -eq 1 ]; then
        podman exec -t rocm bash -c "cat '${app_log}'" 2>/dev/null || true
        abort "ComfyUI process died"
    elif [ $rc -eq 2 ]; then
        podman exec -t rocm bash -c "tail -30 '${app_log}'" 2>/dev/null || true
        abort "ComfyUI did not become ready within 300s"
    fi
    pass "ComfyUI ready"

    # --- Copy workflow JSON and helper into container ---
    podman cp "${workflow_src}" "rocm:${workflow_dst}" || \
        abort "Failed to copy workflow JSON into container"
    podman cp "${helper_src}" "rocm:${helper_dst}" || \
        abort "Failed to copy comfyui_run_workflow.py into container"

    # --- Run workflow ---
    # NOTE: Wan 5B text-to-video with 97 frames / 20 steps can take 1-3 hours.
    info "Running Wan-2.2-5B-text-to-video workflow (up to 3h)..."
    local test_output
    test_output=$(podman exec -t rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         python3 '${helper_dst}' '${workflow_dst}' 2>/tmp/comfyui_helper_18_stderr.txt" \
        | tr -d '\r') || true

    if ! echo "$test_output" | grep -q "^OUTPUT_OK:"; then
        podman exec -t rocm bash -c "cat /tmp/comfyui_helper_18_stderr.txt" 2>/dev/null || true
        podman exec -t rocm bash -c "tail -30 '${app_log}'" 2>/dev/null || true
        abort "Wan-2.2-5B-text-to-video workflow FAILED"
    fi

    local out_line out_path out_sz
    out_line=$(echo "$test_output" | grep "^OUTPUT_OK:" | head -1)
    out_path=$(echo "$out_line" | cut -d: -f2)
    out_sz=$(echo "$out_line"   | cut -d: -f3)
    pass "Wan-2.2-5B-text-to-video output OK (${out_path}, ${out_sz} bytes)"
    if [ "${out_sz:-0}" -lt 10240 ]; then
        abort "Output video suspiciously small (${out_sz} bytes)"
    fi
    pass "Output size OK (${out_sz} bytes >= 10 KB)"

    # --- Stop ComfyUI ---
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

    info "Phase 18 DONE"
}

main() { phase18_comfyui_wan_t2v; }
main "$@"
