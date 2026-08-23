#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

APP_DIR="/AI/koboldcpp-rocm"
APP_PORT=5001
APP_LOG="/tmp/koboldcpp_server.log"
PROC_PAT="koboldcpp"
KB_GPU_CLAUSE=""

_cleanup() {
    stop_app "$PROC_PAT" "$APP_PORT" > /dev/null 2>&1 || true
    reset_container || true
}
trap _cleanup EXIT INT TERM

_kb_start() {
    local extra="$1"
    stop_app "$PROC_PAT" "$APP_PORT"
    ctr ": > '${APP_LOG}'"
    podman exec -d rocm bash -c "cd ${APP_DIR} && ${KB_GPU_CLAUSE} source .venv/bin/activate && \
        uv run koboldcpp.py --model '${TEXT_MODEL_PATH}' --draftmodel '${TEXT_DRAFT_PATH}' \
            --skiplauncher --usecuda --gpulayers 99 --contextsize 262144 \
            --host 0.0.0.0 --port ${APP_PORT} ${extra} \
        >> '${APP_LOG}' 2>&1" > /dev/null

    wait_for_http_or_abort "KoboldCPP" \
        "curl -sf http://localhost:${APP_PORT}/api/extra/version -o /dev/null" \
        "$PROC_PAT" "$APP_LOG" 900 "$APP_DIR"
}

_kb_kv_mib() {
    ctr "grep -oE 'KV buffer size = *[0-9.]+ MiB' '${APP_LOG}' | grep -oE '[0-9.]+'" \
        | python3 -c 'import sys; print(round(sum(float(x) for x in sys.stdin if x.strip()), 2))'
}

