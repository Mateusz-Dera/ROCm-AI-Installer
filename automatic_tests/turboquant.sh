#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

test_turboquant() {
    info "============================================="
    info "TEST: turboquant-rocm-llamacpp (install + verify)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."
    clean_hf_incomplete

    # --- Install ---
    run_install "turboquant-rocm-llamacpp" install_turboquant_rocm_llamacpp "/AI/turboquant-rocm-llamacpp"

    # --- Download test model ---
    local app_dir="/AI/turboquant-rocm-llamacpp"
    local server_port=8080

    local hf_repo="https://huggingface.co/unsloth/gemma-4-12b-it-GGUF"
    local hf_model="gemma-4-12b-it-Q8_0.gguf"

    info "Downloading $hf_model from HuggingFace..."
    podman exec -t rocm bash -c "rm -f '${app_dir}/model.gguf'" 2>/dev/null || true
    podman exec -t rocm bash -c "
        wget -q '${hf_repo}/resolve/main/${hf_model}' -O '${app_dir}/model.gguf' \
        || curl --fail -L '${hf_repo}/resolve/main/${hf_model}' -o '${app_dir}/model.gguf'
    " || abort "Failed to download $hf_model"

    local fsize
    fsize=$(podman exec -t rocm bash -c "stat -c%s '${app_dir}/model.gguf' 2>/dev/null || echo 0" \
            | tr -d '\r\n') || fsize=0
    fsize="${fsize:-0}"
    if [[ "$fsize" =~ ^[0-9]+$ ]] && [ "$fsize" -gt 1048576 ]; then
        pass "model.gguf downloaded ($(( fsize / 1024 / 1024 )) MB)"
    else
        abort "model.gguf missing or empty after download (size=${fsize})"
    fi

    # --- Start server ---
    local server_log="/tmp/llama_tq_rocm_server.log"
    podman exec -t rocm bash -c \
        "pkill -f 'llama-server' 2>/dev/null; sleep 1; : > '${server_log}'" || true

    info "Starting turboquant-rocm-llamacpp server (q4_0 KV cache) on port ${server_port}..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && ./build/bin/llama-server \
            -m model.gguf \
            --host 0.0.0.0 \
            --port ${server_port} \
            -c 131072 \
            --flash-attn on \
            --cache-type-k q4_0 \
            --cache-type-v q4_0 \
            -ngl 99 \
        >> '${server_log}' 2>&1"

    info "Waiting for server to become ready..."
    local max_wait=600 wait_rc=0
    wait_for_http \
        "curl -sf http://localhost:${server_port}/health | grep -q 'ok'" \
        "llama-server" \
        "${server_log}" \
        "$max_wait" \
        "llama server listening" || wait_rc=$?

    if [ $wait_rc -eq 0 ]; then
        pass "turboquant-rocm-llamacpp server ready (/health OK)"
    else
        podman exec -t rocm bash -c "cat '${server_log}'" 2>/dev/null || true
        if [ $wait_rc -eq 1 ]; then
            abort "turboquant-rocm-llamacpp server process died unexpectedly"
        else
            abort "turboquant-rocm-llamacpp server did not become ready within ${max_wait}s"
        fi
    fi

    # --- Verify q4_0 KV cache ---
    info "Checking log for q4_0 KV cache..."
    if podman exec -t rocm bash -c "grep -qi 'invalid.*cache-type' '${server_log}'" 2>/dev/null; then
        podman exec -t rocm bash -c "cat '${server_log}'" 2>/dev/null || true
        abort "turboquant-rocm-llamacpp: q4_0 KV cache rejected by server"
    fi
    if podman exec -t rocm bash -c "grep -qi 'q4_0' '${server_log}'" 2>/dev/null; then
        pass "turboquant-rocm-llamacpp: q4_0 KV cache confirmed in server log"
    else
        podman exec -t rocm bash -c "cat '${server_log}'" 2>/dev/null || true
        abort "turboquant-rocm-llamacpp: q4_0 NOT found in server log"
    fi

    # --- Test inference ---
    info "Sending test query..."
    local api_response
    api_response=$(podman exec -t rocm bash -c "
        curl -sf http://localhost:${server_port}/v1/chat/completions \
            -H 'Content-Type: application/json' \
            -d '{
                \"model\": \"local\",
                \"messages\": [
                    {\"role\": \"system\", \"content\": \"You are a calculator. Output only the numeric result, nothing else.\"},
                    {\"role\": \"user\", \"content\": \"2+2\"}
                ],
                \"max_tokens\": 64,
                \"temperature\": 0
            }'
    " 2>/dev/null) || true

    if echo "$api_response" | grep -q '"choices"'; then
        local answer
        answer=$(echo "$api_response" \
            | python3 -c "import json,sys; d=json.load(sys.stdin); m=d['choices'][0]['message']; print(m.get('content','') or m.get('reasoning_content',''))" 2>/dev/null) || answer=""
        info "  Query:  \"2+2\""
        info "  Answer: \"$answer\""
        if echo "$answer" | grep -q '4'; then
            pass "turboquant-rocm-llamacpp API responded correctly (answer contains 4)"
        else
            abort "turboquant-rocm-llamacpp API returned wrong answer: \"$answer\" (expected 4)"
        fi
    else
        info "Raw API response: $api_response"
        podman exec -t rocm bash -c "cat '${server_log}'" 2>/dev/null || true
        abort "turboquant-rocm-llamacpp API did not return expected response"
    fi

    info "Stopping server..."
    podman exec -t rocm bash -c "pkill -f 'llama-server' 2>/dev/null || true" || true
    local kw=0
    while podman exec -t rocm bash -c "pgrep -f 'llama-server' > /dev/null" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "turboquant-rocm-llamacpp server stopped"

    info "Test turboquant DONE"
}

main() { test_turboquant; }
main "$@"
