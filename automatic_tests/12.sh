#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 12: RUN AND VERIFY – F5-TTS (voice cloning TTS)
# ============================================================
phase12_verify_f5tts() {
    info "============================================="
    info "PHASE 12: RUN AND VERIFY (F5-TTS)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local app_dir="/AI/F5-TTS"
    local app_port=7860
    local app_log="/tmp/f5tts_server.log"
    local soprano_ref="/tmp/soprano_voice_ref.wav"
    local fallback_ref="/AI/F5-TTS/src/f5_tts/infer/examples/basic/basic_ref_en.wav"
    local GEN_TEXT="F5-TTS voice cloning is working correctly with the provided reference audio."

    # --- Kill old instances and clear log ---
    podman exec -t rocm bash -c \
        "pkill -f 'f5-tts_infer' 2>/dev/null; pkill -f 'infer_gradio' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; sleep 1; : > '${app_log}'" || true

    # --- Start F5-TTS ---
    info "Starting F5-TTS on port ${app_port}..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         f5-tts_infer-gradio --host 0.0.0.0 --port ${app_port} \
         >> '${app_log}' 2>&1"

    # --- Wait for Gradio API to become ready (model loads at startup) ---
    info "Waiting for F5-TTS Gradio API to become ready (up to 600s)..."
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
        abort "F5-TTS did not become ready within ${max_wait}s"
    fi
    pass "F5-TTS Gradio API ready on port ${app_port}"

    # --- Select reference WAV (soprano output or built-in fallback) ---
    local ref_wav ref_text
    if podman exec -t rocm bash -c "test -f '${soprano_ref}'" 2>/dev/null; then
        ref_wav="${soprano_ref}"
        ref_text="Hello, this is a test of the soprano speech synthesis system."
        info "Using Soprano reference: ${ref_wav}"
    else
        ref_wav="${fallback_ref}"
        ref_text="Some call me nature, others call me mother nature."
        info "Soprano reference not found – using built-in fallback: ${ref_wav}"
    fi

    # --- Upload reference WAV via /gradio_api/upload ---
    info "Uploading reference WAV to F5-TTS..."
    local upload_response
    upload_response=$(podman exec -t rocm bash -c "
        curl -sf -X POST http://localhost:${app_port}/gradio_api/upload \
            -F 'files=@${ref_wav}' | tr -d '\r'
    " 2>/dev/null) || upload_response=""

    local uploaded_path
    uploaded_path=$(echo "$upload_response" \
        | grep -o '"[^"]*"' | head -1 \
        | tr -d '"') || uploaded_path=""

    if [ -z "$uploaded_path" ]; then
        info "Upload response: $upload_response"
        abort "F5-TTS: failed to upload reference WAV"
    fi
    info "Reference WAV uploaded: ${uploaded_path}"

    # --- Generate speech via /basic_tts ---
    info "Requesting voice cloning: \"${GEN_TEXT}\"..."
    local event_id
    event_id=$(podman exec -t rocm bash -c "
        curl -sf -X POST http://localhost:${app_port}/gradio_api/call/basic_tts \
            -H 'Content-Type: application/json' \
            -d '{\"data\": [
                {\"path\": \"${uploaded_path}\", \"meta\": {\"_type\": \"gradio.FileData\"}},
                \"${ref_text}\",
                \"${GEN_TEXT}\",
                false,
                false,
                42,
                0.15,
                16,
                1.0
            ]}' | tr -d '\r'
    " 2>/dev/null \
    | grep -o '\"event_id\":\"[^\"]*\"' \
    | grep -o '[^:]*$' \
    | tr -d '"') || true

    if [ -z "$event_id" ]; then
        podman exec -t rocm bash -c "tail -20 '${app_log}'" 2>/dev/null || true
        abort "F5-TTS: no event_id returned from /basic_tts"
    fi
    info "Generation started (event_id: $event_id) – polling result..."

    # --- Poll result (SSE stream) – up to 300s ---
    local gen_result
    gen_result=$(podman exec -t rocm bash -c "
        curl -sf --max-time 300 \
            http://localhost:${app_port}/gradio_api/call/basic_tts/${event_id} \
        | tr -d '\r'
    " 2>/dev/null) || true

    local audio_path
    audio_path=$(echo "$gen_result" \
        | grep -oP '"path":\s*"\K[^"]*\.wav[^"]*' | head -1) || audio_path=""

    if [ -z "$audio_path" ]; then
        info "Raw result: $gen_result"
        podman exec -t rocm bash -c "tail -20 '${app_log}'" 2>/dev/null || true
        abort "F5-TTS generation did not return a WAV path"
    fi

    local fsize
    fsize=$(podman exec -t rocm bash -c \
        "stat -c%s '${audio_path}' 2>/dev/null || echo 0" \
        | tr -d '\r\n') || fsize=0
    info "  Output WAV: ${audio_path} ($(( ${fsize:-0} / 1024 )) KB)"
    if [ "${fsize:-0}" -lt 10240 ]; then
        abort "F5-TTS: output WAV suspiciously small (${fsize} bytes)"
    fi
    pass "F5-TTS voice cloning OK (audio returned)"

    # --- Stop server ---
    info "Stopping F5-TTS..."
    podman exec -t rocm bash -c \
        "pkill -f 'f5-tts_infer' 2>/dev/null; pkill -f 'infer_gradio' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c \
            "fuser ${app_port}/tcp > /dev/null 2>&1" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "F5-TTS stopped"

    info "Phase 12 DONE"
}

main() { phase12_verify_f5tts; }
main "$@"
