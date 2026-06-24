#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

test_kimodo() {
    info "============================================="
    info "TEST: kimodo (install + verify)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."
    clean_hf_incomplete

    # --- Require HF_TOKEN ---
    local hf_tok
    hf_tok=$(podman exec -t rocm bash -c 'printf "%s" "${HF_TOKEN:-}"' | tr -d '\r')
    if [ -z "$hf_tok" ]; then
        abort "HF_TOKEN is not set in the container — required for kimodo model download"
    fi
    info "HF_TOKEN is set"

    # --- Install ---
    run_install "kimodo" install_kimodo "/AI/kimodo"

    # --- Test ---
    local app_dir="/AI/kimodo"
    local app_port=7860
    local out_npz="/tmp/kimodo_test_gen.npz"

    podman exec -t rocm bash -c "pkill -f 'kimodo_demo' 2>/dev/null; true" 2>/dev/null || true
    sleep 3
    podman exec -t rocm bash -c "fuser -k ${app_port}/tcp 2>/dev/null; true" || true
    podman exec -t rocm bash -c "rm -f '${out_npz}'" || true

    info "Running kimodo_gen (5 diffusion steps, 2s, seed 42)..."
    local gen_out
    gen_out=$(podman exec -t rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         TEXT_ENCODER_DEVICE=cpu kimodo_gen \
             'A person walks forward.' \
             --diffusion_steps 5 \
             --duration 2.0 \
             --seed 42 \
             --output '${out_npz}' 2>&1" \
        | tr -d '\r') || {
        abort "kimodo_gen failed"
    }

    if ! printf '%s' "$gen_out" | grep -q "Loaded model:"; then
        info "Output: $gen_out"
        abort "kimodo model did not load (no 'Loaded model:' in output)"
    fi
    pass "kimodo model loaded"

    if ! printf '%s' "$gen_out" | grep -q "Saving the npz output"; then
        info "Output: $gen_out"
        abort "kimodo_gen did not save NPZ"
    fi
    pass "kimodo generation completed"

    local npz_size
    npz_size=$(podman exec -t rocm bash -c \
        "stat -c%s '${out_npz}' 2>/dev/null || echo 0" \
        | tr -d '\r\n') || npz_size=0
    if [ -z "$npz_size" ] || [ "$npz_size" -le 0 ] 2>/dev/null; then
        abort "kimodo NPZ file is empty or missing: ${out_npz}"
    fi
    pass "kimodo NPZ file saved (${npz_size} bytes)"

    local keys_ok
    keys_ok=$(podman exec -t rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         python3 -c \"
import numpy as np, sys
d = np.load('${out_npz}')
keys = set(d.keys())
required = {'posed_joints', 'global_rot_mats'}
missing = required - keys
if missing:
    print('MISSING:' + ','.join(missing)); sys.exit(1)
print('KEYS_OK:' + ','.join(sorted(keys)))
\"" \
        | tr -d '\r') || {
        abort "kimodo NPZ key verification failed"
    }

    if ! printf '%s' "$keys_ok" | grep -q "^KEYS_OK:"; then
        info "NPZ check output: $keys_ok"
        abort "kimodo NPZ missing required keys"
    fi
    pass "kimodo NPZ verified ($(printf '%s' "$keys_ok" | cut -d: -f2))"

    info "Test kimodo DONE"
}

main() { test_kimodo; }
main "$@"
