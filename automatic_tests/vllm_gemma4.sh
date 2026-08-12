#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

test_vllm_gemma4() {
    info "============================================="
    info "TEST: vLLM Gemma 4 (install + verify)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."
    clean_hf_incomplete

    run_install "vllm-gemma4" install_vllm_gemma4 "/AI/vllm-gemma4"

    local app_dir="/AI/vllm-gemma4"
    local server_port=8001
    local model="/AI/models/gemma-4-31B-qat-W4A16-sym-g128"
    local server_log="/tmp/vllm_gemma4_server.log"

    info "Checking that the ROCm/Gemma 4 patch was applied..."
    if podman exec -t rocm bash -c "test -f '${app_dir}/turboquant/fused.py'" 2>/dev/null; then
        pass "turboquant/fused.py present (patch applied)"
    else
        abort "turboquant/fused.py missing - the patch did not apply"
    fi

    podman exec -t rocm bash -c \
        "pkill -9 -f '[V]LLM::' 2>/dev/null; pkill -9 -f '[t]q_serve' 2>/dev/null; sleep 5; : > '${server_log}'" || true

    info "Starting vLLM with the compressed KV cache on port ${server_port}..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         HIP_VISIBLE_DEVICES=0 TQ_KV_SHARE=1 TQ_VALUE_BITS=4 \
         PYTHONPATH='${app_dir}'/.venv/lib/python3.14/site-packages/_rocm_sdk_core/share/amd_smi \
         python tq_serve.py --model '${model}' \
            --served-model-name gemma-4-31b \
            --max-model-len 150000 \
            --max-num-seqs 2 \
            --max-num-batched-tokens 512 \
            --kv-cache-memory-bytes 2200000000 \
            --kv-cache-dtype fp8 \
            --enforce-eager \
            --no-enable-prefix-caching \
            --host 0.0.0.0 \
            --port ${server_port} \
        >> '${server_log}' 2>&1"

    info "Waiting for server to become ready (model load is slow)..."
    local max_wait=1800 wait_rc=0
    wait_for_http \
        "curl -sf http://localhost:${server_port}/health > /dev/null" \
        "tq_serve" \
        "${server_log}" \
        "$max_wait" \
        "Application startup complete" || wait_rc=$?

    if [ $wait_rc -eq 0 ]; then
        pass "vLLM server ready (/health OK)"
    else
        podman exec -t rocm bash -c "tail -60 '${server_log}'" 2>/dev/null || true
        if [ $wait_rc -eq 1 ]; then
            abort "vLLM server process died unexpectedly"
        else
            abort "vLLM server did not become ready within ${max_wait}s"
        fi
    fi

    info "Checking the KV pool sized up..."
    local kv_tokens
    kv_tokens=$(podman exec -t rocm bash -c \
        "grep -a 'GPU KV cache size' '${server_log}' | tail -1 | grep -oE '[0-9,]+ tokens' | tr -d ', tokens'" 2>/dev/null \
        | tr -d '\r\n') || kv_tokens=0
    kv_tokens="${kv_tokens:-0}"
    if [[ "$kv_tokens" =~ ^[0-9]+$ ]] && [ "$kv_tokens" -ge 262144 ]; then
        pass "GPU KV pool holds ${kv_tokens} tokens (>= 262144 expected)"
    else
        podman exec -t rocm bash -c "tail -60 '${server_log}'" 2>/dev/null || true
        abort "GPU KV pool too small: ${kv_tokens} tokens (expected >= 262144)"
    fi

    info "Sending a recall query over a long prompt (exercises the store)..."
    podman exec -t rocm bash -c "cat > /tmp/vllm_g4_needle.py << 'PYEOF'
import json, sys, urllib.request

CODE = 'DELTA-8842'
filler = 'The quick brown fox jumps over the lazy dog. '
prompt = ('ZAPAMIETAJ: kod dostepu to ' + CODE + '.\n\n' + filler * 1400
          + '\n\nPodaj kod dostepu, ktory pojawil sie w tekscie. Sam kod.')
body = json.dumps({
    'model': 'gemma-4-31b',
    'messages': [{'role': 'user', 'content': prompt}],
    'max_tokens': 32, 'temperature': 0,
}).encode()
req = urllib.request.Request('http://localhost:${server_port}/v1/chat/completions',
                             data=body, headers={'Content-Type': 'application/json'})
try:
    with urllib.request.urlopen(req, timeout=1200) as r:
        out = json.load(r)['choices'][0]['message']['content'] or ''
except Exception as e:
    print('ERROR ' + str(e)); sys.exit(2)
print(('OK ' if CODE in out else 'MISS ') + out.strip()[:80])
PYEOF
"
    local recall
    recall=$(podman exec -t rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && python /tmp/vllm_g4_needle.py" 2>/dev/null \
        | tr -d '\r') || recall="ERROR"

    info "  Result: ${recall}"
    if [[ "$recall" == OK* ]]; then
        pass "Code recalled from the compressed KV store"
    else
        podman exec -t rocm bash -c "tail -40 '${server_log}'" 2>/dev/null || true
        abort "Recall failed: ${recall}"
    fi

    info "Stopping server..."
    podman exec -t rocm bash -c "pkill -9 -f '[V]LLM::' 2>/dev/null; pkill -9 -f '[t]q_serve' 2>/dev/null || true"
    local kw=0
    while podman exec -t rocm bash -c "pgrep -f '[V]LLM::|tq_serve' > /dev/null" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 30 ]; then break; fi
    done
    pass "vLLM server stopped"

    info "Test vllm_gemma4 DONE"
}

main() { test_vllm_gemma4; }
main "$@"
