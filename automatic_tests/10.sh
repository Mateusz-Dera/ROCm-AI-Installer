#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 10: RUN AND VERIFY – HeartMuLa (text-to-music)
# ============================================================
phase10_verify_heartmula() {
    info "============================================="
    info "PHASE 10: RUN AND VERIFY (HeartMuLa)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local app_dir="/AI/heartlib"
    local app_port=7860
    local app_log="/tmp/heartmula_server.log"

    # --- Kill old instances and clear log ---
    podman exec -t rocm bash -c \
        "pkill -f 'webui.py' 2>/dev/null; pkill -f 'heartlib' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; sleep 1; : > '${app_log}'" || true

    # --- Start HeartMuLa ---
    info "Starting HeartMuLa on port ${app_port}..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         python webui.py --listen \
         >> '${app_log}' 2>&1"

    # --- Wait for Gradio UI to respond (before model load) ---
    info "Waiting for HeartMuLa Gradio API to become ready (up to 300s)..."
    local waited=0 max_wait=300 ready=false
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
        abort "HeartMuLa did not become ready within ${max_wait}s"
    fi
    pass "HeartMuLa Gradio API ready on port ${app_port}"

    # --- Load model via /load_model endpoint ---
    info "Loading HeartMuLa model (may take several minutes on first run)..."
    local load_event_id
    load_event_id=$(podman exec -t rocm bash -c "
        curl -sf -X POST http://localhost:${app_port}/gradio_api/call/load_model \
            -H 'Content-Type: application/json' \
            -d '{\"data\": [\"./ckpt\", \"3B\", false]}' \
            | tr -d '\r'
    " 2>/dev/null \
    | grep -o '"event_id":"[^"]*"' \
    | grep -o '[^:]*$' \
    | tr -d '"') || true

    if [ -z "$load_event_id" ]; then
        podman exec -t rocm bash -c "cat '${app_log}'" 2>/dev/null || true
        abort "HeartMuLa: no event_id returned from /load_model"
    fi

    local load_result
    load_result=$(podman exec -t rocm bash -c "
        curl -sf --max-time 300 \
            http://localhost:${app_port}/gradio_api/call/load_model/${load_event_id} \
        | tr -d '\r'
    " 2>/dev/null) || true

    if echo "$load_result" | grep -qiE 'loaded|success|complete|Model'; then
        pass "HeartMuLa model loaded"
    else
        info "Load result: $load_result"
        # Continue anyway – model may have been loaded silently
        info "Model load status unclear – continuing to generation"
    fi

    # --- Generate a short test song via /generate_music ---
    # min value for max_audio_length_ms is 30000 (30s)
    info "Requesting music generation (30s clip)..."
    local gen_event_id
    gen_event_id=$(podman exec -t rocm bash -c "
        curl -sf -X POST http://localhost:${app_port}/gradio_api/call/generate_music \
            -H 'Content-Type: application/json' \
            -d '{\"data\": [
                \"[Verse]\nThis is a test song\nSimple melody\n\",
                \"piano, simple, pop\",
                30000,
                50,
                1.0,
                1.0
            ]}' | tr -d '\r'
    " 2>/dev/null \
    | grep -o '"event_id":"[^"]*"' \
    | grep -o '[^:]*$' \
    | tr -d '"') || true

    if [ -z "$gen_event_id" ]; then
        podman exec -t rocm bash -c "cat '${app_log}'" 2>/dev/null || true
        abort "HeartMuLa: no event_id returned from /generate_music"
    fi
    info "Generation started (event_id: $gen_event_id) – polling result..."

    # --- Poll result (SSE stream) – up to 600s ---
    local gen_result
    gen_result=$(podman exec -t rocm bash -c "
        curl -sf --max-time 600 \
            http://localhost:${app_port}/gradio_api/call/generate_music/${gen_event_id} \
        | tr -d '\r'
    " 2>/dev/null) || true

    if echo "$gen_result" | grep -qE '\.wav|\.mp3|\.ogg|"path"'; then
        pass "HeartMuLa music generation OK (audio file returned)"
        local audio_path
        audio_path=$(echo "$gen_result" \
            | grep -o '"path":"[^"]*"' | head -1 \
            | sed 's/"path":"//;s/"//') || audio_path=""
        if [ -n "$audio_path" ]; then
            local fsize
            fsize=$(podman exec -t rocm bash -c \
                "stat -c%s '${audio_path}' 2>/dev/null || echo 0" \
                | tr -d '\r\n') || fsize=0
            info "  Audio file: ${audio_path} ($(( ${fsize:-0} / 1024 )) KB)"
        fi
    else
        # Extract last meaningful error line from app log for diagnostics
        local err_line
        err_line=$(podman exec -t rocm bash -c \
            "grep -iE 'error|exception|fatal|traceback' '${app_log}' 2>/dev/null \
             | tail -3" | tr -d '\r') || err_line=""
        [ -n "$err_line" ] && info "  Last error in log: $err_line"
        podman exec -t rocm bash -c "tail -20 '${app_log}'" 2>/dev/null || true
        abort "HeartMuLa generation did not return audio data (event: $(echo "$gen_result" | grep '^event:' | head -1))"
    fi

    # --- Stop server ---
    info "Stopping HeartMuLa..."
    podman exec -t rocm bash -c \
        "pkill -f 'webui.py' 2>/dev/null; pkill -f 'heartlib' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c \
            "fuser ${app_port}/tcp > /dev/null 2>&1" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "HeartMuLa stopped"

    info "Phase 10 DONE"
}

main() { phase10_verify_heartmula; }
main "$@"
