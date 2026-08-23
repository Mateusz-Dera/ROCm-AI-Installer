#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

APP_DIR="/AI/OmniVoice"
APP_PORT=7860
APP_LOG="/tmp/omnivoice_server.log"
PROC_PAT="omnivoice-demo"
WER_LIMIT=0.25

_cleanup() {
    stop_app "$PROC_PAT" "$APP_PORT" > /dev/null 2>&1 || true
    reset_container || true
}
trap _cleanup EXIT INT TERM

_generate() {
    local label="$1" endpoint="$2" payload="$3" expected="$4"

    info "--- ${label} ---"
    local sse
    sse=$(gradio_call "$APP_PORT" "$endpoint" "$payload" 600) \
        || abort "${label}: ${endpoint} did not return an event_id"

    if ! printf '%s' "$sse" | grep -q '^event: complete'; then
        fail "  SSE: $(printf '%s' "$sse" | head -5 | tr '\n' ' ')"
        dump_lines "tail -30 '${APP_LOG}'"
        abort "${label}: no complete event in the SSE stream"
    fi

    local wav
    wav=$(gradio_complete_data "$sse" \
          | python3 -c 'import sys,json; d=json.load(sys.stdin); print((d[0] or {}).get("path",""))') \
        || abort "${label}: could not parse the result"
    [ -n "$wav" ] || abort "${label}: no audio path in the complete event"

    container_file_exists "$wav" || abort "${label}: the audio file ${wav} does not exist"
    check_speech "$label" "$wav" "$expected" "$WER_LIMIT"
}

test_omnivoice() {
    info "============================================="
    info "TEST: OmniVoice (voice generation + voice cloning)"
    info "============================================="

    require_container
    require_parakeet
    clean_hf_incomplete

    stop_app "$PROC_PAT" "$APP_PORT"
    run_install "OmniVoice" install_omnivoice "$APP_DIR"

    local torch_info
    torch_info=$(ctr "cd ${APP_DIR} && source .venv/bin/activate && \
        python -c 'import torch; print(torch.__version__, torch.cuda.is_available())'")
    case "$torch_info" in
        *rocm*True*) pass "ROCm torch sees the GPU (${torch_info%% *})" ;;
        *rocm*)      abort "OmniVoice: torch does not see the GPU (${torch_info})" ;;
        *)           abort "OmniVoice: torch is not the ROCm build (${torch_info})" ;;
    esac

    require_gpu_pin "OmniVoice" OmniVoice

    start_app OmniVoice "$APP_LOG"

    info "Waiting for the Gradio API (model download on first run)..."
    wait_for_http_or_abort "OmniVoice" \
        "curl -sf http://localhost:${APP_PORT}/gradio_api/info -o /dev/null" \
        "$PROC_PAT" "$APP_LOG" 1800 "$APP_DIR"
    pass "Gradio API ready on port ${APP_PORT}"

    if ! listens_on_all_interfaces "$APP_PORT"; then
        fail "  Listening addresses for port ${APP_PORT}: $(port_listen_addrs "$APP_PORT" | tr '\n' ' ')"
        abort "OmniVoice: not listening on 0.0.0.0:${APP_PORT}"
    fi
    pass "Listening on 0.0.0.0:${APP_PORT}"

    local design_text clone_text ref_text
    design_text=$(tr -d '\n' < "${TESTS_DIR}/assets/tts_design.txt")
    clone_text=$(tr -d '\n' < "${TESTS_DIR}/assets/tts_clone.txt")
    ref_text=$(tr -d '\n' < "${TESTS_DIR}/assets/reference_speech.txt")

    _generate "Voice Design" _design_fn \
        "{\"data\": [\"${design_text}\", \"Auto\", 32, 2.0, true, 1.0, null, true, true, \
                     \"Auto\", \"Auto\", \"Auto\", \"Auto\", \"Auto\", \"Auto\"]}" \
        "${TESTS_DIR}/assets/tts_design.txt"

    require_gpu_process "OmniVoice" "$PROC_PAT"

    info "Uploading the reference voice..."
    podman cp "${TESTS_DIR}/assets/reference_speech.wav" "rocm:/tmp/reference_speech.wav" \
        || abort "OmniVoice: failed to copy the reference sample into the container"
    local ref_upload
    ref_upload=$(gradio_upload "$APP_PORT" /tmp/reference_speech.wav) \
        || abort "OmniVoice: reference upload failed"
    [ -n "$ref_upload" ] || abort "OmniVoice: reference upload returned no path"

    local ref_file="{\"path\": \"${ref_upload}\", \"meta\": {\"_type\": \"gradio.FileData\"}}"

    _generate "Voice Clone" _clone_fn \
        "{\"data\": [\"${clone_text}\", \"Auto\", ${ref_file}, \"${ref_text}\", \"\", \
                     32, 2.0, true, 1.0, null, true, true]}" \
        "${TESTS_DIR}/assets/tts_clone.txt"

    stop_app "$PROC_PAT" "$APP_PORT"
    pass "OmniVoice stopped"

    ctr "rm -f /tmp/reference_speech.wav '${APP_LOG}'"
    info "Test omnivoice DONE"
}

main() { test_omnivoice; }
main "$@"
