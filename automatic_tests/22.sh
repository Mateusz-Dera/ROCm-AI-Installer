#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 22: RUN AND VERIFY – OmniVoice
#   Step 1: Voice Design  (no reference) → save output as ref
#   Step 2: Voice Clone   (use step-1 output as reference)
# ============================================================
phase22_verify_omnivoice() {
    info "============================================="
    info "PHASE 22: RUN AND VERIFY (OmniVoice)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local app_dir="/AI/OmniVoice"
    local app_port=7860
    local app_log="/tmp/omnivoice_server.log"
    local ref_wav="/tmp/omnivoice_ref.wav"
    local GEN_TEXT="OmniVoice text to speech synthesis is working correctly."

    # --- Kill old instances and clear log ---
    podman exec -t rocm bash -c \
        "pkill -f 'omnivoice-demo' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; sleep 1; : > '${app_log}'" || true

    # --- Start OmniVoice ---
    info "Starting OmniVoice on port ${app_port}..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         omnivoice-demo --ip 0.0.0.0 --port ${app_port} \
         >> '${app_log}' 2>&1"

    # --- Wait for Gradio API to become ready (model download + load) ---
    info "Waiting for OmniVoice Gradio API to become ready (up to 600s)..."
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
        abort "OmniVoice did not become ready within ${max_wait}s"
    fi
    pass "OmniVoice Gradio API ready on port ${app_port}"

    # ================================================================
    # STEP 1 – Voice Design (no reference audio)
    # Endpoint: /_design_fn
    # Inputs (15): text, lang, ns, gs, dn, sp, du, pp, po, 6×group
    # ================================================================
    info "--- Step 1: Voice Design (no reference) ---"
    info "Requesting Voice Design: \"${GEN_TEXT}\"..."

    local event_id
    event_id=$(podman exec -t rocm bash -c "
        curl -sf -X POST http://localhost:${app_port}/gradio_api/call/_design_fn \
            -H 'Content-Type: application/json' \
            -d '{\"data\": [
                \"${GEN_TEXT}\",
                \"Auto\",
                32,
                2.0,
                true,
                1.0,
                null,
                true,
                true,
                \"Auto\",
                \"Auto\",
                \"Auto\",
                \"Auto\",
                \"Auto\",
                \"Auto\"
            ]}' | tr -d '\r'
    " 2>/dev/null \
    | grep -o '\"event_id\":\"[^\"]*\"' \
    | grep -o '[^:]*$' \
    | tr -d '"') || true

    if [ -z "$event_id" ]; then
        podman exec -t rocm bash -c "tail -20 '${app_log}'" 2>/dev/null || true
        abort "OmniVoice: no event_id returned from /_design_fn"
    fi
    info "Voice Design started (event_id: $event_id) – polling result (up to 300s)..."

    local design_result
    design_result=$(podman exec -t rocm bash -c "
        curl -sf --max-time 300 \
            http://localhost:${app_port}/gradio_api/call/_design_fn/${event_id} \
        | tr -d '\r'
    " 2>/dev/null) || true

    if ! echo "$design_result" | grep -q '"path"'; then
        info "Raw result: $design_result"
        podman exec -t rocm bash -c "tail -20 '${app_log}'" 2>/dev/null || true
        abort "OmniVoice Voice Design did not return audio data"
    fi
    pass "OmniVoice Voice Design OK (audio returned)"

    # Extract audio path and copy to persistent location
    local audio_path
    audio_path=$(echo "$design_result" \
        | grep -o '"path":"[^"]*"' | head -1 \
        | sed 's/"path":"//;s/"//') || audio_path=""

    if [ -z "$audio_path" ]; then
        info "Raw result: $design_result"
        abort "OmniVoice: could not extract audio path from Voice Design result"
    fi
    info "  Voice Design output: ${audio_path}"

    # Verify size
    local fsize
    fsize=$(podman exec -t rocm bash -c \
        "stat -c%s '${audio_path}' 2>/dev/null || echo 0" \
        | tr -d '\r\n') || fsize=0
    if [ "${fsize:-0}" -lt 1024 ]; then
        abort "OmniVoice: Voice Design audio suspiciously small (${fsize} bytes)"
    fi
    info "  Size: $(( ${fsize} / 1024 )) KB"

    # Copy to persistent location for use as reference
    podman exec -t rocm bash -c "cp '${audio_path}' '${ref_wav}'" || \
        abort "OmniVoice: failed to copy reference audio to ${ref_wav}"
    pass "Voice Design audio saved as reference: ${ref_wav}"

    # ================================================================
    # STEP 2 – Voice Clone (use step-1 output as reference)
    # Endpoint: /_clone_fn
    # Inputs (11): text, lang, ref_audio, ref_text, ns, gs, dn, sp, du, pp, po
    # ================================================================
    info "--- Step 2: Voice Clone (using generated audio as reference) ---"

    # Upload reference audio via /gradio_api/upload
    info "Uploading reference audio to OmniVoice..."
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
        abort "OmniVoice: failed to upload reference audio"
    fi
    info "Reference audio uploaded: ${uploaded_path}"

    info "Requesting Voice Clone: \"${GEN_TEXT}\"..."
    event_id=$(podman exec -t rocm bash -c "
        curl -sf -X POST http://localhost:${app_port}/gradio_api/call/_clone_fn \
            -H 'Content-Type: application/json' \
            -d '{\"data\": [
                \"${GEN_TEXT}\",
                \"Auto\",
                {\"path\": \"${uploaded_path}\", \"meta\": {\"_type\": \"gradio.FileData\"}},
                \"\",
                32,
                2.0,
                true,
                1.0,
                null,
                true,
                true
            ]}' | tr -d '\r'
    " 2>/dev/null \
    | grep -o '\"event_id\":\"[^\"]*\"' \
    | grep -o '[^:]*$' \
    | tr -d '"') || true

    if [ -z "$event_id" ]; then
        podman exec -t rocm bash -c "tail -20 '${app_log}'" 2>/dev/null || true
        abort "OmniVoice: no event_id returned from /_clone_fn"
    fi
    info "Voice Clone started (event_id: $event_id) – polling result (up to 300s)..."

    local clone_result
    clone_result=$(podman exec -t rocm bash -c "
        curl -sf --max-time 300 \
            http://localhost:${app_port}/gradio_api/call/_clone_fn/${event_id} \
        | tr -d '\r'
    " 2>/dev/null) || true

    if echo "$clone_result" | grep -q '"path"'; then
        pass "OmniVoice Voice Clone OK (audio returned)"
        local clone_path
        clone_path=$(echo "$clone_result" \
            | grep -o '"path":"[^"]*"' | head -1 \
            | sed 's/"path":"//;s/"//') || clone_path=""
        if [ -n "$clone_path" ]; then
            fsize=$(podman exec -t rocm bash -c \
                "stat -c%s '${clone_path}' 2>/dev/null || echo 0" \
                | tr -d '\r\n') || fsize=0
            info "  Clone output: ${clone_path} ($(( ${fsize:-0} / 1024 )) KB)"
            if [ "${fsize:-0}" -lt 1024 ]; then
                abort "OmniVoice: Voice Clone audio suspiciously small (${fsize} bytes)"
            fi
        fi
        pass "Voice Clone audio size OK"
    else
        info "Raw result: $clone_result"
        podman exec -t rocm bash -c "tail -20 '${app_log}'" 2>/dev/null || true
        abort "OmniVoice Voice Clone did not return audio data"
    fi

    # --- Stop server ---
    info "Stopping OmniVoice..."
    podman exec -t rocm bash -c \
        "pkill -f 'omnivoice-demo' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c \
            "fuser ${app_port}/tcp > /dev/null 2>&1" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "OmniVoice stopped"

    info "Phase 22 DONE"
}

main() { phase22_verify_omnivoice; }
main "$@"
