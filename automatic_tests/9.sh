#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 9: RUN AND VERIFY – ACE-Step (text-to-music)
# ============================================================
phase9_verify_acestep() {
    info "============================================="
    info "PHASE 9: RUN AND VERIFY (ACE-Step)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local app_dir="/AI/ACE-Step"
    local app_port=7860
    local app_log="/tmp/acestep_server.log"

    # --- Kill old instances and clear log ---
    podman exec -t rocm bash -c \
        "pkill -f 'acestep' 2>/dev/null; pkill -f 'MIOPEN_FIND_MODE' 2>/dev/null; \
         fuser -k ${app_port}/tcp 2>/dev/null; sleep 1; : > '${app_log}'" || true

    # --- Start ACE-Step ---
    info "Starting ACE-Step on port ${app_port}..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         MIOPEN_FIND_MODE=3 PYTORCH_TUNABLEOP_ENABLED=1 \
         uv run acestep --checkpoint_path ./checkpoints \
             --server_name 0.0.0.0 --bf16 True \
         >> '${app_log}' 2>&1"

    # --- Wait for Gradio API to become ready (model loads at startup) ---
    info "Waiting for ACE-Step Gradio API to become ready (up to 600s)..."
    local waited=0 max_wait=600 ready=false
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
        abort "ACE-Step did not become ready within ${max_wait}s"
    fi
    pass "ACE-Step Gradio API ready on port ${app_port}"

    # --- Generate a short test song via the /__call__ endpoint ---
    # infer_step=20 (faster than default 60), audio_duration=15s
    info "Requesting music generation (15s, 20 infer steps)..."
    local event_id
    event_id=$(podman exec -t rocm bash -c "
        curl -sf -X POST http://localhost:${app_port}/gradio_api/call/__call__ \
            -H 'Content-Type: application/json' \
            -d '{\"data\": [
                \"wav\",
                15,
                \"pop, simple, calm, test\",
                \"[verse]\nThis is a test song\nSimple melody\n\",
                20,
                15.0,
                \"euler\",
                \"apg\",
                10.0,
                null,
                0.5,
                0.0,
                3.0,
                true,
                false,
                true,
                null,
                0.0,
                0.0,
                false,
                0.5,
                null,
                \"none\",
                1.0
            ]}' | tr -d '\r'
    " 2>/dev/null \
    | grep -o '"event_id":"[^"]*"' \
    | grep -o '[^:]*$' \
    | tr -d '"') || true

    if [ -z "$event_id" ]; then
        podman exec -t rocm bash -c "cat '${app_log}'" 2>/dev/null || true
        abort "ACE-Step: no event_id returned from /__call__"
    fi
    info "Generation started (event_id: $event_id) – polling result..."

    # --- Poll result (SSE stream) – up to 600s ---
    local gen_result
    gen_result=$(podman exec -t rocm bash -c "
        curl -sf --max-time 600 \
            http://localhost:${app_port}/gradio_api/call/__call__/${event_id} \
        | tr -d '\r'
    " 2>/dev/null) || true

    if echo "$gen_result" | grep -qE '\.wav|\.mp3|\.ogg|"path"'; then
        pass "ACE-Step music generation OK (audio file returned)"
        # Extract and log the file path
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
        info "Raw generation result: $gen_result"
        podman exec -t rocm bash -c "cat '${app_log}'" 2>/dev/null || true
        abort "ACE-Step generation did not return audio data"
    fi

    # --- Stop server ---
    info "Stopping ACE-Step..."
    podman exec -t rocm bash -c \
        "pkill -f 'acestep' 2>/dev/null; pkill -f 'MIOPEN_FIND_MODE' 2>/dev/null; \
         fuser -k ${app_port}/tcp 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c \
            "fuser ${app_port}/tcp > /dev/null 2>&1" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "ACE-Step stopped"

    info "Phase 9 DONE"
}

main() { phase9_verify_acestep; }
main "$@"
