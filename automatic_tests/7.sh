#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 7: RUN AND VERIFY – Atomic llama.cpp (ROCm + MTP)
# ============================================================
phase7_verify_atomic_llama_cpp() {
    info "============================================="
    info "PHASE 7: RUN AND VERIFY (Atomic llama.cpp)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local app_dir="/AI/atomic-llama-cpp-turboquant"
    local model_file="$app_dir/model.gguf"
    local mtp_file="$app_dir/model_mtp.gguf"
    local server_port=8080
    local server_log="/tmp/atomic_llama_turboquant_server.log"

    local target_repo="https://huggingface.co/bartowski/google_gemma-4-26B-A4B-it-GGUF"
    local target_file="google_gemma-4-26B-A4B-it-Q4_K_M.gguf"
    local mtp_repo="https://huggingface.co/AtomicChat/gemma-4-26B-A4B-it-assistant-GGUF"
    local mtp_hf_file="gemma-4-26B-A4B-it-assistant.Q4_K_M.gguf"

    # --- Download target model ---
    info "Downloading target model $target_file from HuggingFace..."
    podman exec -t rocm bash -c "rm -f '${model_file}'" 2>/dev/null || true
    podman exec -t rocm bash -c "
        mkdir -p '${app_dir}' && \
        wget -q '${target_repo}/resolve/main/${target_file}' -O '${model_file}' \
        || curl --fail -L '${target_repo}/resolve/main/${target_file}' -o '${model_file}'
    " || abort "Failed to download $target_file"

    local fsize
    fsize=$(podman exec -t rocm bash -c "stat -c%s '${model_file}' 2>/dev/null || echo 0" \
            | tr -d '\r\n') || fsize=0
    fsize="${fsize:-0}"
    if [[ "$fsize" =~ ^[0-9]+$ ]] && [ "$fsize" -gt 1048576 ]; then
        pass "model.gguf downloaded ($(( fsize / 1024 / 1024 )) MB)"
    else
        abort "model.gguf missing or empty after download (size=${fsize})"
    fi

    # --- Download MTP head model ---
    info "Downloading MTP head $mtp_hf_file from HuggingFace..."
    podman exec -t rocm bash -c "rm -f '${mtp_file}'" 2>/dev/null || true
    podman exec -t rocm bash -c "
        wget -q '${mtp_repo}/resolve/main/${mtp_hf_file}' -O '${mtp_file}' \
        || curl --fail -L '${mtp_repo}/resolve/main/${mtp_hf_file}' -o '${mtp_file}'
    " || abort "Failed to download $mtp_hf_file"

    local mtp_fsize
    mtp_fsize=$(podman exec -t rocm bash -c "stat -c%s '${mtp_file}' 2>/dev/null || echo 0" \
                | tr -d '\r\n') || mtp_fsize=0
    mtp_fsize="${mtp_fsize:-0}"
    if [[ "$mtp_fsize" =~ ^[0-9]+$ ]] && [ "$mtp_fsize" -gt 1048576 ]; then
        pass "model_mtp.gguf downloaded ($(( mtp_fsize / 1024 / 1024 )) MB)"
    else
        abort "model_mtp.gguf missing or empty after download (size=${mtp_fsize})"
    fi

    podman exec -t rocm bash -c \
        "pkill -f 'llama-server' 2>/dev/null; sleep 1; : > '${server_log}'" || true

    # --- Start server with MTP ---
    info "Starting Atomic llama.cpp server (MTP, block-size=5) on port ${server_port}..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && ./build/bin/llama-server \
            -m model.gguf \
            --mtp-head model_mtp.gguf \
            --spec-type mtp \
            --draft-block-size 5 \
            --host 0.0.0.0 \
            --port ${server_port} \
            -c 16384 \
            --cache-type-k turbo3 \
            --cache-type-v turbo3 \
            -ngl 99 -ngld 99 \
            -fa on \
        >> '${server_log}' 2>&1"

    info "Waiting for Atomic llama.cpp server to become ready..."
    local max_wait=600 wait_rc=0
    wait_for_http \
        "curl -sf http://localhost:${server_port}/health | grep -q 'ok'" \
        "llama-server" \
        "${server_log}" \
        "$max_wait" \
        "llama server listening" || wait_rc=$?

    if [ $wait_rc -eq 0 ]; then
        pass "Atomic llama.cpp server ready (/health OK)"
    else
        podman exec -t rocm bash -c "cat '${server_log}'" 2>/dev/null || true
        if [ $wait_rc -eq 1 ]; then
            abort "Atomic llama.cpp server process died unexpectedly"
        else
            abort "Atomic llama.cpp server did not become ready within ${max_wait}s"
        fi
    fi

    # --- Verify MTP is active ---
    info "Sending test query to Atomic llama.cpp API (checking MTP)..."
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
            pass "Atomic llama.cpp API responded correctly (answer contains 4)"
        else
            abort "Atomic llama.cpp API returned wrong answer: \"$answer\" (expected 4)"
        fi
    else
        info "Raw API response: $api_response"
        podman exec -t rocm bash -c "cat '${server_log}'" 2>/dev/null || true
        abort "Atomic llama.cpp API did not return expected response"
    fi

    info "Stopping Atomic llama.cpp server..."
    podman exec -t rocm bash -c "pkill -f 'llama-server' 2>/dev/null || true" || true
    local kw=0
    while podman exec -t rocm bash -c "pgrep -f 'llama-server' > /dev/null" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "Atomic llama.cpp server stopped"

    info "Phase 7 DONE"
}

main() { phase7_verify_atomic_llama_cpp; }
main "$@"
