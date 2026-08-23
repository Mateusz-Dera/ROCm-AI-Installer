#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

APP_DIR="/AI/ardy"
DEMO_PORT=2333
ENCODER_PORT=9550
APP_LOG="/tmp/ardy_demo.log"
DEMO_PAT="^python scripts/run_demo"
ENCODER_PAT="^python scripts/run_text_encoder_server"
SWEEP_PAT="[r]un_demo|[r]un_text_encoder_server"
VRAM_MAX_MIB=12000

_cleanup() {
    stop_app "$SWEEP_PAT" "$DEMO_PORT" > /dev/null 2>&1 || true
    ctr "fuser -k ${ENCODER_PORT}/tcp 2>/dev/null; true" > /dev/null 2>&1 || true
    reset_container || true
}
trap _cleanup EXIT INT TERM

test_ardy() {
    info "============================================="
    info "TEST: ARDY (text to motion, encoder on the CPU)"
    info "============================================="

    require_container
    clean_hf_incomplete

    stop_app "$SWEEP_PAT" "$DEMO_PORT"
    ctr "fuser -k ${ENCODER_PORT}/tcp 2>/dev/null; true"

    run_install "ARDY" install_ardy "$APP_DIR"
    require_gpu_pin "ARDY" ardy

    local cmd
    cmd=$(app_command ardy)
    printf '%s' "$cmd" | grep -q 'run_text_encoder_server.py --device cpu' \
        || abort "ARDY: run.sh does not start the text encoder server on the CPU - the topology under test is not the shipped one"
    pass "run.sh keeps the text encoder on the CPU, in its own process"

    printf '%s' "$cmd" | grep -q 'run_demo.py' \
        || abort "ARDY: run.sh does not start the demo"
    pass "run.sh starts the demo after the encoder"

    start_app ardy "$APP_LOG"

    info "Waiting for the text encoder server (CPU, ~16 GB model)..."
    wait_for_http_or_abort "ARDY encoder" \
        "curl -sf --max-time 3 http://localhost:${ENCODER_PORT}/gradio_api/info > /dev/null" \
        "$ENCODER_PAT" "$APP_LOG" 2400 "$APP_DIR"
    pass "Text encoder server ready on port ${ENCODER_PORT}"

    if ! listens_on_all_interfaces "$ENCODER_PORT"; then
        fail "  Listening addresses: $(port_listen_addrs "$ENCODER_PORT" | tr '\n' ' ')"
        abort "ARDY: the encoder server is not listening on 0.0.0.0:${ENCODER_PORT}"
    fi
    pass "Encoder listening on 0.0.0.0:${ENCODER_PORT}"

    info "Waiting for the demo..."
    wait_for_http_or_abort "ARDY demo" \
        "curl -sf --max-time 3 http://localhost:${DEMO_PORT}/ > /dev/null" \
        "$DEMO_PAT" "$APP_LOG" 2400 "$APP_DIR"
    pass "Demo ready on port ${DEMO_PORT}"

    if ! listens_on_all_interfaces "$DEMO_PORT"; then
        fail "  Listening addresses: $(port_listen_addrs "$DEMO_PORT" | tr '\n' ' ')"
        abort "ARDY: the demo is not listening on 0.0.0.0:${DEMO_PORT}"
    fi
    pass "Demo listening on 0.0.0.0:${DEMO_PORT}"

    if ctr "grep -q 'falling back to local LLM2Vec' '${APP_LOG}'"; then
        dump_lines "grep -n 'text encoder' '${APP_LOG}' | tail -5"
        abort "ARDY: the demo could not reach the encoder service and loaded the 16 GB encoder itself"
    fi
    pass "The demo reached the encoder service - no fallback to a local encoder"

    ctr "grep -q 'Setting up text encoder' '${APP_LOG}'" \
        || abort "ARDY: the demo never set up a text encoder"
    pass "Demo set up its text encoder through the service"

    require_gpu_process "ARDY" "$DEMO_PAT"

    local encoder_vram
    [ -n "$(app_pid "$ENCODER_PAT")" ] || abort "ARDY: the encoder server process is gone"
    encoder_vram=$(gpu_vram_mib "$ENCODER_PAT")
    [ "${encoder_vram:-0}" -eq 0 ] \
        || abort "ARDY: the encoder server holds ${encoder_vram} MiB of VRAM - it is meant to run on the CPU"
    pass "Encoder server holds no VRAM - it really is on the CPU"

    local demo_vram
    demo_vram=$(gpu_vram_mib "$DEMO_PAT")
    info "  Demo VRAM: ${demo_vram} MiB"
    [ "${demo_vram:-0}" -lt "$VRAM_MAX_MIB" ] \
        || abort "ARDY: the demo holds ${demo_vram} MiB - that is the local encoder loaded on the GPU, not just the motion model"
    pass "Demo VRAM stays under ${VRAM_MAX_MIB} MiB - only the motion model is on the card"

    stop_app "$SWEEP_PAT" "$DEMO_PORT"
    ctr "fuser -k ${ENCODER_PORT}/tcp 2>/dev/null; true"
    pass "ARDY stopped"

    ctr "rm -f '${APP_LOG}'"
    info "Test ardy DONE"
}

main() { test_ardy; }
main "$@"
