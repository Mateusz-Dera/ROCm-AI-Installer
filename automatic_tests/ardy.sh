#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

test_ardy() {
    info "============================================="
    info "TEST: ARDY (install + ROCm motion generation)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."
    clean_hf_incomplete

    require_hf_token "ARDY"

    run_install "ARDY" install_ardy "/AI/ardy"

    local app_dir="/AI/ardy"

    local tv
    tv=$(podman exec -t rocm bash -c "cd ${app_dir} && source .venv/bin/activate && \
        python -c 'import torch; print(torch.__version__, torch.cuda.is_available())'" | tr -d '\r')
    if ! printf '%s' "$tv" | grep -q 'rocm'; then
        info "torch: $tv"
        abort "ARDY: torch is not the ROCm build"
    fi
    if ! printf '%s' "$tv" | grep -q 'True'; then
        abort "ARDY: torch does not see the GPU"
    fi
    pass "ARDY on ROCm torch with GPU ($(printf '%s' "$tv" | awk '{print $1}'))"

    if ! podman exec -t rocm bash -c "cd ${app_dir} && source .venv/bin/activate && python -c 'import ardy' 2>/dev/null"; then
        abort "ARDY: package import failed"
    fi
    pass "ARDY package imports (MotionCorrection C++ ext built)"

    local out_stem="/AI/ardy/test_motion"
    local gen_log="/tmp/ardy_gen.log"
    podman exec -t rocm bash -c "rm -f ${out_stem}.npz '${gen_log}'" || true

    info "Running headless motion generation (first run downloads Llama-3 + checkpoint)..."
    if ! podman exec -t rocm bash -c "
            cd ${app_dir} && source .venv/bin/activate && \
            export PYTORCH_HIP_ALLOC_CONF=expandable_segments:True && \
            timeout 1800 python scripts/generate.py 'a person walks forward' \
                --duration 3 --output ${out_stem} > '${gen_log}' 2>&1"; then
        podman exec -t rocm bash -c "tail -30 '${gen_log}'" 2>/dev/null || true
        abort "ARDY: motion generation returned non-zero (OOM or error)"
    fi

    local npz_size
    npz_size=$(podman exec -t rocm bash -c "stat -c %s ${out_stem}.npz 2>/dev/null" | tr -d '\r') || npz_size=""
    if [ -z "$npz_size" ] || [ "$npz_size" -le 0 ] 2>/dev/null; then
        podman exec -t rocm bash -c "tail -30 '${gen_log}'" 2>/dev/null || true
        abort "ARDY: output .npz is missing or empty"
    fi
    pass "ARDY generated a motion (${npz_size} bytes)"

    podman exec -t rocm bash -c "rm -f ${out_stem}.npz '${gen_log}'" 2>/dev/null || true

    info "Test ardy DONE"
}

main() { test_ardy; }
main "$@"
