#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 8: RUN AND VERIFY – KoboldCPP
# ============================================================
phase8_verify_koboldcpp() {
    info "============================================="
    info "PHASE 8: RUN AND VERIFY (KoboldCPP)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local model_file="/AI/koboldcpp-rocm/model.gguf"
    local hf_repo="https://huggingface.co/bartowski/Mistral-7B-Instruct-v0.3-GGUF"
    local hf_file="Mistral-7B-Instruct-v0.3-Q4_K_M.gguf"
    local kobold_port=5001
    local kobold_log="/tmp/kobold_server.log"

    info "Downloading $hf_file from HuggingFace..."
    podman exec -t rocm bash -c "rm -f '${model_file}'" 2>/dev/null || true
    podman exec -t rocm bash -c "
        mkdir -p /AI/koboldcpp-rocm && \
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

    podman exec -t rocm bash -c "pkill -f 'koboldcpp' 2>/dev/null; sleep 1; : > '${kobold_log}'" || true

    info "Starting KoboldCPP on port ${kobold_port}..."
    podman exec -d rocm bash -c \
        "cd /AI/koboldcpp-rocm && source .venv/bin/activate && \
         uv run koboldcpp.py \
             --model '${model_file}' \
             --gpulayers 99 \
             --usecublas \
             --contextsize 8192 \
             --port ${kobold_port} \
             --host 0.0.0.0 \
             --skiplauncher \
         >> '${kobold_log}' 2>&1"

    info "Waiting for KoboldCPP to become ready..."
    local waited=0 max_wait=300 ready=false
    while [ $waited -lt $max_wait ]; do
        if podman exec -t rocm bash -c \
               "curl -sf http://localhost:${kobold_port}/api/extra/version | grep -q '\"result\"'" 2>/dev/null; then
            ready=true
            break
        fi
        sleep 5
        waited=$((waited + 5))
        info "  ...waiting ($waited/${max_wait}s)"
    done

    if $ready; then
        pass "KoboldCPP server ready (/api/extra/version OK)"
    else
        podman exec -t rocm bash -c "cat '${kobold_log}'" 2>/dev/null || true
        abort "KoboldCPP did not become ready within ${max_wait}s"
    fi

    info "Sending test query to KoboldCPP API..."
    local api_response
    api_response=$(podman exec -t rocm bash -c "
        curl -sf http://localhost:${kobold_port}/api/v1/generate \
            -H 'Content-Type: application/json' \
            -d '{
                \"prompt\": \"Reply with one word: OK\",
                \"max_length\": 16,
                \"temperature\": 0
            }'
    " 2>/dev/null) || true

    if echo "$api_response" | grep -q '"results"'; then
        local answer
        answer=$(echo "$api_response" \
            | grep -o '"text": *"[^"]*"' \
            | head -1 \
            | sed 's/"text": *"//;s/"//') || answer=""
        info "  Query:  \"Reply with one word: OK\""
        info "  Answer: \"$answer\""
        pass "KoboldCPP API responded"
    else
        info "Raw API response: $api_response"
        podman exec -t rocm bash -c "cat '${kobold_log}'" 2>/dev/null || true
        abort "KoboldCPP API did not return expected response (missing 'results')"
    fi

    info "Stopping KoboldCPP..."
    podman exec -t rocm bash -c "pkill -f 'koboldcpp' 2>/dev/null || true" || true
    local kw=0
    while podman exec -t rocm bash -c "pgrep -f 'koboldcpp' > /dev/null" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "KoboldCPP server stopped"

    info "Phase 8 DONE"
}

main() { phase8_verify_koboldcpp; }
main "$@"
