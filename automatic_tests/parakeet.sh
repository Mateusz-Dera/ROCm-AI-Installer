#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

APP_DIR="/AI/parakeet"
APP_PORT=7860
APP_LOG="/tmp/parakeet_server.log"
PROC_PAT="python app.py"
WER_LIMIT=0.15

_cleanup() {
    stop_app "$PROC_PAT" "$APP_PORT" > /dev/null 2>&1 || true
    reset_container || true
}
trap _cleanup EXIT INT TERM

test_parakeet() {
    info "============================================="
    info "TEST: Parakeet (speech recognition)"
    info "============================================="

    require_container
    clean_hf_incomplete

    stop_app "$PROC_PAT" "$APP_PORT"
    run_install "Parakeet" install_parakeet "$APP_DIR"

    local torch_info
    torch_info=$(ctr "cd ${APP_DIR} && source .venv/bin/activate && \
        python -c 'import torch; print(torch.__version__, torch.cuda.is_available())'")
    case "$torch_info" in
        *rocm*True*) pass "ROCm torch sees the GPU (${torch_info%% *})" ;;
        *rocm*)      abort "Parakeet: torch does not see the GPU (${torch_info})" ;;
        *)           abort "Parakeet: torch is not the ROCm build (${torch_info})" ;;
    esac

    require_gpu_pin "Parakeet" parakeet

    start_app parakeet "$APP_LOG"

    info "Waiting for the Gradio API..."
    wait_for_http_or_abort "Parakeet" \
        "curl -sf http://localhost:${APP_PORT}/gradio_api/info -o /dev/null" \
        "$PROC_PAT" "$APP_LOG" 900 "$APP_DIR"
    pass "Gradio API ready on port ${APP_PORT}"

    if ! listens_on_all_interfaces "$APP_PORT"; then
        fail "  Listening addresses for port ${APP_PORT}: $(port_listen_addrs "$APP_PORT" | tr '\n' ' ')"
        abort "Parakeet: not listening on 0.0.0.0:${APP_PORT}"
    fi
    pass "Listening on 0.0.0.0:${APP_PORT}"

    info "Transcribing the reference sample..."
    podman cp "${TESTS_DIR}/assets/reference_speech.wav" "rocm:/tmp/reference_speech.wav" \
        || abort "Parakeet: failed to copy the reference sample into the container"

    local uploaded
    uploaded=$(gradio_upload "$APP_PORT" /tmp/reference_speech.wav) \
        || abort "Parakeet: upload of the reference sample failed"
    [ -n "$uploaded" ] || abort "Parakeet: upload returned no path"

    local sse
    sse=$(gradio_call "$APP_PORT" transcribe \
          "{\"data\": [{\"path\": \"${uploaded}\", \"meta\": {\"_type\": \"gradio.FileData\"}}]}" 300) \
        || abort "Parakeet: /transcribe did not return an event_id"

    if ! printf '%s' "$sse" | grep -q '^event: complete'; then
        fail "  SSE: $(printf '%s' "$sse" | head -5 | tr '\n' ' ')"
        dump_lines "tail -30 '${APP_LOG}'"
        abort "Parakeet: /transcribe returned no complete event"
    fi

    local payload transcript stats
    payload=$(gradio_complete_data "$sse")
    transcript=$(printf '%s' "$payload" | python3 -c 'import sys,json; print(json.load(sys.stdin)[0])') \
        || abort "Parakeet: could not parse the transcription result"
    stats=$(printf '%s' "$payload" | python3 -c 'import sys,json; print(json.load(sys.stdin)[1])') \
        || stats=""

    [ -n "$transcript" ] || abort "Parakeet: the transcription is empty"
    info "  Transcript: \"${transcript}\""
    info "  ${stats}"

    local wer_json wer
    wer_json=$(printf '%s' "$transcript" \
               | python3 "${TESTS_DIR}/helpers/wer.py" "${TESTS_DIR}/assets/reference_speech.txt") \
        || abort "Parakeet: WER computation failed"
    wer=$(printf '%s' "$wer_json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["wer"])')
    info "  ${wer_json}"

    if ! python3 -c "import sys; sys.exit(0 if $wer <= $WER_LIMIT else 1)"; then
        abort "Parakeet: WER ${wer} exceeds the ${WER_LIMIT} limit - the transcription does not match the reference"
    fi
    pass "Transcription matches the reference (WER ${wer})"

    local vram
    vram=$(printf '%s' "$stats" | grep -oE 'Peak VRAM: [0-9.]+' | grep -oE '[0-9.]+$') || vram=""
    if [ -z "$vram" ] || ! python3 -c "import sys; sys.exit(0 if $vram > 0 else 1)" 2>/dev/null; then
        abort "Parakeet: no VRAM was allocated - the model did not run on the GPU"
    fi
    pass "Ran on the GPU (peak VRAM ${vram} GB)"

    local rtf
    rtf=$(printf '%s' "$stats" | grep -oE 'Real-time factor: [0-9.]+' | grep -oE '[0-9.]+$') || rtf=""
    [ -n "$rtf" ] && pass "Real-time factor ${rtf}x"

    if ctr "grep -qiE 'falling back|running on cpu' '${APP_LOG}'"; then
        dump_lines "grep -iE 'falling back|running on cpu' '${APP_LOG}'"
        abort "Parakeet: the log reports a CPU fallback"
    fi
    pass "No CPU fallback in the log"

    stop_app "$PROC_PAT" "$APP_PORT"
    pass "Parakeet stopped"

    ctr "rm -f /tmp/reference_speech.wav '${APP_LOG}'"
    info "Test parakeet DONE"
}

main() { test_parakeet; }
main "$@"