_kb_ask() {
    local label="$1" prompt="$2" expected="$3" max_tokens="${4:-64}"

    local response
    response=$(ctr "curl -sf --max-time 600 http://localhost:${APP_PORT}/v1/chat/completions \
        -H 'Content-Type: application/json' \
        -d '{\"model\": \"koboldcpp\",
             \"messages\": [{\"role\": \"user\", \"content\": \"${prompt}\"}],
             \"max_tokens\": ${max_tokens}, \"temperature\": 0}'")

    if ! printf '%s' "$response" | grep -q '"choices"'; then
        fail "  Response: $(printf '%s' "$response" | head -c 300)"
        dump_lines "tail -30 '${APP_LOG}'"
        abort "${label}: the API did not return a completion"
    fi

    local answer
    answer=$(printf '%s' "$response" | python3 -c '
import sys, json
m = json.load(sys.stdin)["choices"][0]["message"]
print((m.get("content") or m.get("reasoning_content") or "").strip())') \
        || abort "${label}: could not parse the answer"

    info "  Q: ${prompt}"
    info "  A: \"$(printf '%s' "$answer" | head -c 160)\""

    [ -n "$answer" ] || abort "${label}: the model returned an empty answer"
    printf '%s' "$answer" | grep -qiE "$expected" \
        || abort "${label}: the answer does not match /${expected}/ - the model is answering noise"
    pass "${label}: correct answer"
}

_kb_report_speed() {
    local label="${1:-}"
    local perf gen prompt tokens
    perf=$(ctr "curl -sf http://localhost:${APP_PORT}/api/extra/perf")
    [ -n "$perf" ] || abort "KoboldCPP: /api/extra/perf returned nothing"

    gen=$(printf '%s' "$perf" | python3 -c 'import sys,json; print(round(json.load(sys.stdin)["last_eval_speed"],2))')
    prompt=$(printf '%s' "$perf" | python3 -c 'import sys,json; print(round(json.load(sys.stdin)["last_process_speed"],2))')
    tokens=$(printf '%s' "$perf" | python3 -c 'import sys,json; print(json.load(sys.stdin)["last_token_count"])')

    python3 -c "import sys; sys.exit(0 if $gen > 0 and $tokens >= 10 else 1)" \
        || abort "KoboldCPP: speed measured over only ${tokens} tokens (${gen} tok/s) - too few to mean anything"
    pass "KoboldCPP${label:+ ${label}}: ${gen} tok/s generated over ${tokens} tokens, ${prompt} tok/s prompt"

    local drafted rejected
    drafted=$(printf '%s' "$perf" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("last_draft_success",0))')
    rejected=$(printf '%s' "$perf" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("last_draft_failed",0))')
    [ "${drafted:-0}" -gt 0 ] 2>/dev/null \
        || abort "KoboldCPP: speculative decoding produced no accepted draft tokens (${drafted} accepted, ${rejected} rejected)"
    pass "KoboldCPP${label:+ ${label}}: MTP speculation active (${drafted} draft tokens accepted, ${rejected} rejected)"
}

test_koboldcpp() {
    info "============================================="
    info "TEST: KoboldCPP (text generation + MTP)"
    info "============================================="

    require_container
    clean_hf_incomplete
    require_text_model

    stop_app "$PROC_PAT" "$APP_PORT"
    run_install "KoboldCPP" install_koboldcpp "$APP_DIR"
    require_gpu_pin "KoboldCPP" koboldcpp-rocm

    container_file_exists "${APP_DIR}/koboldcpp_hipblas.so" \
        || abort "KoboldCPP: koboldcpp_hipblas.so missing - the HIP backend was not built"
    pass "HIP backend built (koboldcpp_hipblas.so)"

    local pin; pin=$(app_gpu_clause koboldcpp-rocm)
    KB_GPU_CLAUSE="${pin:+${pin} &&}"
    info "GPU pin taken from run.sh: ${pin:-none}"

    info "--- Default KV cache (f16) ---"
    _kb_start ""
    pass "Server ready on port ${APP_PORT}"

    if ! listens_on_all_interfaces "$APP_PORT"; then
        fail "  Listening addresses: $(port_listen_addrs "$APP_PORT" | tr '\n' ' ')"
        abort "KoboldCPP: not listening on 0.0.0.0:${APP_PORT}"
    fi
    pass "Listening on 0.0.0.0:${APP_PORT}"

    ctr "grep -q 'Initializing dynamic library: koboldcpp_hipblas.so' '${APP_LOG}'" \
        || abort "KoboldCPP: the server did not load koboldcpp_hipblas.so"
    pass "Server running on the HIP backend"

    ctr "grep -qE 'flash_attn + *= *enabled' '${APP_LOG}'" \
        || abort "KoboldCPP: flash attention is not enabled"
    pass "Flash attention enabled"

    local served
    served=$(ctr "curl -sf http://localhost:${APP_PORT}/api/v1/model" \
             | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"])')
    printf '%s' "$served" | grep -q "${LLAMA_TQ_MODEL%.gguf}" \
        || abort "KoboldCPP: serving '${served}' instead of ${LLAMA_TQ_MODEL%.gguf}"
    pass "Model served: ${served}"

    ctr "grep -q 'loaded meta data.*${LLAMA_TQ_MTP}' '${APP_LOG}'" \
        || abort "KoboldCPP: the MTP draft ${LLAMA_TQ_MTP} was not loaded"
    pass "MTP draft loaded (${LLAMA_TQ_MTP})"

    _kb_ask "KoboldCPP" "Name the capital of France. Answer with the city name only." "paris"
    _kb_ask "KoboldCPP" "What is 17 plus 25? Answer with the number only." "42"
    _kb_ask "KoboldCPP" "List the first eight prime numbers, separated by commas." \
            "2.*3.*5.*7.*11.*13.*17.*19" 256
    _kb_report_speed

    require_gpu_process "KoboldCPP" "$PROC_PAT"

    local kv_f16
    kv_f16=$(_kb_kv_mib)
    info "  KV cache at f16: ${kv_f16} MiB"

    info "--- Quantised KV cache (--quantkv q8_0) ---"
    _kb_start "--quantkv q8_0"
    pass "Server ready with a quantised KV cache"

    local kv_q8
    kv_q8=$(_kb_kv_mib)
    info "  KV cache at q8_0: ${kv_q8} MiB"

    python3 -c "import sys; sys.exit(0 if $kv_q8 < $kv_f16 * 0.75 else 1)" \
        || abort "KoboldCPP: --quantkv q8_0 did not shrink the KV cache (${kv_f16} -> ${kv_q8} MiB)"
    pass "Quantised KV cache active (${kv_f16} -> ${kv_q8} MiB)"

    _kb_ask "KoboldCPP q8_0 KV" "Name the capital of France. Answer with the city name only." "paris"
    _kb_ask "KoboldCPP q8_0 KV" "List the first eight prime numbers, separated by commas." \
            "2.*3.*5.*7.*11.*13.*17.*19" 256
    _kb_report_speed "q8_0 KV"

    stop_app "$PROC_PAT" "$APP_PORT"
    pass "KoboldCPP stopped"

    ctr "rm -f '${APP_LOG}'"
    info "Test koboldcpp DONE"
}

main() { test_koboldcpp; }
main "$@"
