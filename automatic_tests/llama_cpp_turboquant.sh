#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"
source "$TESTS_DIR/lib/llama.sh"

_cleanup() {
    stop_app "$LLAMA_PROC" "$LLAMA_PORT" > /dev/null 2>&1 || true
    restore_user_models || true
    reset_container || true
}
trap _cleanup EXIT INT TERM

main() {
    info "============================================="
    info "TEST: llama.cpp TurboQuant (ROCm)"
    info "============================================="

    llama_run_variant "llama.cpp ROCm" \
        "llama.cpp-turboquant" install_llama_cpp_turboquant

    info "Test llama_cpp_turboquant DONE"
}

main "$@"
