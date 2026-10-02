#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# server.py sits idle while the engine reads 58-84 GB of experts into RAM
HANG_LIMIT="${HANG_LIMIT:-900}"
source "$TESTS_DIR/common.sh"
source "$TESTS_DIR/lib/llama.sh"

FOLDER="Strata"
APP_DIR="/AI/${FOLDER}"
DATA_DIR="/AI/Strata-data"
LLAMA_PORT=8003
LLAMA_LOG="/tmp/strata_server.log"
SERVER_PROC="serve/server.py"
ENGINE_PROC="strata --serve"
LABEL="Strata"

_stop() {
    stop_app "$SERVER_PROC" ""
    stop_app "$ENGINE_PROC" "$LLAMA_PORT"
}

_cleanup() {
    _stop > /dev/null 2>&1 || true
    reset_container || true
}
trap _cleanup EXIT INT TERM

_health_field() {
    ctr "curl -sf http://localhost:${LLAMA_PORT}/health" \
        | python3 -c "import sys, json; print(json.load(sys.stdin).get('$1', ''))" 2>/dev/null
}

# strata_ask_anthropic <prompt> <expected regex>
strata_ask_anthropic() {
    local prompt="$1" expected="$2" response answer

    response=$(ctr "curl -sf --max-time 600 http://localhost:${LLAMA_PORT}/v1/messages \
        -H 'Content-Type: application/json' -H 'anthropic-version: 2023-06-01' \
        -d '{\"model\": \"${MODEL_ID}\", \"max_tokens\": 256,
             \"messages\": [{\"role\": \"user\", \"content\": \"${prompt}\"}]}'")

    answer=$(printf '%s' "$response" | python3 -c '
import sys, json
blocks = json.load(sys.stdin).get("content") or []
text = " ".join(b.get("text") or "" for b in blocks if b.get("type") == "text").strip()
print(text or " ".join(b.get("thinking") or "" for b in blocks).strip())') || {
        fail "  Response: $(printf '%s' "$response" | head -c 300)"
        dump_lines "tail -30 '${LLAMA_LOG}'"
        abort "${LABEL}: the Anthropic API did not return a message"
    }

    info "  Q: ${prompt}"
    info "  A: \"${answer}\""
    printf '%s' "$answer" | grep -qiE "$expected" \
        || abort "${LABEL}: the Anthropic answer does not match /${expected}/"
    pass "${LABEL}: Anthropic API answers correctly"
}

main() {
    info "============================================="
    info "TEST: Strata (HIP)"
    info "============================================="

    require_container
    _stop

    run_install "$LABEL" install_strata "$APP_DIR"
    require_gpu_pin "$LABEL" "$FOLDER"

    local shards
    shards=$(ctr "find '${DATA_DIR}/models' -name '*.gguf' | wc -l")
    [ "${shards:-0}" -gt 0 ] || abort "${LABEL}: no .gguf files in ${DATA_DIR}/models"
    pass "Model files in ${DATA_DIR}/models (${shards} .gguf)"

    container_file_exists "${APP_DIR}/engine/strata" \
        || abort "${LABEL}: the HIP engine ${APP_DIR}/engine/strata was not built"
    pass "HIP engine built"

    start_app "$FOLDER" "$LLAMA_LOG"

    # setup.py checks the install first, then execv()s into serve/server.py
    info "Waiting for setup.py to hand over to the server..."
    local waited=0
    until [ -n "$(app_pid "$SERVER_PROC")" ]; do
        if [ -z "$(ctr "pgrep -f '[s]etup.sh --yes' | head -1")" ]; then
            dump_lines "tail -40 '${LLAMA_LOG}'"
            abort "${LABEL}: setup.sh exited before starting the server"
        fi
        [ $waited -ge 600 ] && abort "${LABEL}: setup.sh did not start the server in 600s"
        sleep 2; waited=$((waited + 2))
    done
    pass "setup.py started the server (${waited}s)"

    info "Waiting for the server..."
    wait_for_http_or_abort "$LABEL" \
        "curl -sf http://localhost:${LLAMA_PORT}/health -o /dev/null" \
        "$SERVER_PROC" "$LLAMA_LOG" 1800 "$APP_DIR"
    pass "Server ready on port ${LLAMA_PORT}"

    if ! listens_on_all_interfaces "$LLAMA_PORT"; then
        fail "  Listening addresses: $(port_listen_addrs "$LLAMA_PORT" | tr '\n' ' ')"
        abort "${LABEL}: not listening on 0.0.0.0:${LLAMA_PORT}"
    fi
    pass "Listening on 0.0.0.0:${LLAMA_PORT}"

    [ "$(_health_field service)" = "strata" ] \
        || abort "${LABEL}: /health does not report service=strata"
    local ctx
    ctx=$(_health_field max_context)
    [ "$ctx" = "262144" ] || abort "${LABEL}: the context size is ${ctx:-unknown}, not 262144"
    pass "Context size 262144"

    MODEL_ID=$(llama_model_id)
    [ -n "$MODEL_ID" ] || abort "${LABEL}: /v1/models listed no model"
    printf '%s' "$MODEL_ID" | grep -qi 'iq2_xs' \
        || abort "${LABEL}: /v1/models does not serve the IQ2_XS model (got ${MODEL_ID})"
    pass "Model served: ${MODEL_ID}"

    info "--- Generation (OpenAI API) ---"
    llama_ask "$LABEL" "$MODEL_ID" \
        "Name the capital of France. Answer with the city name only." "paris"
    llama_report_speed "$LABEL"

    llama_ask "$LABEL" "$MODEL_ID" \
        "What is 17 plus 25? Answer with the number only." "42"

    info "--- Generation (Anthropic API) ---"
    strata_ask_anthropic "What is the chemical symbol for gold? Answer with the symbol only." "\\bau\\b"

    require_gpu_process "$LABEL" "$ENGINE_PROC"

    _stop
    pass "${LABEL} stopped"

    ctr "rm -f '${LLAMA_LOG}'"
    info "Test strata DONE"
}

main "$@"
