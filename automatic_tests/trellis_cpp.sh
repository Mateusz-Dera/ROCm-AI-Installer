#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

BACKEND="${1:-hip}"
_install_trellis_cpp() { install_trellis_cpp "$BACKEND"; }

test_trellis_cpp() {
    info "============================================="
    info "TEST: trellis.cpp ${BACKEND} (install + generate)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."
    clean_hf_incomplete

    export TRELLIS_CPP_WEIGHTS="${TRELLIS_CPP_WEIGHTS:-q8}"

    run_install "trellis.cpp ($BACKEND)" _install_trellis_cpp "/AI/trellis.cpp"

    local app_dir="/AI/trellis.cpp"
    local app_port=8081
    local app_log="/tmp/trellis_cpp_server.log"
    local out_glb="/tmp/trellis_cpp_out.glb"
    local BACKEND_DIR server_env
    if [ "$BACKEND" = "vulkan" ]; then
        BACKEND_DIR="vulkan"
        server_env="VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json GGML_VK_VISIBLE_DEVICES=0"
    else
        BACKEND_DIR="hip"
        server_env="ROCM_PATH=/opt/rocm GGML_CUDA_DISABLE_GRAPHS=1 HIP_VISIBLE_DEVICES=0"
    fi

    podman exec -t rocm bash -c \
        "pkill -f '[t]rellis-server' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; sleep 1; \
         rm -f '${app_log}' '${out_glb}'; touch '${app_log}'" || true

    info "Starting trellis-server on port ${app_port}..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && export ${server_env} && \
         ./build-${BACKEND_DIR}/trellis-server --models /AI/trellis2-gguf \
            --host 0.0.0.0 --port ${app_port} >> '${app_log}' 2>&1"
    sleep 5

    wait_for_http \
        "curl -sf --max-time 3 http://localhost:${app_port}/health > /dev/null" \
        "trellis-server" \
        "$app_log" \
        600 \
        || abort "trellis.cpp: server did not become ready"
    pass "trellis.cpp server ready on port ${app_port}"

    info "Generating a GLB from assets/goblin.png (res 512)..."
    podman exec -t rocm bash -c \
        "curl -sf --max-time 3600 -o '${out_glb}' \
            -F 'image=@${app_dir}/assets/goblin.png' \
            -F 'resolution=512' -F 'seed=42' \
            http://localhost:${app_port}/generate" \
        || abort "trellis.cpp: /generate request failed"

    local fsize
    fsize=$(podman exec -t rocm bash -c "stat -c%s '${out_glb}' 2>/dev/null || echo 0" \
        | tr -d '\r\n')
    if [ "${fsize:-0}" -lt 100000 ]; then
        podman exec -t rocm bash -c "tail -20 '${app_log}'" 2>/dev/null || true
        abort "trellis.cpp: GLB suspiciously small (${fsize} bytes)"
    fi
    pass "trellis.cpp generated a GLB (${fsize} bytes)"

    podman exec -t rocm bash -c "head -c4 '${out_glb}' | grep -q 'glTF'" \
        || abort "trellis.cpp: output is not a GLB"
    pass "GLB header verified"

    info "Stopping trellis-server..."
    podman exec -t rocm bash -c "pkill -f '[t]rellis-server' 2>/dev/null; true" || true
    sleep 2
    podman exec -t rocm bash -c "fuser -k ${app_port}/tcp 2>/dev/null; true" || true
    pass "trellis.cpp stopped"

    info "Test trellis_cpp DONE"
}

main() { test_trellis_cpp; }
main "$@"
