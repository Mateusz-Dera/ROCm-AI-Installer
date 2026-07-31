#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# Unsloth: LLM fine-tuning on ROCm. Verifies the install (ROCm torch + unsloth +
# the Studio web UI setup), that unsloth imports and sees the GPU, and that the
# Studio was installed. A full fine-tuning run is too heavy for an automated test.
test_unsloth() {
    info "============================================="
    info "TEST: Unsloth (install + ROCm import + Studio)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    # --- Install ---
    run_install "Unsloth" install_unsloth "/AI/unsloth"

    local app_dir="/AI/unsloth"

    # --- Verify ROCm torch (not the CUDA wheel) + unsloth import + GPU ---
    local out
    out=$(podman exec -t rocm bash -c "cd ${app_dir} && source .venv/bin/activate && \
        HSA_OVERRIDE_GFX_VERSION=11.0.0 python -c '
import torch
print(\"TORCH\", torch.__version__, torch.cuda.is_available())
import unsloth
print(\"UNSLOTH_OK\", unsloth.__version__)
' 2>&1" | tr -d '\r') || true

    if ! printf '%s' "$out" | grep -qE 'TORCH .*rocm'; then
        info "$out"
        abort "Unsloth: torch is not the ROCm build"
    fi
    if ! printf '%s' "$out" | grep -qE 'TORCH .*True'; then
        abort "Unsloth: torch does not see the GPU"
    fi
    pass "Unsloth on ROCm torch with GPU"

    if ! printf '%s' "$out" | grep -q 'UNSLOTH_OK'; then
        info "$out"
        abort "Unsloth: import failed"
    fi
    pass "Unsloth imports ($(printf '%s' "$out" | grep UNSLOTH_OK | awk '{print $2}'))"

    # --- Verify Unsloth Studio (web UI) was installed ---
    if ! podman exec -t rocm bash -c "[ -d /root/.unsloth/studio ]"; then
        abort "Unsloth: Studio was not installed (~/.unsloth/studio missing)"
    fi
    pass "Unsloth Studio installed"

    info "NOTE: a full fine-tuning run was not exercised (time/VRAM)."
    info "Test unsloth DONE"
}

main() { test_unsloth; }
main "$@"
