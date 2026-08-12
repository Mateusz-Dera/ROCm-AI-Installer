#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

app_port=8188
app_dir="/AI/ComfyUI"
app_log="/tmp/comfyui_server.log"

_start_comfyui() {
    info "Killing old ComfyUI instances..."
    podman exec -t rocm bash -c \
        "pkill -f '[m]ain\.py' 2>/dev/null; pkill -f '[c]omfyui' 2>/dev/null; true" 2>/dev/null || true
    sleep 3
    podman exec -t rocm bash -c \
        "fuser -k ${app_port}/tcp 2>/dev/null; sleep 1; rm -f '${app_log}'; touch '${app_log}'" || true

    info "Starting ComfyUI on port ${app_port}..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512 TORCH_BLAS_PREFER_HIPBLASLT=1 \
         uv run main.py --listen 0.0.0.0 --enable-manager \
         --preview-method auto --dont-upcast-attention --bf16-vae \
         --use-pytorch-cross-attention --reserve-vram 2.0 \
         >> '${app_log}' 2>&1"

    info "Waiting for ComfyUI to become ready (up to 300s)..."
    local rc
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
}

_stop_comfyui() {
    info "Stopping ComfyUI..."
    podman exec -t rocm bash -c \
        "pkill -f '[m]ain\.py' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c \
            "fuser ${app_port}/tcp > /dev/null 2>&1" 2>/dev/null; do
        sleep 2; kw=$((kw + 2))
        if [ $kw -ge 20 ]; then break; fi
    done
    pass "ComfyUI stopped"
}

_run_workflow() {
    local workflow_name="$1"
    local workflow_src="$2"
    local min_size="$3"
    local stderr_suffix="$4"

    info "--- Workflow: ${workflow_name} ---"

    podman cp "${workflow_src}" "rocm:/tmp/${workflow_name}.json"

    podman cp "${TESTS_DIR}/helpers/comfyui_run_workflow.py" "rocm:/tmp/comfyui_run_workflow.py"

    local output stderr_log="/tmp/comfyui_wf_${stderr_suffix}.log"
    output=$(podman exec -t rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         python3 /tmp/comfyui_run_workflow.py '/tmp/${workflow_name}.json' \
         2>'${stderr_log}'" \
        | tr -d '\r') || true

    podman exec -t rocm bash -c "cat '${stderr_log}'" 2>/dev/null | while IFS= read -r line; do
        info "  [helper] $line"
    done || true

    if echo "$output" | grep -q '^OUTPUT_FAIL:'; then
        local reason
        reason=$(echo "$output" | grep '^OUTPUT_FAIL:' | head -1 | cut -d: -f2-)
        abort "${workflow_name}: workflow failed – ${reason}"
    fi

    if ! echo "$output" | grep -q '^OUTPUT_OK:'; then
        podman exec -t rocm bash -c "tail -30 '${app_log}'" 2>/dev/null || true
        abort "${workflow_name}: no OUTPUT_OK line in helper output"
    fi

    local any_ok=false
    while IFS= read -r line; do
        local fpath fsize
        fpath=$(echo "$line" | cut -d: -f2)
        fsize=$(echo "$line" | cut -d: -f3 | tr -d '\r\n')
        info "  Output: ${fpath} (${fsize} bytes)"
        if [ "${fsize:-0}" -ge "${min_size}" ]; then
            any_ok=true
        else
            fail "${workflow_name}: output file ${fpath} too small (${fsize} < ${min_size} bytes)"
        fi
    done < <(echo "$output" | grep '^OUTPUT_OK:')

    if ! $any_ok; then
        abort "${workflow_name}: no output file met minimum size (${min_size} bytes)"
    fi

    pass "${workflow_name} workflow completed successfully"
}

main() {
    info "============================================="
    info "ComfyUI: Install + Startup + Workflow Tests"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."
    clean_hf_incomplete

    info "--- Installing: ComfyUI (addons: 1 2 3 4 5) ---"
    if ! install_comfyui 1 2 3 4 5; then
        abort "ComfyUI: install function returned non-zero"
    fi
    if ! container_dir_exists "/AI/ComfyUI"; then
        abort "ComfyUI: directory /AI/ComfyUI not found after install"
    fi
    if ! container_file_exists "/AI/ComfyUI/run.sh"; then
        abort "ComfyUI: run.sh not found after install"
    fi
    pass "ComfyUI installed successfully (addons: 1 2 3 4 5)"

    _start_comfyui

    local node_count
    node_count=$(podman exec -t rocm bash -c \
        "curl -sf http://localhost:${app_port}/object_info | python3 -c 'import sys,json; d=json.load(sys.stdin); print(len(d))'" \
        | tr -d '\r\n') || node_count=0
    if [ "${node_count:-0}" -lt 50 ]; then
        abort "ComfyUI /object_info returned only ${node_count} node types (expected >=50)"
    fi
    pass "ComfyUI /object_info OK (${node_count} node types)"

    _stop_comfyui

    _start_comfyui
    _run_workflow \
        "Z-Image-Turbo" \
        "${SCRIPT_DIR}/workflows/Z-Image-Turbo.json" \
        10240 \
        "z_turbo"
    _stop_comfyui

    _start_comfyui
    _run_workflow \
        "Z-Anime" \
        "${SCRIPT_DIR}/workflows/Z-Anime.json" \
        10240 \
        "z_anime"
    _stop_comfyui

    _start_comfyui
    _run_workflow \
        "Wan-2.2-5B-text-to-video" \
        "${SCRIPT_DIR}/workflows/Wan-2.2-5B-text-to-video.json" \
        10240 \
        "wan_t2v"
    _stop_comfyui

    _start_comfyui
    podman cp "${SCRIPT_DIR}/workflows/images/bottle.png" "rocm:/AI/ComfyUI/input/bottle.png"
    _run_workflow \
        "Wan-2.2-5B-image-to-video" \
        "${SCRIPT_DIR}/workflows/Wan-2.2-5B-image-to-video.json" \
        10240 \
        "wan_i2v"
    _stop_comfyui

    info "============================================="
    pass "All ComfyUI tests passed"
    info "============================================="
}

main "$@"
