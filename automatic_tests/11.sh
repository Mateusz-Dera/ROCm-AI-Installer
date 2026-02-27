#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 11: RUN AND VERIFY – Soprano (text-to-speech)
# ============================================================
phase11_verify_soprano() {
    info "============================================="
    info "PHASE 11: RUN AND VERIFY (Soprano)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local app_dir="/AI/soprano-rocm"
    local app_log="/tmp/soprano_server.log"
    local ref_wav="/tmp/soprano_voice_ref.wav"
    local REF_TEXT="Hello, this is a test of the soprano speech synthesis system."

    # --- Kill old instances and clear log ---
    podman exec -t rocm bash -c \
        "pkill -f 'soprano-webui' 2>/dev/null; pkill -f 'soprano' 2>/dev/null; \
         sleep 2; : > '${app_log}'" || true

    # --- Start Soprano ---
    info "Starting Soprano TTS..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         TORCH_BLAS_PREFER_HIPBLASLT=1 soprano-webui \
         >> '${app_log}' 2>&1"

    # --- Detect port from log (Soprano finds free port starting at 7860) ---
    info "Waiting for Soprano to start and detect port (up to 120s)..."
    local app_port="" waited=0 max_wait=120
    while [ $waited -lt $max_wait ]; do
        app_port=$(podman exec -t rocm bash -c \
            "grep -oP 'Starting Gradio interface on port \K[0-9]+' '${app_log}' 2>/dev/null | tail -1" \
            | tr -d '\r\n') || app_port=""
        [ -n "$app_port" ] && break
        sleep 3; waited=$((waited + 3))
        info "  ...waiting ($waited/${max_wait}s)"
    done
    if [ -z "$app_port" ]; then
        podman exec -t rocm bash -c "cat '${app_log}'" 2>/dev/null || true
        abort "Soprano: could not detect port from log"
    fi
    info "Soprano detected port: ${app_port}"

    # --- Wait for Gradio API to become ready ---
    info "Waiting for Soprano Gradio API on port ${app_port} (up to 300s)..."
    local ready=false
    waited=0; max_wait=300
    while [ $waited -lt $max_wait ]; do
        if podman exec -t rocm bash -c \
               "curl -sf http://localhost:${app_port}/gradio_api/info \
                | grep -q '\"named_endpoints\"'" 2>/dev/null; then
            ready=true; break
        fi
        sleep 5; waited=$((waited + 5))
        info "  ...waiting ($waited/${max_wait}s)"
    done
    if ! $ready; then
        podman exec -t rocm bash -c "cat '${app_log}'" 2>/dev/null || true
        abort "Soprano did not become ready within ${max_wait}s"
    fi
    pass "Soprano Gradio API ready on port ${app_port}"

    # --- Generate speech (streaming=false → single audio file returned) ---
    info "Requesting speech synthesis: \"${REF_TEXT}\"..."
    local event_id
    event_id=$(podman exec -t rocm bash -c "
        curl -sf -X POST http://localhost:${app_port}/gradio_api/call/generate_speech \
            -H 'Content-Type: application/json' \
            -d '{\"data\": [
                \"${REF_TEXT}\",
                0.0,
                0.95,
                1.2,
                1,
                false
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

    # --- Poll result (SSE stream) ---
    local gen_result
    gen_result=$(podman exec -t rocm bash -c "
        curl -sf --max-time 120 \
            http://localhost:${app_port}/gradio_api/call/generate_speech/${event_id} \
        | tr -d '\r'
    " 2>/dev/null) || true

    if echo "$gen_result" | grep -q '"path"'; then
        pass "Soprano speech generation OK (audio returned)"
        # Extract audio path and copy to stable location for F5-TTS (test 12)
        local audio_path
        audio_path=$(echo "$gen_result" \
            | grep -o '"path":"[^"]*\.wav[^"]*"' | head -1 \
            | sed 's/"path":"//;s/"//') || audio_path=""
        if [ -n "$audio_path" ]; then
            podman exec -t rocm bash -c "cp '${audio_path}' '${ref_wav}'" 2>/dev/null || true
            local fsize
            fsize=$(podman exec -t rocm bash -c \
                "stat -c%s '${ref_wav}' 2>/dev/null || echo 0" \
                | tr -d '\r\n') || fsize=0
            info "  Voice reference saved: ${ref_wav} ($(( ${fsize:-0} / 1024 )) KB)"
        else
            info "  Warning: could not extract audio path from result"
        fi
    else
        info "Raw result: $gen_result"
        podman exec -t rocm bash -c "tail -20 '${app_log}'" 2>/dev/null || true
        abort "Soprano generation did not return audio data"
    fi

    # --- Stop server ---
    info "Stopping Soprano..."
    podman exec -t rocm bash -c \
        "pkill -f 'soprano-webui' 2>/dev/null; pkill -f 'soprano' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c \
            "fuser ${app_port}/tcp > /dev/null 2>&1" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "Soprano stopped"

    info "Phase 11 DONE"
}

main() { phase11_verify_soprano; }
main "$@"
