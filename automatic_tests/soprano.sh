#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

test_soprano() {
    info "============================================="
    info "TEST: Soprano (install + verify)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."
    clean_hf_incomplete

    # --- Install ---
    run_install "Soprano" install_soprano "/AI/soprano-rocm"

    # --- Test ---
    local app_dir="/AI/soprano-rocm"
    local app_log="/tmp/soprano_server.log"
    local REF_TEXT="Hello, this is a test of the soprano speech synthesis system."

    podman exec -t rocm bash -c "pkill -9 -f 'soprano' 2>/dev/null; true" 2>/dev/null || true
    podman exec -t rocm bash -c "pgrep 'VLLM' | xargs -r kill -9 2>/dev/null; true" || true
    sleep 3
    podman exec -t rocm bash -c \
        "fuser -k 7860/tcp 2>/dev/null; fuser -k 7861/tcp 2>/dev/null; \
         sleep 1; rm -f '${app_log}'; touch '${app_log}'" || true

    info "Starting Soprano TTS..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         TORCH_BLAS_PREFER_HIPBLASLT=1 soprano-webui \
         >> '${app_log}' 2>&1"

    info "Waiting for Soprano model to load and Gradio to start (up to 300s)..."
    sleep 5
    local app_port="" waited=5 max_wait=300
    while [ $waited -lt $max_wait ]; do
        app_port=$(podman exec -t rocm bash -c \
            "grep -oP 'Starting Gradio interface on port \K[0-9]+' '${app_log}' 2>/dev/null | tail -1" \
            | tr -d '\r\n') || app_port=""
        [ -n "$app_port" ] && break
        sleep 5; waited=$((waited + 5))
        info "  ...waiting ($waited/${max_wait}s)"
    done
    if [ -z "$app_port" ]; then
        podman exec -t rocm bash -c "cat '${app_log}'" 2>/dev/null || true
        abort "Soprano: could not detect port from log within ${max_wait}s"
    fi
    pass "Soprano ready on port ${app_port} (model loaded)"

    info "Requesting speech synthesis: \"${REF_TEXT}\"..."
    local event_id
    event_id=$(podman exec -t rocm bash -c "
        curl -sf -X POST http://localhost:${app_port}/gradio_api/call/generate_speech \
            -H 'Content-Type: application/json' \
            -d '{\"data\": [
                \"${REF_TEXT}\",
                0.0, 0.95, 1.2, 1, false
            ]}' | tr -d '\r'
    " 2>/dev/null \
    | grep -o '"event_id":"[^"]*"' \
    | grep -o '[^:]*$' \
    | tr -d '"') || true

    if [ -z "$event_id" ]; then
        podman exec -t rocm bash -c "cat '${app_log}'" 2>/dev/null || true
        abort "Soprano: no event_id returned from /generate_speech"
    fi
    info "Generation started (event_id: $event_id) – polling result..."

    local gen_result
    gen_result=$(podman exec -t rocm bash -c "
        curl -sf --max-time 120 \
            http://localhost:${app_port}/gradio_api/call/generate_speech/${event_id} \
        | tr -d '\r'
    " 2>/dev/null) || true

    if echo "$gen_result" | grep -q '"path"'; then
        pass "Soprano speech generation OK (audio returned)"
    else
        info "Raw result: $gen_result"
        podman exec -t rocm bash -c "tail -20 '${app_log}'" 2>/dev/null || true
        abort "Soprano generation did not return audio data"
    fi

    info "Stopping Soprano..."
    podman exec -t rocm bash -c "pkill -9 -f 'soprano' 2>/dev/null; true" 2>/dev/null || true
    podman exec -t rocm bash -c "pgrep 'VLLM' | xargs -r kill -9 2>/dev/null; true" || true
    sleep 2
    podman exec -t rocm bash -c "fuser -k ${app_port}/tcp 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c \
            "fuser ${app_port}/tcp > /dev/null 2>&1" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "Soprano stopped"

    info "Test soprano DONE"
}

main() { test_soprano; }
main "$@"
