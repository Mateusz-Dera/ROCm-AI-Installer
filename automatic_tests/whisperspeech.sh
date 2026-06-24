#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

test_whisperspeech() {
    info "============================================="
    info "TEST: WhisperSpeech web UI (install + verify)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."
    clean_hf_incomplete

    # --- Install ---
    run_install "WhisperSpeech web UI" install_whisperspeech_web_ui "/AI/whisperspeech-webui"

    # --- Test ---
    local ws_dir="/AI/whisperspeech-webui"
    local ws_port=7860
    local ws_log="/tmp/whisper_server.log"

    podman exec -t rocm bash -c "pkill -f 'webui.py' 2>/dev/null; sleep 1; : > '$ws_log'" || true

    info "Starting WhisperSpeech web UI (port $ws_port)..."
    podman exec -d rocm bash -c \
        "cd '$ws_dir' && source .venv/bin/activate \
         && uv run --extra rocm webui.py --listen --api \
         >> '$ws_log' 2>&1"

    info "Waiting for WhisperSpeech web UI to become ready..."
    local waited=0 max_wait=180 ready=false
    while [ $waited -lt $max_wait ]; do
        if podman exec -t rocm bash -c \
               "curl -sf http://localhost:${ws_port}/ > /dev/null" 2>/dev/null; then
            ready=true; break
        fi
        sleep 5; waited=$((waited + 5))
        info "  ...waiting ($waited/${max_wait}s)"
    done
    if ! $ready; then
        podman exec -t rocm bash -c "cat '$ws_log'" 2>/dev/null || true
        abort "WhisperSpeech web UI did not start within ${max_wait}s"
    fi
    pass "WhisperSpeech web UI is running on port $ws_port"

    info "Waiting for Gradio API to become ready..."
    local api_info="" api_waited=0 api_max=600
    while [ $api_waited -lt $api_max ]; do
        api_info=$(podman exec -t rocm bash -c \
            "curl -sf http://localhost:${ws_port}/gradio_api/info" 2>/dev/null \
            | tr -d '\r') || true
        if echo "$api_info" | grep -q '"named_endpoints"'; then break; fi
        sleep 5; api_waited=$((api_waited + 5))
        info "  ...API not ready yet ($api_waited/${api_max}s)"
    done
    if ! echo "$api_info" | grep -q '"named_endpoints"'; then
        podman exec -t rocm bash -c "cat '$ws_log'" 2>/dev/null || true
        abort "WhisperSpeech Gradio API did not become ready within ${api_max}s"
    fi
    pass "Gradio API ready"

    local tts_fn
    tts_fn=$(echo "$api_info" \
        | grep -o '"named_endpoints":{"[^"]*"' \
        | grep -o '"[^"]*"$' | tr -d '"' | sed 's|^/||')
    info "TTS endpoint: /gradio_api/call/${tts_fn}"

    info "Testing TTS generation..."
    local event_id
    event_id=$(podman exec -t rocm bash -c "
        curl -sf -X POST http://localhost:${ws_port}/gradio_api/call/${tts_fn} \
            -H 'Content-Type: application/json' \
            -d '{\"data\": [
                \"collabora/whisperspeech:s2a-q4-tiny-en+pl.model\",
                \"Test audio generation\",
                13.5, null, \"wav\", false
            ]}' | tr -d '\r'
    " 2>/dev/null | grep -o '"event_id":"[^"]*"' | grep -o '[^:]*$' | tr -d '"') || true

    if [ -z "$event_id" ]; then
        podman exec -t rocm bash -c "cat '$ws_log'" 2>/dev/null || true
        abort "WhisperSpeech TTS: no event_id returned"
    fi
    info "TTS event_id: $event_id – polling result..."

    local tts_result
    tts_result=$(podman exec -t rocm bash -c "
        curl -sf --max-time 120 \
            http://localhost:${ws_port}/gradio_api/call/${tts_fn}/${event_id} \
        | tr -d '\r'
    " 2>/dev/null) || true

    if echo "$tts_result" | grep -qE '\.wav|\.mp3|\.ogg|"path"'; then
        pass "WhisperSpeech TTS generation OK (audio file returned)"
    else
        info "Raw TTS result: $tts_result"
        podman exec -t rocm bash -c "cat '$ws_log'" 2>/dev/null || true
        abort "WhisperSpeech TTS API did not return audio data"
    fi

    info "Stopping WhisperSpeech..."
    podman exec -t rocm bash -c "pkill -f 'webui.py' 2>/dev/null || true" || true
    local kw=0
    while podman exec -t rocm bash -c "pgrep -f 'webui.py' > /dev/null" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "WhisperSpeech stopped"

    info "Test whisperspeech DONE"
}

main() { test_whisperspeech; }
main "$@"
