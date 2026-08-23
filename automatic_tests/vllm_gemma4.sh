#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

APP_DIR="/AI/vllm-gemma4"
APP_PORT=8000
APP_LOG="/tmp/vllm_gemma4.log"
PROC_PAT="tq_serve"
GPU_PAT="tq_serve|VLLM::"
MODEL="/AI/models/gemma-4-31B-qat-W4A16-sym-g128"
NEEDLE_TARGET=250000

_stop_vllm() {
    ctr "pkill -9 -f '[V]LLM::' 2>/dev/null; pkill -9 -f '[t]q_serve' 2>/dev/null; true"
    local waited=0
    while [ -n "$(ctr "pgrep -f '[V]LLM::|[t]q_serve' | head -1")" ] && [ $waited -lt 30 ]; do
        sleep 2; waited=$((waited + 2))
    done
    ctr "fuser -k ${APP_PORT}/tcp 2>/dev/null; true"
}

_cleanup() {
    _stop_vllm > /dev/null 2>&1 || true
    reset_container || true
}
trap _cleanup EXIT INT TERM

_vllm_ask() {
    local label="$1" prompt="$2" expected="$3"

    local response
    response=$(ctr "curl -sf --max-time 900 http://localhost:${APP_PORT}/v1/chat/completions \
        -H 'Content-Type: application/json' \
        -d '{\"model\": \"gemma-4-31b\",
             \"messages\": [{\"role\": \"user\", \"content\": \"${prompt}\"}],
             \"max_tokens\": 128, \"temperature\": 0,
             \"chat_template_kwargs\": {\"enable_thinking\": false}}'")

    if ! printf '%s' "$response" | grep -q '\"choices\"'; then
        fail "  Response: $(printf '%s' "$response" | head -c 300)"
        dump_lines "tail -30 '${APP_LOG}'"
        abort "${label}: the API did not return a completion"
    fi

    local answer
    answer=$(printf '%s' "$response" | python3 -c '
import sys, json
m = json.load(sys.stdin)["choices"][0]["message"]
print((m.get("content") or m.get("reasoning_content") or "").strip())')

    info "  Q: ${prompt}"
    info "  A: \"$(printf '%s' "$answer" | head -c 160)\""
    [ -n "$answer" ] || abort "${label}: the model returned an empty answer"
    printf '%s' "$answer" | grep -qiE "$expected" \
        || abort "${label}: the answer does not match /${expected}/ - the model is answering noise"
    pass "${label}: correct answer"
}

_vllm_log_throughput() {
    ctr "grep -oE 'Avg generation throughput: [0-9.]+ tokens/s' '${APP_LOG}' \
         | grep -oE '[0-9.]+' | sort -rn | head -1"
}

test_vllm_gemma4() {
    info "============================================="
    info "TEST: vLLM Gemma 4 (TurboQuant KV cache)"
    info "============================================="

    require_container
    clean_hf_incomplete

    _stop_vllm
    run_install "vLLM Gemma 4" install_vllm_gemma4 "$APP_DIR"
    require_gpu_pin "vLLM Gemma 4" vllm-gemma4

    container_file_exists "${APP_DIR}/turboquant/fused.py" \
        || abort "vLLM Gemma 4: turboquant/fused.py missing - the ROCm patch did not apply"
    pass "TurboQuant ROCm patch applied"

    container_dir_exists "$MODEL" \
        || abort "vLLM Gemma 4: the quantized model ${MODEL} is missing"
    pass "Quantized model present"

    start_app vllm-gemma4 "$APP_LOG"

    info "Waiting for the engine (model load and KV pool sizing)..."
    wait_for_http_or_abort "vLLM Gemma 4" \
        "curl -sf http://localhost:${APP_PORT}/health -o /dev/null" \
        "$PROC_PAT" "$APP_LOG" 3600 "$APP_DIR"
    pass "API ready on port ${APP_PORT}"

    if ! listens_on_all_interfaces "$APP_PORT"; then
        fail "  Listening addresses: $(port_listen_addrs "$APP_PORT" | tr '\n' ' ')"
        abort "vLLM Gemma 4: not listening on 0.0.0.0:${APP_PORT}"
    fi
    pass "Listening on 0.0.0.0:${APP_PORT}"

    local declared
    declared=$(ctr "curl -sf http://localhost:${APP_PORT}/v1/models" \
               | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"][0]["max_model_len"])')
    [ "$declared" = "262144" ] \
        || abort "vLLM Gemma 4: the API reports max_model_len ${declared}, expected 262144"
    pass "Maximum context declared: ${declared} tokens"

    local pool
    pool=$(ctr "grep -oE 'GPU KV cache size: [0-9,]+ tokens' '${APP_LOG}' | tail -1 \
                | grep -oE '[0-9,]+' | tr -d ','")
    [ -n "$pool" ] || abort "vLLM Gemma 4: the log did not report the KV pool size"
    info "  KV pool: ${pool} tokens in 2200000000 bytes"
    [ "$pool" -ge 262144 ] 2>/dev/null \
        || abort "vLLM Gemma 4: the KV pool holds ${pool} tokens, too few for a 262144 token context"
    pass "KV pool holds ${pool} tokens, enough for the full context"

    info "--- Short answers ---"
    _vllm_ask "vLLM Gemma 4" "Name the capital of France. Answer with the city name only." "paris"
    _vllm_ask "vLLM Gemma 4" "What is 17 plus 25? Answer with the number only." "42"
    _vllm_ask "vLLM Gemma 4" "List the first eight prime numbers, separated by commas." \
              "2.*3.*5.*7.*11.*13.*17.*19"

    info "--- Long context: needle, speed and coherence at ${NEEDLE_TARGET} tokens ---"
    podman cp "${TESTS_DIR}/helpers/vllm_longctx.py" "rocm:/tmp/vllm_longctx.py" \
        || abort "vLLM Gemma 4: could not copy the long context helper into the container"

    local probe
    probe=$(ctr "cd ${APP_DIR} && source .venv/bin/activate && \
        python /tmp/vllm_longctx.py --target ${NEEDLE_TARGET} --tokenizer '${MODEL}' 2>/dev/null | tail -1")
    [ -n "$probe" ] || { dump_lines "tail -40 '${APP_LOG}'"; abort "vLLM Gemma 4: the long context probe returned nothing"; }
    info "  ${probe}"

    local sent produced secs found words uniq repeat wordlen alpha
    _field() { printf '%s' "$probe" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$1'))"; }
    sent=$(_field prompt_tokens);   produced=$(_field completion_tokens)
    secs=$(_field total_seconds);   found=$(_field code_found)
    words=$(_field words);          uniq=$(_field unique_ratio)
    repeat=$(_field repeat_ratio);  wordlen=$(_field mean_word_len)
    alpha=$(_field alpha_ratio)

    [ "${sent:-0}" -ge 200000 ] 2>/dev/null \
        || abort "vLLM Gemma 4: only ${sent} tokens were sent, the long context was not exercised"
    pass "Prompt of ${sent} tokens accepted"

    [ "$found" = "True" ] \
        || abort "vLLM Gemma 4: the code was not recalled from a ${sent} token context"
    pass "Recalled the planted code from ${sent} tokens of context"

    local logged; logged=$(_vllm_log_throughput)
    info "  Generation: ${produced} tokens in ${secs} s end to end, engine peak ${logged:-n/a} tok/s"
    python3 -c "import sys; sys.exit(0 if ${produced:-0} >= 32 else 1)" \
        || abort "vLLM Gemma 4: only ${produced} tokens were generated, too few to judge"
    pass "Generated ${produced} tokens at a ${sent} token context (${secs} s end to end)"

    info "  Coherence: ${words} words, unique ${uniq}, repeat ${repeat}, mean word ${wordlen}, alpha ${alpha}"
    python3 - <<PYEOF || abort "vLLM Gemma 4: the answer at ${sent} tokens of context is degenerate, not prose"
import sys
ok = (${words:-0} >= 20 and ${uniq:-0} >= 0.4 and ${repeat:-1} <= 0.25
      and ${wordlen:-0} >= 3.0 and ${alpha:-0} >= 0.9)
sys.exit(0 if ok else 1)
PYEOF
    pass "The answer at ${sent} tokens is coherent prose, not gibberish"

    require_gpu_process "vLLM Gemma 4" "$GPU_PAT"

    _stop_vllm
    pass "Server stopped"

    info "--- Two sessions of 130k: store isolation ---"
    local multi
    multi=$(ctr "cd ${APP_DIR} && source .venv/bin/activate && \
        HIP_VISIBLE_DEVICES=${GPU_PIN_INDEX:-0} TQ_KV_SHARE=1 TQ_VALUE_BITS=4 \
        PYTHONPATH=${APP_DIR}/.venv/lib/python3.14/site-packages/_rocm_sdk_core/share/amd_smi \
        python tq_multi.py --sessions 2 --per-session 130000 --max-len 132000 \
            --key-bits 4 --value-bits 4 --model '${MODEL}' 2>&1 | tail -25")

    printf '%s\n' "$multi" | while IFS= read -r line; do info "  $line"; done

    if printf '%s' "$multi" | grep -q 'ZANIECZYSZCZENIE'; then
        abort "vLLM Gemma 4: a session read another session's history - the stores leak"
    fi
    printf '%s' "$multi" | grep -qE '2 sesji .* OK$' \
        || abort "vLLM Gemma 4: the two-session run did not finish with OK"
    pass "Two 130k sessions stayed isolated, no cross-session leak"

    ctr "rm -f /tmp/vllm_needle.py '${APP_LOG}'"
    info "Test vllm_gemma4 DONE"
}

main() { test_vllm_gemma4; }
main "$@"
