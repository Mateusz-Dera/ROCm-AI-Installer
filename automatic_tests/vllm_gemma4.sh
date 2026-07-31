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

    # --- Install ---
    run_install "vllm-gemma4" install_vllm_gemma4 "/AI/vllm-gemma4"

    local app_dir="/AI/vllm-gemma4"
    local server_port=8001
    local model="/AI/models/gemma-4-31B-it-W4A16-sym-g128"
    local server_log="/tmp/vllm_gemma4_server.log"

    # --- The patch has to have landed, or this is stock 0xSero/turboquant ---
    # fused.py is added only by our patch and is what makes decode usable
    # (6.5 -> 12.2 tok/s at 32k), so its absence means the patch silently failed.
    info "Checking that the ROCm/Gemma 4 patch was applied..."
    if podman exec -t rocm bash -c "test -f '${app_dir}/turboquant/fused.py'" 2>/dev/null; then
        pass "turboquant/fused.py present (patch applied)"
    else
        abort "turboquant/fused.py missing - the patch did not apply"
    fi

    # --- Start server ---
    # The engine renames itself to VLLM::EngineCore, so a pkill on "vllm" alone
    # leaves it holding all the VRAM and the next start fails on free memory.
    podman exec -t rocm bash -c \
        "pkill -9 -f 'VLLM::' 2>/dev/null; pkill -9 -f 'tq_serve' 2>/dev/null; sleep 5; : > '${server_log}'" || true

    # vllm serve cannot be used: the plugin's hooks must be installed before the
    # model is built, which is what tq_serve.py does. --no-enable-prefix-caching
    # is mandatory - a cache hit skips the forward pass, so the plugin never
    # captures and the model answers with an empty store.
    info "Starting vLLM with the compressed KV cache on port ${server_port}..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         HIP_VISIBLE_DEVICES=0 TQ_KV_SHARE=1 \
         PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
         python tq_serve.py --model '${model}' \
            --served-model-name gemma-4-31b \
            --max-model-len 262000 \
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

    # --- The pool has to size up, or max_model_len was not honoured ---
    # Measured: 2.2 GB with --max-model-len 262000 gives 300 410 tokens. The same
    # 2.2 GB with max-model-len 104000 gives only 179 952, so a low number here
    # means the pool was sized from the wrong parameter.
    info "Checking the KV pool sized up..."
    local kv_tokens
    kv_tokens=$(podman exec -t rocm bash -c \
        "grep -a 'GPU KV cache size' '${server_log}' | tail -1 | grep -oE '[0-9,]+ tokens' | tr -d ', tokens'" 2>/dev/null \
        | tr -d '\r\n') || kv_tokens=0
    kv_tokens="${kv_tokens:-0}"
    if [[ "$kv_tokens" =~ ^[0-9]+$ ]] && [ "$kv_tokens" -ge 280000 ]; then
        pass "GPU KV pool holds ${kv_tokens} tokens (>= 280000 expected)"
    else
        podman exec -t rocm bash -c "tail -60 '${server_log}'" 2>/dev/null || true
        abort "GPU KV pool too small: ${kv_tokens} tokens (expected >= 280000)"
    fi

    # --- Recall through the compressed store ---
    # "2+2" would pass with an empty store and prove nothing about compression:
    # the ring buffer alone holds the last 128 tokens. Planting a code far enough
    # back that it can only come from the compressed history is what actually
    # exercises the plugin.
    info "Sending a recall query over a long prompt (exercises the store)..."
    podman exec -t rocm bash -c "cat > /tmp/vllm_g4_needle.py << 'PYEOF'
import json, sys, urllib.request

CODE = 'DELTA-8842'
filler = 'The quick brown fox jumps over the lazy dog. '
# ~8k tokens: comfortably past the 128-token exact ring, so a correct answer
# can only have come out of the compressed store.
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
    podman exec -t rocm bash -c "pkill -9 -f 'VLLM::' 2>/dev/null; pkill -9 -f 'tq_serve' 2>/dev/null || true"
    local kw=0
    while podman exec -t rocm bash -c "pgrep -f 'VLLM::|tq_serve' > /dev/null" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 30 ]; then break; fi
    done
    pass "vLLM server stopped"

    info "Test vllm_gemma4 DONE"
}

main() { test_vllm_gemma4; }
main "$@"
