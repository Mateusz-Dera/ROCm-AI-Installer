#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

test_llama_cpp() {
    info "============================================="
    info "TEST: llama.cpp ROCm + Vulkan (install + MTP verify)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."
    clean_hf_incomplete

    # --- Install both variants ---
    run_install "llama.cpp" install_llama_cpp "/AI/llama.cpp"
    run_install "llama.cpp-vulkan" install_llama_cpp_vulkan "/AI/llama.cpp-vulkan"

    # --- Download model once, share between variants ---
    local rocm_dir="/AI/llama.cpp"
    local vulkan_dir="/AI/llama.cpp-vulkan"
    local server_port=8080

    local hf_repo="https://huggingface.co/unsloth/gemma-4-12b-it-GGUF"
    local hf_model="gemma-4-12b-it-Q8_0.gguf"
    local hf_mtp="mtp-gemma-4-12b-it.gguf"

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

    info "Downloading MTP head $hf_mtp from HuggingFace..."
    podman exec -t rocm bash -c "
        rm -f '${rocm_dir}/model_mtp.gguf' '${vulkan_dir}/model_mtp.gguf'
    " 2>/dev/null || true
    podman exec -t rocm bash -c "
        wget -q '${hf_repo}/resolve/main/${hf_mtp}' -O '${rocm_dir}/model_mtp.gguf' \
        || curl --fail -L '${hf_repo}/resolve/main/${hf_mtp}' -o '${rocm_dir}/model_mtp.gguf'
    " || abort "Failed to download $hf_mtp"

    local mtp_fsize
    mtp_fsize=$(podman exec -t rocm bash -c "stat -c%s '${rocm_dir}/model_mtp.gguf' 2>/dev/null || echo 0" \
                | tr -d '\r\n') || mtp_fsize=0
    mtp_fsize="${mtp_fsize:-0}"
    if [[ "$mtp_fsize" =~ ^[0-9]+$ ]] && [ "$mtp_fsize" -gt 1048576 ]; then
        pass "model_mtp.gguf downloaded ($(( mtp_fsize / 1024 / 1024 )) MB)"
    else
        abort "model_mtp.gguf missing or empty after download (size=${mtp_fsize})"
    fi

    info "Copying models to Vulkan directory..."
    podman exec -t rocm bash -c "
        cp '${rocm_dir}/model.gguf' '${vulkan_dir}/model.gguf' && \
        cp '${rocm_dir}/model_mtp.gguf' '${vulkan_dir}/model_mtp.gguf'
    " || abort "Failed to copy models"
    pass "Models copied to Vulkan directory"

    # ---- Helper: test MTP variant ----
    _test_mtp_variant() {
        local variant_name="$1"
        local app_dir="$2"
        local server_log="$3"

        podman exec -t rocm bash -c \
            "pkill -f 'llama-server' 2>/dev/null; sleep 1; : > '${server_log}'" || true

        info "Starting ${variant_name} server (MTP) on port ${server_port}..."
        podman exec -d rocm bash -c \
            "cd '${app_dir}' && ./build/bin/llama-server \
                -m model.gguf \
                --spec-draft-model model_mtp.gguf \
                --spec-type draft-mtp \
                --spec-draft-n-max 4 \
                --host 0.0.0.0 \
                --port ${server_port} \
                -c 131072 \
                -ngl auto \
                -fa on \
                --cache-type-k q8_0 \
                --cache-type-v q8_0 \
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

        # --- Verify MTP ---
        info "Checking ${variant_name} log for MTP (draft-mtp)..."
        if podman exec -t rocm bash -c "grep -q 'draft-mtp' '${server_log}'" 2>/dev/null; then
            pass "${variant_name}: MTP (draft-mtp) confirmed in server log"
        else
            podman exec -t rocm bash -c "cat '${server_log}'" 2>/dev/null || true
            abort "${variant_name}: MTP (draft-mtp) NOT found in server log"
        fi

        # --- Test inference + verify MTP draft tokens ---
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

            local draft_n
            draft_n=$(echo "$api_response" \
                | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('timings',{}).get('draft_n',0))" 2>/dev/null) || draft_n="0"
            draft_n=$(printf '%s' "$draft_n" | tr -d '\r')
            if [[ "$draft_n" =~ ^[0-9]+$ ]] && [ "$draft_n" -gt 0 ]; then
                local draft_accepted
                draft_accepted=$(echo "$api_response" \
                    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('timings',{}).get('draft_n_accepted',0))" 2>/dev/null) || draft_accepted="0"
                draft_accepted=$(printf '%s' "$draft_accepted" | tr -d '\r')
                pass "${variant_name}: MTP active (draft_n=${draft_n}, accepted=${draft_accepted})"
            else
                abort "${variant_name}: MTP draft tokens not found in response (draft_n=${draft_n})"
            fi
        else
            info "Raw API response: $api_response"
            podman exec -t rocm bash -c "cat '${server_log}'" 2>/dev/null || true
            abort "${variant_name} API did not return expected response"
        fi

        info "Stopping ${variant_name} server..."
        podman exec -t rocm bash -c "pkill -f 'llama-server' 2>/dev/null || true" || true
        local kw=0
        while podman exec -t rocm bash -c "pgrep -f 'llama-server' > /dev/null" 2>/dev/null; do
            sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
        done
        pass "${variant_name} server stopped"
    }

    # ---- Test ROCm variant ----
    info "--- Testing llama.cpp ROCm (MTP) ---"
    _test_mtp_variant "llama.cpp (ROCm)" "$rocm_dir" "/tmp/llama_rocm_server.log"

    # ---- Test Vulkan variant ----
    info "--- Testing llama.cpp Vulkan (MTP) ---"
    _test_mtp_variant "llama.cpp (Vulkan)" "$vulkan_dir" "/tmp/llama_vulkan_server.log"

    info "Test llama_cpp DONE"
}

main() { test_llama_cpp; }
main "$@"
