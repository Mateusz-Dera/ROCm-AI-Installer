#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

test_llama_cpp() {
    info "============================================="
    info "TEST: llama.cpp ROCm + Vulkan (install + TurboQuant verify)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."
    clean_hf_incomplete

    run_install "llama.cpp-turboquant" install_llama_cpp_turboquant "/AI/llama.cpp-turboquant"
    run_install "llama.cpp-turboquant-vulkan" install_llama_cpp_turboquant_vulkan "/AI/llama.cpp-turboquant-vulkan"

    local rocm_dir="/AI/llama.cpp-turboquant"
    local vulkan_dir="/AI/llama.cpp-turboquant-vulkan"
    local server_port=8080

    local hf_repo="https://huggingface.co/unsloth/gemma-4-12b-it-GGUF"
    local hf_model="gemma-4-12b-it-Q8_0.gguf"

    info "Downloading $hf_model from HuggingFace..."
    podman exec -t rocm bash -c "
        rm -f '${rocm_dir}/model.gguf' '${vulkan_dir}/model.gguf'
    " 2>/dev/null || true
    podman exec -t rocm bash -c "
        wget -q '${hf_repo}/resolve/main/${hf_model}' -O '${rocm_dir}/model.gguf' \
        || curl --fail -L '${hf_repo}/resolve/main/${hf_model}' -o '${rocm_dir}/model.gguf'
    " || abort "Failed to download $hf_model"

    local fsize
    fsize=$(podman exec -t rocm bash -c "stat -c%s '${rocm_dir}/model.gguf' 2>/dev/null || echo 0" \
            | tr -d '\r\n') || fsize=0
    fsize="${fsize:-0}"
    if [[ "$fsize" =~ ^[0-9]+$ ]] && [ "$fsize" -gt 1048576 ]; then
        pass "model.gguf downloaded ($(( fsize / 1024 / 1024 )) MB)"
    else
        abort "model.gguf missing or empty after download (size=${fsize})"
    fi

    info "Copying models to Vulkan directory..."
    podman exec -t rocm bash -c "
        cp '${rocm_dir}/model.gguf' '${vulkan_dir}/model.gguf'
    " || abort "Failed to copy models"
    pass "Models copied to Vulkan directory"

    _test_variant() {
        local variant_name="$1"
        local app_dir="$2"
        local server_log="$3"
        local server_env="$4"
        local fa="$5"

        podman exec -t rocm bash -c \
            "pkill -f '[l]lama-server' 2>/dev/null; sleep 1; : > '${server_log}'" || true

        info "Starting ${variant_name} server on port ${server_port}..."
        podman exec -d rocm bash -c \
            "cd '${app_dir}' && export ${server_env} && ./build/bin/llama-server \
                -m model.gguf \
                --host 0.0.0.0 \
                --port ${server_port} \
                -c 262144 \
                -ngl auto \
                -fa ${fa} \
                --cache-type-k turbo3 \
                --cache-type-v turbo3 \
            >> '${server_log}' 2>&1"

        info "Waiting for ${variant_name} server to become ready..."
        local max_wait=600 wait_rc=0
        wait_for_http \
            "curl -sf http://localhost:${server_port}/health | grep -q 'ok'" \
            "llama-server" \
            "${server_log}" \
            "$max_wait" \
            "llama server listening" || wait_rc=$?

        if [ $wait_rc -eq 0 ]; then
            pass "${variant_name} server ready (/health OK)"
        else
            podman exec -t rocm bash -c "cat '${server_log}'" 2>/dev/null || true
            if [ $wait_rc -eq 1 ]; then
                abort "${variant_name} server process died unexpectedly"
            else
                abort "${variant_name} server did not become ready within ${max_wait}s"
            fi
        fi

        info "Checking ${variant_name} log for the turbo3 KV cache..."
        if podman exec -t rocm bash -c "grep -qi 'turbo3' '${server_log}'" 2>/dev/null; then
            pass "${variant_name}: turbo3 KV cache confirmed in server log"
        else
            podman exec -t rocm bash -c "cat '${server_log}'" 2>/dev/null || true
            abort "${variant_name}: turbo3 NOT found in server log"
        fi

        info "Sending test query to ${variant_name} API..."
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
                pass "${variant_name} API responded correctly (answer contains 4)"
            else
                abort "${variant_name} API returned wrong answer: \"$answer\" (expected 4)"
            fi

        else
            info "Raw API response: $api_response"
            podman exec -t rocm bash -c "cat '${server_log}'" 2>/dev/null || true
            abort "${variant_name} API did not return expected response"
        fi

        info "Stopping ${variant_name} server..."
        podman exec -t rocm bash -c "pkill -f '[l]lama-server' 2>/dev/null || true" || true
        local kw=0
        while podman exec -t rocm bash -c "pgrep -f '[l]lama-server' > /dev/null" 2>/dev/null; do
            sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
        done
        pass "${variant_name} server stopped"
    }

    info "--- Testing llama.cpp TurboQuant ROCm ---"
    _test_variant "llama.cpp (ROCm)" "$rocm_dir" "/tmp/llama_rocm_server.log" \
        "GGML_CUDA_DISABLE_GRAPHS=1 HIP_VISIBLE_DEVICES=0" "on"

    info "--- Testing llama.cpp TurboQuant Vulkan ---"
    _test_variant "llama.cpp (Vulkan)" "$vulkan_dir" "/tmp/llama_vulkan_server.log" \
        "VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json GGML_VK_VISIBLE_DEVICES=0" "auto"

    info "Test llama_cpp DONE"
}

main() { test_llama_cpp; }
main "$@"
