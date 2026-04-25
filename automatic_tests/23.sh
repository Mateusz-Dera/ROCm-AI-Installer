#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 23: RUN AND VERIFY – TRELLIS.2_rocm (image-to-3D: GLB)
# ============================================================
phase23_verify_trellis2() {
    info "============================================="
    info "PHASE 23: RUN AND VERIFY (TRELLIS.2_rocm)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local app_dir="/AI/TRELLIS.2_rocm"
    local app_port=7860
    local app_log="/tmp/trellis2_server.log"
    local helper_src="${TESTS_DIR}/trellis2_api_helper.py"
    local helper_dst="/tmp/trellis2_api_helper.py"

    # --- Kill any leftover processes and clear log ---
    podman exec -t rocm bash -c \
        "pkill -f 'app\.py' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; sleep 1; : > '${app_log}'" || true

    # --- Start TRELLIS.2_rocm ---
    info "Starting TRELLIS.2_rocm on port ${app_port}..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         ROCM_SAFE_SPCONV=1 FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE \
         ATTN_BACKEND=sdpa GRADIO_SERVER_NAME=0.0.0.0 \
         PYTORCH_ALLOC_CONF=expandable_segments:True \
         python app.py >> '${app_log}' 2>&1"

    # --- Wait for /gradio_api/info (model loads at startup, can take 2+ min) ---
    info "Waiting for TRELLIS.2_rocm to become ready (up to 600s)..."
    local waited=0 max_wait=600 ready=false
    while [ $waited -lt $max_wait ]; do
        if podman exec -t rocm bash -c \
               "curl -sf http://localhost:${app_port}/gradio_api/info \
                | grep -q '\"named_endpoints\"'" 2>/dev/null; then
            ready=true; break
        fi
        # Fail fast if process died
        if ! podman exec -t rocm bash -c \
                "pgrep -f 'python.*app\.py' > /dev/null" 2>/dev/null; then
            podman exec -t rocm bash -c "tail -20 '${app_log}'" 2>/dev/null || true
            abort "TRELLIS.2_rocm process died during startup"
        fi
        sleep 5; waited=$((waited + 5))
        info "  ...waiting ($waited/${max_wait}s)"
    done
    if ! $ready; then
        podman exec -t rocm bash -c "tail -30 '${app_log}'" 2>/dev/null || true
        abort "TRELLIS.2_rocm did not become ready within ${max_wait}s"
    fi
    pass "TRELLIS.2_rocm API ready on port ${app_port}"

    # --- Copy Python helper into container ---
    podman cp "${helper_src}" "rocm:${helper_dst}" || \
        abort "Failed to copy trellis2_api_helper.py into container"

    # --- Run API test helper (preprocess → generate → extract GLB) ---
    info "Running TRELLIS.2_rocm API test (Preprocess → Generate → Extract GLB)..."
    local test_output
    test_output=$(podman exec -t rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         python3 '${helper_dst}' 2>/tmp/trellis2_helper_stderr.txt" \
        | tr -d '\r') || true

    # Show debug output if test did not produce expected results
    if ! echo "$test_output" | grep -q "GLB_OK"; then
        info "--- helper stderr ---"
        podman exec -t rocm bash -c "cat /tmp/trellis2_helper_stderr.txt" 2>/dev/null || true
        info "--- app log (last 30 lines) ---"
        podman exec -t rocm bash -c "tail -30 '${app_log}'" 2>/dev/null || true
    fi

    # --- Check Generate ---
    if echo "$test_output" | grep -q "^GENERATE_OK:"; then
        pass "TRELLIS.2 Generate OK"
    else
        abort "TRELLIS.2 Generate FAILED (no GENERATE_OK in output)"
    fi

    # --- Check Extract GLB ---
    if echo "$test_output" | grep -q "^GLB_OK:"; then
        local glb_line glb_path glb_sz
        glb_line=$(echo "$test_output" | grep "^GLB_OK:" | head -1)
        glb_path=$(echo "$glb_line" | cut -d: -f2)
        glb_sz=$(echo "$glb_line"   | cut -d: -f3)
        pass "TRELLIS.2 Extract GLB OK (${glb_path}, ${glb_sz} bytes)"
        if [ "${glb_sz:-0}" -lt 1024 ]; then
            abort "GLB file suspiciously small (${glb_sz} bytes)"
        fi
    elif echo "$test_output" | grep -q "^GLB_FAIL:"; then
        local fail_msg
        fail_msg=$(echo "$test_output" | grep "^GLB_FAIL:" | head -1 | cut -d: -f2-)
        abort "TRELLIS.2 Extract GLB FAILED: ${fail_msg}"
    else
        abort "TRELLIS.2 Extract GLB: no result in output"
    fi

    # --- Stop server ---
    info "Stopping TRELLIS.2_rocm..."
    podman exec -t rocm bash -c \
        "pkill -f 'python.*app\.py' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c \
            "fuser ${app_port}/tcp > /dev/null 2>&1" 2>/dev/null; do
        sleep 2; kw=$((kw + 2))
        [ $kw -ge 20 ] && break
    done
    pass "TRELLIS.2_rocm stopped"

    info "Phase 23 DONE"
}

main() { phase23_verify_trellis2; }
main "$@"
