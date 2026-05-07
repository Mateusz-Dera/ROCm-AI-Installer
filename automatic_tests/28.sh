#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 28: RUN AND VERIFY – vllm-turboquant (ROCm)
# ============================================================
phase28_verify_vllm_turboquant() {
    info "============================================="
    info "PHASE 28: RUN AND VERIFY (vllm-turboquant)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local app_dir="/AI/vllm-turboquant"
    local model_file="$app_dir/model.gguf"
    local server_port=8000
    local server_log="/tmp/vllm_turboquant_server.log"
    local hf_repo="https://huggingface.co/unsloth/Mistral-Nemo-Instruct-2407-GGUF"
    local hf_file="Mistral-Nemo-Instruct-2407.Q4_K_M.gguf"

    # --- Download model ---
    info "Downloading $hf_file from HuggingFace..."
    podman exec -t rocm bash -c "rm -f '${model_file}'" 2>/dev/null || true
    podman exec -t rocm bash -c "
        mkdir -p '${app_dir}' && \
        wget -q '${hf_repo}/resolve/main/${hf_file}' -O '${model_file}' \
        || curl --fail -L '${hf_repo}/resolve/main/${hf_file}' -o '${model_file}'
    " || abort "Failed to download Mistral-Nemo model"

    local fsize
    fsize=$(podman exec -t rocm bash -c "stat -c%s '${model_file}' 2>/dev/null || echo 0" \
            | tr -d '\r\n') || fsize=0
    fsize="${fsize:-0}"
    if [[ "$fsize" =~ ^[0-9]+$ ]] && [ "$fsize" -gt 1048576 ]; then
        pass "model.gguf downloaded ($(( fsize / 1024 / 1024 )) MB)"
    else
        abort "model.gguf missing or empty after download (size=${fsize})"
    fi

    # --- Kill old instances, clear log ---
    podman exec -t rocm bash -c \
        "pkill -f 'vllm' 2>/dev/null; sleep 1; fuser -k ${server_port}/tcp 2>/dev/null; : > '${server_log}'" || true

    # --- Start vllm-turboquant server ---
    info "Starting vllm-turboquant server on port ${server_port}..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         vllm serve model.gguf \
             --host 0.0.0.0 \
             --port ${server_port} \
             --kv-cache-dtype turboquant35 \
             --enable-turboquant \
         >> '${server_log}' 2>&1"

    # --- Wait for server ready (vLLM prints "Application startup complete") ---
    info "Waiting for vllm-turboquant server to become ready (up to 300s)..."
    local max_wait=300 wait_rc=0
    wait_for_http \
        "curl -sf http://localhost:${server_port}/health | grep -q 'ok'" \
        "vllm" \
        "${server_log}" \
        "$max_wait" \
        "Application startup complete" || wait_rc=$?

    if [ $wait_rc -eq 0 ]; then
        pass "vllm-turboquant server ready (/health OK)"
    else
        podman exec -t rocm bash -c "tail -30 '${server_log}'" 2>/dev/null || true
        if [ $wait_rc -eq 1 ]; then
            abort "vllm-turboquant server process died unexpectedly"
        else
            abort "vllm-turboquant server did not become ready within ${max_wait}s"
        fi
    fi

    # --- Send test query (OpenAI-compatible API) ---
    info "Sending test query to vllm-turboquant API..."
    local api_response
    api_response=$(podman exec -t rocm bash -c "
        curl -sf http://localhost:${server_port}/v1/chat/completions \
            -H 'Content-Type: application/json' \
            -d '{
                \"model\": \"model.gguf\",
                \"messages\": [{\"role\": \"user\", \"content\": \"Reply with one word: OK\"}],
                \"max_tokens\": 16,
                \"temperature\": 0
            }'
    " 2>/dev/null) || true

    if echo "$api_response" | grep -q '"content"'; then
        local answer
        answer=$(echo "$api_response" \
            | grep -o '"content": *"[^"]*"' \
            | head -1 \
            | sed 's/"content": *"//;s/"//') || answer=""
        info "  Query:  \"Reply with one word: OK\""
        info "  Answer: \"$answer\""
        pass "vllm-turboquant API responded"
    else
        info "Raw API response: $api_response"
        podman exec -t rocm bash -c "tail -30 '${server_log}'" 2>/dev/null || true
        abort "vllm-turboquant API did not return expected response (missing 'content')"
    fi

    # --- Stop server ---
    info "Stopping vllm-turboquant server..."
    podman exec -t rocm bash -c \
        "pkill -f 'vllm' 2>/dev/null; sleep 2; fuser -k ${server_port}/tcp 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c "fuser ${server_port}/tcp > /dev/null 2>&1" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "vllm-turboquant server stopped"

    info "Phase 28 DONE"
}

main() { phase28_verify_vllm_turboquant; }
main "$@"
