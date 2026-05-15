#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 4: RUN AND VERIFY – llama.cpp
# ============================================================
phase4_verify_llama() {
    info "============================================="
    info "PHASE 4: RUN AND VERIFY (llama.cpp)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local model_dir="/AI/llama.cpp"
    local model_file="$model_dir/model.gguf"
    local hf_repo="https://huggingface.co/bartowski/google_gemma-4-26B-A4B-it-GGUF"
    local hf_file="google_gemma-4-26B-A4B-it-Q4_K_M.gguf"

    info "Downloading $hf_file from HuggingFace..."
    podman exec -t rocm bash -c "rm -f '${model_file}'" 2>/dev/null || true

    podman exec -t rocm bash -c "
        mkdir -p '${model_dir}' && \
        wget -q '${hf_repo}/resolve/main/${hf_file}' -O '${model_file}' \
        || curl --fail -L '${hf_repo}/resolve/main/${hf_file}' -o '${model_file}'
    " || abort "Failed to download $hf_file"

    local fsize
    fsize=$(podman exec -t rocm bash -c "stat -c%s '${model_file}' 2>/dev/null || echo 0" \
            | tr -d '\r\n') || fsize=0
    fsize="${fsize:-0}"
    if [[ "$fsize" =~ ^[0-9]+$ ]] && [ "$fsize" -gt 1048576 ]; then
        pass "model.gguf downloaded ($(( fsize / 1024 / 1024 )) MB)"
    else
        abort "model.gguf missing or empty after download (size=${fsize})"
    fi

    local server_port=8080
    local server_log="/tmp/llama_server.log"
    podman exec -t rocm bash -c "pkill -f 'llama-server' 2>/dev/null; sleep 1; : > '${server_log}'" || true

    info "Starting llama.cpp server on port ${server_port}..."
    podman exec -d rocm bash -c \
        "cd '${model_dir}' && ./build/bin/llama-server \
            -m model.gguf \
            --host 0.0.0.0 \
            --port ${server_port} \
            -c 8192 \
            -ngl 99 \
        >> '${server_log}' 2>&1"

    info "Waiting for llama.cpp server to become ready..."
    local max_wait=300 wait_rc=0
    wait_for_http \
        "curl -sf http://localhost:${server_port}/health | grep -q 'ok'" \
        "llama-server" \
        "${server_log}" \
        "$max_wait" \
        "llama server listening" || wait_rc=$?

    if [ $wait_rc -eq 0 ]; then
        pass "llama.cpp server ready (/health OK)"
    else
        podman exec -t rocm bash -c "cat '${server_log}'" 2>/dev/null || true
        if [ $wait_rc -eq 1 ]; then
            abort "llama.cpp server process died unexpectedly"
        else
            abort "llama.cpp server did not become ready within ${max_wait}s"
        fi
    fi

    info "Sending test query to llama.cpp API..."
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
        pass "llama.cpp API responded"
    else
        info "Raw API response: $api_response"
        podman exec -t rocm bash -c "cat '${server_log}'" 2>/dev/null || true
        abort "llama.cpp API did not return expected response (missing 'content')"
    fi

    info "Stopping llama.cpp server..."
    podman exec -t rocm bash -c "pkill -f 'llama-server' 2>/dev/null || true" || true
    local kw=0
    while podman exec -t rocm bash -c "pgrep -f 'llama-server' > /dev/null" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "llama.cpp server stopped"

    info "Phase 4 DONE"
}

main() { phase4_verify_llama; }
main "$@"
