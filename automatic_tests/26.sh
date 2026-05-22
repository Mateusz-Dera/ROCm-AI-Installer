#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 26: RUN AND VERIFY – TRELLIS.2_rocm (3D + GLB export)
# resolution=512, steps=4 per phase; est. ~20 min generation
# + ~5 min GLB extraction
# ============================================================
phase26_verify_trellis2_rocm() {
    info "============================================="
    info "PHASE 26: RUN AND VERIFY (TRELLIS.2_rocm)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local app_dir="/AI/TRELLIS.2_rocm"
    local app_port=7860
    local app_log="/tmp/trellis2_rocm_server.log"
    local helper_src="$TESTS_DIR/trellis2_rocm_api_helper.py"
    local helper_dst="/tmp/trellis2_rocm_api_helper.py"

    # --- Kill any leftover processes ---
    podman exec -t rocm bash -c \
        "pkill -f 'python.*app\.py' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; sleep 1; rm -f '${app_log}'; touch '${app_log}'" || true

    # --- Start TRELLIS.2_rocm ---
    info "Starting TRELLIS.2_rocm on port ${app_port} (model loading may take several minutes)..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         ATTN_BACKEND=flash_attn HSA_XNACK=1 ROCM_SAFE_SPCONV=1 \
         PYTORCH_HIP_ALLOC_CONF=garbage_collection_threshold:0.6,max_split_size_mb:128 \
         PYTORCH_ALLOC_CONF=expandable_segments:True \
         GRADIO_SERVER_NAME=0.0.0.0 \
         python -u app.py >> '${app_log}' 2>&1"
    sleep 5

    # --- Wait for HTTP ---
    wait_for_http \
        "curl -sf --max-time 3 http://localhost:${app_port}/ > /dev/null" \
        "python.*app\.py" \
        "${app_log}" \
        600 \
        "Running on local URL"

    local wait_rc=$?
    if [ $wait_rc -eq 1 ]; then
        podman exec -t rocm bash -c "tail -30 '${app_log}'" 2>/dev/null || true
        abort "TRELLIS.2_rocm process died during startup"
    elif [ $wait_rc -eq 2 ]; then
        podman exec -t rocm bash -c "tail -30 '${app_log}'" 2>/dev/null || true
        abort "TRELLIS.2_rocm did not become ready within 600s"
    fi
    pass "TRELLIS.2_rocm HTTP server ready on port ${app_port}"

    # --- Copy API helper into container ---
    podman cp "$helper_src" "rocm:${helper_dst}"

    # --- Run generation + GLB export (timeout: 6000s = ~100 min) ---
    info "Running 3D generation + GLB export (resolution=512, 4 steps/phase)..."
    info "Expected: ~20 min generation + ~5 min GLB extraction"

    local api_out
    api_out=$(podman exec -t rocm bash -c \
        "source '${app_dir}/.venv/bin/activate' && \
         python3 '${helper_dst}' 2>/dev/null" \
        | tr -d '\r') || {
        podman exec -t rocm bash -c "tail -20 '${app_log}'" 2>/dev/null || true
        abort "trellis2_rocm_api_helper.py failed"
    }

    # --- Check GENERATE_OK ---
    if ! printf '%s' "$api_out" | grep -q "^GENERATE_OK"; then
        info "API output: $api_out"
        abort "3D generation did not complete (GENERATE_OK not found)"
    fi
    pass "3D generation completed"

    # --- Check GLB_OK and file size ---
    local glb_line
    glb_line=$(printf '%s' "$api_out" | grep "^GLB_OK:" | head -1)
    if [ -z "$glb_line" ]; then
        info "API output: $api_out"
        abort "GLB extraction did not complete (GLB_OK not found)"
    fi

    local glb_size
    glb_size=$(printf '%s' "$glb_line" | cut -d: -f3)
    if [ -z "$glb_size" ] || [ "$glb_size" -le 0 ] 2>/dev/null; then
        abort "GLB file is empty or size unknown: $glb_line"
    fi
    pass "GLB exported successfully (${glb_size} bytes)"

    # --- Verify GLB exists in container ---
    local glb_path
    glb_path=$(printf '%s' "$glb_line" | cut -d: -f2)
    podman exec -t rocm bash -c "[ -s '${glb_path}' ] || [ -s '/tmp/trellis2_rocm_test.glb' ]" \
        || abort "GLB file not found in container: ${glb_path}"
    pass "GLB file verified in container"

    # --- Stop TRELLIS.2_rocm ---
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

    info "Phase 26 DONE"
}

main() { phase26_verify_trellis2_rocm; }
main "$@"
