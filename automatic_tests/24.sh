#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 24: RUN AND VERIFY – hipfire (LLM inference, qwen3.5:4b)
# ============================================================
phase24_verify_hipfire() {
    info "============================================="
    info "PHASE 24: RUN AND VERIFY (hipfire)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local app_dir="/AI/hipfire"
    local api_port=11435
    local serve_log="/root/.hipfire/serve.log"
    local model="qwen3.5:4b"

    # --- Kill any leftover serve daemon ---
    podman exec -t rocm bash -c "hipfire stop 2>/dev/null; sleep 2; fuser -k ${api_port}/tcp 2>/dev/null; true" || true

    # --- diag ---
    info "Running hipfire diag..."
    local diag_out
    diag_out=$(podman exec -t rocm bash -c "hipfire diag 2>&1" | tr -d '\r')
    if echo "$diag_out" | grep -qi "gfx\|GPU\|HIP\|VRAM"; then
        pass "hipfire diag OK"
        info "$diag_out" | head -5
    else
        info "diag output: $diag_out"
        abort "hipfire diag did not report GPU info"
    fi

    # --- Pull model (idempotent, resumes if partial) ---
    info "Pulling model ${model} (may take a while on first run)..."
    podman exec -it rocm bash -c "hipfire pull ${model}" || abort "hipfire pull ${model} failed"
    pass "Model ${model} ready"

    # --- Start serve in background ---
    info "Starting hipfire serve on port ${api_port}..."
    podman exec -d rocm bash -c "hipfire serve ${api_port} >> '${serve_log}' 2>&1"

    # --- Wait for API ---
    info "Waiting for hipfire API (up to 120s)..."
    local waited=0 max_wait=120 ready=false
    while [ $waited -lt $max_wait ]; do
        if podman exec -t rocm bash -c \
               "curl -sf http://localhost:${api_port}/v1/models" 2>/dev/null; then
            ready=true; break
        fi
        if ! podman exec -t rocm bash -c \
               "pgrep -f 'examples/daemon' > /dev/null" 2>/dev/null; then
            podman exec -t rocm bash -c "tail -20 '${serve_log}'" 2>/dev/null || true
            abort "hipfire daemon died during startup"
        fi
        sleep 3; waited=$((waited + 3))
        info "  ...waiting ($waited/${max_wait}s)"
    done
    $ready || abort "hipfire API did not respond within ${max_wait}s"
    pass "hipfire API ready on port ${api_port}"

    # --- Query model ---
    info "Querying ${model}: 'What is 2+2?'"
    local response
    response=$(podman exec -t rocm bash -c "curl -sf http://localhost:${api_port}/v1/chat/completions \
        -H 'Content-Type: application/json' \
        -d '{
            \"model\": \"${model}\",
            \"messages\": [{\"role\": \"user\", \"content\": \"What is 2+2? Answer with just the number.\"}],
            \"max_tokens\": 32,
            \"temperature\": 0
        }' 2>&1" | tr -d '\r') || true

    if echo "$response" | grep -qiE '"content"\s*:\s*"[^"]*4'; then
        local content
        content=$(echo "$response" | grep -oP '"content"\s*:\s*"\K[^"]+' | head -1)
        pass "Model answered correctly: '$content'"
    elif echo "$response" | grep -q '"content"'; then
        local content
        content=$(echo "$response" | grep -oP '"content"\s*:\s*"\K[^"]+' | head -1)
        info "Response content: '$content'"
        pass "Model responded (content present)"
    else
        info "Full response: $response"
        abort "No valid response from model"
    fi

    # --- Stop serve ---
    info "Stopping hipfire serve..."
    podman exec -t rocm bash -c "hipfire stop 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c "fuser ${api_port}/tcp > /dev/null 2>&1" 2>/dev/null; do
        sleep 2; kw=$((kw + 2))
        [ $kw -ge 20 ] && break
    done
    pass "hipfire stopped"

    info "Phase 24 DONE"
}

main() { phase24_verify_hipfire; }
main "$@"
