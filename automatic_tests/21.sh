#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 21: RUN AND VERIFY – llama.cpp-vulkan
# ============================================================
phase21_verify_llama_vulkan() {
    info "============================================="
    info "PHASE 21: RUN AND VERIFY (llama.cpp-vulkan)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    # --- Download model ---
    local model_dir="/AI/llama.cpp-vulkan"
    local model_file="$model_dir/model.gguf"
    local hf_repo="https://huggingface.co/unsloth/Mistral-Nemo-Instruct-2407-GGUF"
    # Q4_K_M: good quality/size tradeoff (~7.5 GB)
    local hf_file="Mistral-Nemo-Instruct-2407.Q4_K_M.gguf"

    info "Downloading $hf_file from HuggingFace..."
    # Remove old/empty file if it exists
    podman exec -t rocm bash -c "rm -f '${model_file}'" 2>/dev/null || true

    podman exec -t rocm bash -c "
        mkdir -p '${model_dir}' && \
        wget -q '${hf_repo}/resolve/main/${hf_file}' -O '${model_file}' \
        || curl --fail -L '${hf_repo}/resolve/main/${hf_file}' -o '${model_file}'
    " || abort "Failed to download Mistral-Nemo model"

    # Verify: file must exist and have size > 0
    # tr -d '\r' removes carriage return added by podman exec -t via TTY layer
    local fsize
    fsize=$(podman exec -t rocm bash -c "stat -c%s '${model_file}' 2>/dev/null || echo 0" \
            | tr -d '\r\n') || fsize=0
    fsize="${fsize:-0}"
    if [[ "$fsize" =~ ^[0-9]+$ ]] && [ "$fsize" -gt 1048576 ]; then
        pass "model.gguf downloaded successfully ($(( fsize / 1024 / 1024 )) MB)"
    else
        abort "model.gguf is missing or empty after download (size=${fsize} bytes)"
    fi

    # --- Start server in background ---
    local server_port=8080
    # Kill old server instances and clear log before starting
    podman exec -t rocm bash -c "pkill -f 'llama-server' 2>/dev/null; sleep 1; : > /tmp/llama_vulkan_server.log" || true

    info "Starting llama.cpp-vulkan server on port $server_port..."
    # Mistral-Nemo GGUF (unsloth): rope.dimension_count=160 in metadata,
    # but tensors have head_dim=128 → llama.cpp rejects the model without override.
    podman exec -d rocm bash -c \
        "cd '$model_dir' && ./build/bin/llama-server \
            -m model.gguf \
            --host 0.0.0.0 \
            --port $server_port \
            --ctx-size 32768 \
            --gpu-layers 31 \
            --override-kv llama.attention.key_length=int:128,llama.attention.value_length=int:128,llama.rope.dimension_count=int:128 \
        >> /tmp/llama_vulkan_server.log 2>&1"

    # --- Wait for server to become ready (up to 300 s) ---
    info "Waiting for llama.cpp-vulkan server to become ready..."
    local max_wait=300
    local wait_rc=0
    wait_for_http \
        "curl -sf http://localhost:${server_port}/health | grep -q 'ok'" \
        "llama-server" \
        "/tmp/llama_vulkan_server.log" \
        "$max_wait" \
        "llama server listening" || wait_rc=$?

    if [ $wait_rc -eq 0 ]; then
        pass "llama.cpp-vulkan server is running and /health responded OK"
    else
        podman exec -t rocm bash -c "cat /tmp/llama_vulkan_server.log" 2>/dev/null || true
        if [ $wait_rc -eq 1 ]; then
            abort "llama.cpp-vulkan server process died unexpectedly"
        else
            abort "llama.cpp-vulkan server did not become ready within ${max_wait}s"
        fi
    fi

    # --- Send test API query (/v1/chat/completions) ---
    info "Sending test query to llama.cpp-vulkan API..."
    local api_response
    api_response=$(podman exec -t rocm bash -c "
        curl -sf http://localhost:${server_port}/v1/chat/completions \
            -H 'Content-Type: application/json' \
            -d '{
                \"model\": \"local\",
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
        pass "llama.cpp-vulkan API responded"
    else
        # Print server log and raw response for diagnostics
        info "Raw API response: $api_response"
        podman exec -t rocm bash -c "cat /tmp/llama_vulkan_server.log" 2>/dev/null || true
        abort "llama.cpp-vulkan API did not return expected response (missing 'content' field)"
    fi

    # --- Stop server ---
    info "Stopping llama.cpp-vulkan server..."
    podman exec -t rocm bash -c "pkill -f 'llama-server'" 2>/dev/null || true
    # Wait until the process is gone
    local kill_wait=0
    while podman exec -t rocm bash -c "pgrep -f 'llama-server' > /dev/null" 2>/dev/null; do
        sleep 2
        kill_wait=$((kill_wait + 2))
        if [ $kill_wait -ge 20 ]; then break; fi
    done
    pass "llama.cpp-vulkan server stopped"

    info "Phase 21 DONE"
}

main() { phase21_verify_llama_vulkan; }
main "$@"
