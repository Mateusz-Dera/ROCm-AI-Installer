#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

APP_DIR="/AI/soprano-rocm"
APP_LOG="/tmp/soprano_server.log"
PROC_PAT="soprano-webui"
GPU_PAT="soprano-webui|VLLM::"
WER_LIMIT=0.25

_cleanup() {
    stop_app "$PROC_PAT" "" > /dev/null 2>&1 || true
    reset_container || true
}
trap _cleanup EXIT INT TERM

test_soprano() {
    info "============================================="
    info "TEST: Soprano (voice generation)"
    info "============================================="

    require_container
    require_parakeet
    clean_hf_incomplete

    stop_app "$PROC_PAT" ""
    run_install "Soprano" install_soprano "$APP_DIR"

    local torch_info
    torch_info=$(ctr "cd ${APP_DIR} && source .venv/bin/activate && \
        python -c 'import torch; print(torch.__version__, torch.cuda.is_available())'")
    case "$torch_info" in
        *rocm*True*) pass "ROCm torch sees the GPU (${torch_info%% *})" ;;
        *rocm*)      abort "Soprano: torch does not see the GPU (${torch_info})" ;;
        *)           abort "Soprano: torch is not the ROCm build (${torch_info})" ;;
    esac

    require_gpu_pin "Soprano" soprano-rocm

    start_app soprano-rocm "$APP_LOG"

    info "Waiting for the model to load and Gradio to pick a port..."
    wait_for_http_or_abort "Soprano" \
        "grep -q 'Starting Gradio interface on port' '${APP_LOG}'" \
        "$PROC_PAT" "$APP_LOG" 1800 "$APP_DIR"

    local app_port
    app_port=$(ctr "grep -oE 'Starting Gradio interface on port [0-9]+' '${APP_LOG}' \
                    | tail -1 | grep -oE '[0-9]+$'")
    [ -n "$app_port" ] || abort "Soprano: could not read the port from the log"
    pass "Model loaded, Gradio announced port ${app_port}"

    info "Waiting for the Gradio API on port ${app_port}..."
    wait_for_http_or_abort "Soprano" \
        "curl -sf http://localhost:${app_port}/gradio_api/info -o /dev/null" \
        "$PROC_PAT" "$APP_LOG" 600 "$APP_DIR"
    pass "Gradio API ready on port ${app_port}"

    if ! listens_on_all_interfaces "$app_port"; then
        fail "  Listening addresses for port ${app_port}: $(port_listen_addrs "$app_port" | tr '\n' ' ')"
        abort "Soprano: not listening on 0.0.0.0:${app_port}"
    fi
    pass "Listening on 0.0.0.0:${app_port}"

    require_gpu_process "Soprano" "$GPU_PAT"

    local text
    text=$(tr -d '\n' < "${TESTS_DIR}/assets/tts_design.txt")

    info "--- Voice generation ---"
    local sse
    sse=$(gradio_call "$app_port" generate_speech \
          "{\"data\": [\"${text}\", 0.0, 0.95, 1.2, 1, false]}" 600) \
        || abort "Soprano: /generate_speech did not return an event_id"

    if ! printf '%s' "$sse" | grep -q '^event: complete'; then
        fail "  SSE: $(printf '%s' "$sse" | head -5 | tr '\n' ' ')"
        dump_lines "tail -30 '${APP_LOG}'"
        abort "Soprano: no complete event in the SSE stream"
    fi

    local wav status
    wav=$(gradio_complete_data "$sse" \
          | python3 -c 'import sys,json; d=json.load(sys.stdin); print((d[0] or {}).get("path",""))') \
        || abort "Soprano: could not parse the result"
    status=$(gradio_complete_data "$sse" \
             | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[1] if len(d)>1 else "")') \
        || status=""
    [ -n "$status" ] && info "  Status: ${status}"
    [ -n "$wav" ] || abort "Soprano: no audio path in the complete event"

    container_file_exists "$wav" || abort "Soprano: the audio file ${wav} does not exist"
    check_speech "Voice generation" "$wav" "${TESTS_DIR}/assets/tts_design.txt" "$WER_LIMIT"

    stop_app "$PROC_PAT" "$app_port"
    pass "Soprano stopped"

    ctr "rm -f '${APP_LOG}'"
    info "Test soprano DONE"
}

main() { test_soprano; }
main "$@"
