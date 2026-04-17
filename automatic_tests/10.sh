#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 10: RUN AND VERIFY – ACE-Step-1.5 (text-to-music)
# ============================================================
phase10_verify_ace_step_1_5() {
    info "============================================="
    info "PHASE 10: RUN AND VERIFY (ACE-Step-1.5)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local app_dir="/AI/ACE-Step-1.5"
    local app_port=7860
    local app_log="/tmp/acestep15_server.log"

    # --- Kill old instances and clear log ---
    podman exec -t rocm bash -c \
        "pkill -f 'acestep_v15_pipeline' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; sleep 1; : > '${app_log}'" || true

    # --- Start ACE-Step-1.5 ---
    info "Starting ACE-Step-1.5 on port ${app_port}..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         ACESTEP_LM_BACKEND=pt MIOPEN_FIND_MODE=FAST \
         python -m acestep.acestep_v15_pipeline \
             --server-name 0.0.0.0 \
             --port ${app_port} \
             --config_path acestep-v15-turbo \
             --lm_model_path acestep-5Hz-lm-4B \
             --init_service true \
             --backend pt \
         >> '${app_log}' 2>&1"

    # --- Wait for Gradio API (up to 600s – models download on first run) ---
    info "Waiting for ACE-Step-1.5 Gradio API to become ready (up to 600s)..."
    local waited=0 max_wait=600 ready=false
    while [ $waited -lt $max_wait ]; do
        if podman exec -t rocm bash -c \
               "curl -sf http://localhost:${app_port}/gradio_api/info \
                | grep -q '\"named_endpoints\"'" 2>/dev/null; then
            ready=true; break
        fi
        sleep 10; waited=$((waited + 10))
        info "  ...waiting ($waited/${max_wait}s)"
    done
    if ! $ready; then
        podman exec -t rocm bash -c "cat '${app_log}'" 2>/dev/null || true
        abort "ACE-Step-1.5 did not become ready within ${max_wait}s"
    fi
    pass "ACE-Step-1.5 Gradio API ready on port ${app_port}"

    # --- Generate a short test song via /generation_wrapper ---
    # Parameters: 64 total (59 visible + 5 hidden gr.State components)
    # DiT Inference Steps max = 20 for acestep-v15-turbo config
    # Audio Duration = 30s (minimum)
    # Hidden gr.State positions: index 42 (after CoT Language Detection),
    #   and indices 60-63 (at the end)
    info "Requesting music generation (30s clip, DiT steps=20)..."
    local gen_event_id
    gen_event_id=$(podman exec -t rocm bash -c "
        curl -sf -X POST http://localhost:${app_port}/gradio_api/call/generation_wrapper \
            -H 'Content-Type: application/json' \
            -d '{\"data\": [
                \"pop, simple, guitar\",
                \"[Verse]\\nThis is a test song\\nWith a simple melody\",
                120, \"C Major\", \"4/4\", \"en\",
                20, 7.0, true, \"\", null, 30, 1, null, \"\",
                0, -1, \"\", 0.0, 0.0, \"text2music\",
                false, 0.0, 1.0, 3.0, \"ode\", \"euler\", 0.0, 0.0, \"\",
                \"wav\", \"128k\", 48000, 1.0, false, 1.0, 0, 1.0, \"\",
                false, false, true,
                null,
                false, false, false, false, 0.01, 1,
                \"woodwinds\", [\"woodwinds\"],
                false, -10.0, 0.0, 0.0, -0.2, 0.5, \"conservative\", 0.0, false,
                null, null, null, null
            ]}' | tr -d '\r'
    " 2>/dev/null \
    | grep -o '"event_id":"[^"]*"' \
    | grep -o '[^:]*$' \
    | tr -d '"') || true

    if [ -z "$gen_event_id" ]; then
        podman exec -t rocm bash -c "cat '${app_log}'" 2>/dev/null || true
        abort "ACE-Step-1.5: no event_id returned from /generation_wrapper"
    fi
    info "Generation started (event_id: $gen_event_id) – polling result (up to 300s)..."

    # --- Poll result (SSE stream) ---
    local gen_result
    gen_result=$(podman exec -t rocm bash -c "
        curl -sf --max-time 300 \
            http://localhost:${app_port}/gradio_api/call/generation_wrapper/${gen_event_id} \
        | tr -d '\r'
    " 2>/dev/null) || true

    if echo "$gen_result" | grep -qE '\.wav|\.mp3|\.ogg|"path"'; then
        pass "ACE-Step-1.5 music generation OK (audio file returned)"
        local audio_path
        audio_path=$(echo "$gen_result" \
            | grep -o '"path":"[^"]*\.wav[^"]*"' | head -1 \
            | sed 's/"path":"//;s/"//') || audio_path=""
        if [ -n "$audio_path" ]; then
            local fsize
            fsize=$(podman exec -t rocm bash -c \
                "stat -c%s '${audio_path}' 2>/dev/null || echo 0" \
                | tr -d '\r\n') || fsize=0
            info "  Audio file: ${audio_path} ($(( ${fsize:-0} / 1024 )) KB)"
            if [ "${fsize:-0}" -lt 102400 ]; then
                abort "ACE-Step-1.5: audio file suspiciously small (${fsize} bytes)"
            fi
        fi
    else
        local err_line
        err_line=$(podman exec -t rocm bash -c \
            "grep -iE 'error|exception|fatal|traceback' '${app_log}' 2>/dev/null \
             | tail -3" | tr -d '\r') || err_line=""
        [ -n "$err_line" ] && info "  Last error in log: $err_line"
        podman exec -t rocm bash -c "tail -20 '${app_log}'" 2>/dev/null || true
        abort "ACE-Step-1.5 generation did not return audio data"
    fi

    # --- Stop server ---
    info "Stopping ACE-Step-1.5..."
    podman exec -t rocm bash -c \
        "pkill -f 'acestep_v15_pipeline' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c \
            "fuser ${app_port}/tcp > /dev/null 2>&1" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "ACE-Step-1.5 stopped"

    info "Phase 10 DONE"
}

main() { phase10_verify_ace_step_1_5; }
main "$@"
