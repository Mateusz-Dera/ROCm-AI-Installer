#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 14: RUN AND VERIFY – TRELLIS-AMD (image-to-3D: GLB + Gaussian)
# ============================================================
phase14_verify_trellis() {
    info "============================================="
    info "PHASE 14: RUN AND VERIFY (TRELLIS-AMD)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local app_dir="/AI/TRELLIS-AMD"
    local app_port=7860
    local app_log="/tmp/trellis_server.log"
    local helper_src="${TESTS_DIR}/trellis_api_helper.py"
    local helper_dst="/tmp/trellis_api_helper.py"

    # --- Kill old instances and clear log ---
    podman exec -t rocm bash -c \
        "pkill -f 'app\.py' 2>/dev/null; pkill -f 'trellis' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; sleep 1; : > '${app_log}'" || true

    # --- Start TRELLIS-AMD ---
    info "Starting TRELLIS-AMD on port ${app_port}..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         ATTN_BACKEND=sdpa XFORMERS_DISABLED=1 SPARSE_BACKEND=torchsparse \
         uv run app.py >> '${app_log}' 2>&1"

    # --- Wait for /info endpoint (model loads at startup, can take >2 min) ---
    info "Waiting for TRELLIS-AMD to become ready (up to 600s)..."
    local waited=0 max_wait=600 ready=false
    while [ $waited -lt $max_wait ]; do
        if podman exec -t rocm bash -c \
               "curl -sf http://localhost:${app_port}/info \
                | grep -q '\"named_endpoints\"'" 2>/dev/null; then
            ready=true; break
        fi
        sleep 5; waited=$((waited + 5))
        info "  ...waiting ($waited/${max_wait}s)"
    done
    if ! $ready; then
        podman exec -t rocm bash -c "cat '${app_log}'" 2>/dev/null || true
        abort "TRELLIS-AMD did not become ready within ${max_wait}s"
    fi
    pass "TRELLIS-AMD API ready on port ${app_port}"

    # --- Copy Python helper into container ---
    podman cp "${helper_src}" "rocm:${helper_dst}" || \
        abort "Failed to copy trellis_api_helper.py into container"

    # --- Run API test helper (generate + extract GLB + extract Gaussian) ---
    info "Running TRELLIS-AMD API test (Generate → Extract GLB → Extract Gaussian)..."
    local test_output
    test_output=$(podman exec -t rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         python3 '${helper_dst}' 2>/tmp/trellis_helper_stderr.txt" \
        | tr -d '\r') || true   # preserve output even on non-zero exit

    # Show stderr for debugging if test failed
    if ! echo "$test_output" | grep -q "GAUSSIAN_OK"; then
        podman exec -t rocm bash -c "cat /tmp/trellis_helper_stderr.txt" 2>/dev/null || true
        podman exec -t rocm bash -c "tail -30 '${app_log}'" 2>/dev/null || true
    fi

    # --- Check Generate ---
    if echo "$test_output" | grep -q "^GENERATE_OK:"; then
        local gen_line video_path gen_sz
        gen_line=$(echo "$test_output" | grep "^GENERATE_OK:" | head -1)
        video_path=$(echo "$gen_line" | cut -d: -f2)
        gen_sz=$(echo "$gen_line"    | cut -d: -f3)
        pass "TRELLIS Generate OK (video: ${video_path}, ${gen_sz} bytes)"
    else
        abort "TRELLIS Generate FAILED"
    fi

    # --- Check Extract GLB ---
    if echo "$test_output" | grep -q "^GLB_OK:"; then
        local glb_line glb_path glb_sz
        glb_line=$(echo "$test_output" | grep "^GLB_OK:" | head -1)
        glb_path=$(echo "$glb_line" | cut -d: -f2)
        glb_sz=$(echo "$glb_line"   | cut -d: -f3)
        pass "TRELLIS Extract GLB OK (${glb_path}, ${glb_sz} bytes)"
        if [ "${glb_sz:-0}" -lt 1024 ]; then
            abort "GLB file suspiciously small (${glb_sz} bytes)"
        fi
    elif echo "$test_output" | grep -q "^GLB_FAIL:"; then
        local fail_msg
        fail_msg=$(echo "$test_output" | grep "^GLB_FAIL:" | head -1 | cut -d: -f2-)
        abort "TRELLIS Extract GLB FAILED: ${fail_msg}"
    else
        abort "TRELLIS Extract GLB: no result"
    fi

    # --- Check Extract Gaussian ---
    if echo "$test_output" | grep -q "^GAUSSIAN_OK:"; then
        local gs_line ply_path ply_sz
        gs_line=$(echo "$test_output" | grep "^GAUSSIAN_OK:" | head -1)
        ply_path=$(echo "$gs_line" | cut -d: -f2)
        ply_sz=$(echo "$gs_line"   | cut -d: -f3)
        pass "TRELLIS Extract Gaussian OK (${ply_path}, ${ply_sz} bytes)"
        if [ "${ply_sz:-0}" -lt 1024 ]; then
            abort "PLY file suspiciously small (${ply_sz} bytes)"
        fi
    elif echo "$test_output" | grep -q "^GAUSSIAN_FAIL:"; then
        local fail_msg
        fail_msg=$(echo "$test_output" | grep "^GAUSSIAN_FAIL:" | head -1 | cut -d: -f2-)
        abort "TRELLIS Extract Gaussian FAILED: ${fail_msg}"
    else
        abort "TRELLIS Extract Gaussian: no result"
    fi

    # --- Stop server ---
    info "Stopping TRELLIS-AMD..."
    podman exec -t rocm bash -c \
        "pkill -f 'app\.py' 2>/dev/null; pkill -f 'trellis' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c \
            "fuser ${app_port}/tcp > /dev/null 2>&1" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "TRELLIS-AMD stopped"

    info "Phase 14 DONE"
}

main() { phase14_verify_trellis; }
main "$@"
