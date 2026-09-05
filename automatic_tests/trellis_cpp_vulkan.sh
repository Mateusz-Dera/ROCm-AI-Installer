#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"
source "$TESTS_DIR/lib/trellis.sh"

_cleanup() {
    stop_app "$TRELLIS_PROC" "$TRELLIS_UI_PORT" > /dev/null 2>&1 || true
    stop_app "$TRELLIS_ENGINE" "$TRELLIS_PORT" > /dev/null 2>&1 || true
    reset_container || true
}
trap _cleanup EXIT INT TERM

main() {
    info "============================================="
    info "TEST: trellis.cpp (Vulkan, every weight set)"
    info "============================================="

    trellis_run_variant "trellis.cpp Vulkan" \
        "trellis.cpp-vulkan" install_trellis_cpp_vulkan

    info "Test trellis_cpp_vulkan DONE"
}

main "$@"
