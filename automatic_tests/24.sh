#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 24: RUN AND VERIFY – TripoSplat (image to 3D Gaussian)
# 5 inference steps, 32768 gaussians for speed; est. ~5-15 min.
# ============================================================
phase24_verify_triposplat() {
    info "============================================="
    info "PHASE 24: RUN AND VERIFY (TripoSplat)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local app_dir="/AI/TripoSplat"
    local app_port=7860
    local app_log="/tmp/triposplat_server.log"
    local helper_src="$TESTS_DIR/triposplat_api_helper.py"
    local helper_dst="/tmp/triposplat_api_helper.py"

    # --- Kill any leftover processes ---
    podman exec -t rocm bash -c \
        "pkill -f 'python.*run_gradio\.py' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; sleep 1; \
         rm -f '${app_log}'; touch '${app_log}'" || true

    # --- Start TripoSplat ---
    info "Starting TripoSplat on port ${app_port} (model loading may take several minutes)..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         HSA_XNACK=0 \
         PYTORCH_HIP_ALLOC_CONF=garbage_collection_threshold:0.6,max_split_size_mb:128 \
         python -u run_gradio.py >> '${app_log}' 2>&1"
    sleep 5

    # --- Wait for HTTP ---
    wait_for_http \
        "curl -sf --max-time 3 http://localhost:${app_port}/ > /dev/null" \
        "python.*run_gradio\.py" \
        "${app_log}" \
        600 \
        "Running on local URL"

    local wait_rc=$?
    if [ $wait_rc -eq 1 ]; then
        podman exec -t rocm bash -c "tail -30 '${app_log}'" 2>/dev/null || true
        abort "TripoSplat process died during startup"
    elif [ $wait_rc -eq 2 ]; then
        podman exec -t rocm bash -c "tail -30 '${app_log}'" 2>/dev/null || true
        abort "TripoSplat did not become ready within 600s"
    fi
    pass "TripoSplat HTTP server ready on port ${app_port}"

    # --- Copy API helper into container ---
    podman cp "$helper_src" "rocm:${helper_dst}"

    # --- Run generation (timeout: 1800s = 30 min) ---
    info "Running image-to-3D generation (seed=42, steps=5, num_gaussians=32768)..."
    info "Expected: ~5-15 min (model load already done + generation)"

    local api_out
    api_out=$(podman exec -t rocm bash -c \
        "source '${app_dir}/.venv/bin/activate' && \
         python3 '${helper_dst}' 2>/dev/null" \
        | tr -d '\r') || {
        podman exec -t rocm bash -c "tail -20 '${app_log}'" 2>/dev/null || true
        abort "triposplat_api_helper.py failed"
    }

    # --- Check PLY_OK ---
    if ! printf '%s' "$api_out" | grep -q "^PLY_OK"; then
        info "API output: $api_out"
        abort "3D generation did not complete (PLY_OK not found)"
    fi
    pass "3D generation completed"

    # --- Check PLY file and size ---
    local ply_line
    ply_line=$(printf '%s' "$api_out" | grep "^PLY_OK:" | head -1)

    local ply_size
    ply_size=$(printf '%s' "$ply_line" | cut -d: -f3)
    if [ -z "$ply_size" ] || [ "$ply_size" -le 0 ] 2>/dev/null; then
        abort "PLY file is empty or size unknown: $ply_line"
    fi
    pass "PLY exported successfully (${ply_size} bytes)"

    # --- Verify PLY exists in container ---
    local ply_path
    ply_path=$(printf '%s' "$ply_line" | cut -d: -f2)
    podman exec -t rocm bash -c "[ -s '${ply_path}' ] || [ -s '/tmp/triposplat_test.ply' ]" \
        || abort "PLY file not found in container: ${ply_path}"
    pass "PLY file verified in container"

    # --- Stop TripoSplat ---
    info "Stopping TripoSplat..."
    podman exec -t rocm bash -c \
        "pkill -f 'python.*run_gradio\.py' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c \
            "fuser ${app_port}/tcp > /dev/null 2>&1" 2>/dev/null; do
        sleep 2; kw=$((kw + 2))
        [ $kw -ge 20 ] && break
    done
    pass "TripoSplat stopped"

    info "Phase 24 DONE"
}

main() { phase24_verify_triposplat; }
main "$@"
