#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

phase8_verify_tabbyapi() {
    info "============================================="
    info "PHASE 8: RUN AND VERIFY (TabbyAPI)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local model_dir="/AI/tabbyAPI/models/example-model"
    local tabby_port=5000
    local tabby_log="/tmp/tabby_server.log"
    local hf_repo="turboderp/Mistral-Nemo-Base-12B-exl2"
    local hf_revision="4.0bpw"

    # --- Download model ---
    info "Downloading ${hf_repo} (revision: ${hf_revision})..."
    podman exec -t rocm bash -c "
        mkdir -p '${model_dir}' && \
        cd /AI/tabbyAPI && \
        .venv/bin/python -c \"
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='${hf_repo}',
    revision='${hf_revision}',
    local_dir='${model_dir}',
    ignore_patterns=['*.bin']
)
print('Download complete')
\"
    " || abort "Failed to download TabbyAPI model"

    # --- Verify model files ---
    local model_count
    model_count=$(podman exec -t rocm bash -c \
        "find '${model_dir}' -name '*.safetensors' 2>/dev/null | wc -l" \
        | tr -d '\r\n') || model_count=0
    model_count="${model_count:-0}"
    if [[ "$model_count" =~ ^[0-9]+$ ]] && [ "$model_count" -gt 0 ]; then
        pass "TabbyAPI model downloaded (${model_count} shard(s) in ${model_dir})"
    else
        abort "TabbyAPI model download failed – no .safetensors files in ${model_dir}"
    fi

    # --- Update config: set max_seq_len=8192 to avoid OOM during test ---
    info "Setting TabbyAPI config (model: example-model, max_seq_len: 8192)..."
    podman exec -t rocm bash -c "cat > /AI/tabbyAPI/config.yml << 'CFGEOF'
network:
  host: 0.0.0.0
  port: 5000
  disable_auth: true

model:
  model_dir: models
  model_name: example-model
  max_seq_len: 8192
CFGEOF
"

    # --- Kill old instances, clear log ---
    podman exec -t rocm bash -c "pkill -f 'python main.py' 2>/dev/null; sleep 1; : > '${tabby_log}'" || true

    # --- Start TabbyAPI ---
    info "Starting TabbyAPI on port ${tabby_port}..."
    podman exec -d rocm bash -c \
        "cd /AI/tabbyAPI && source .venv/bin/activate && \
         python main.py >> '${tabby_log}' 2>&1"

    # --- Wait for HTTP server start ---
    info "Waiting for TabbyAPI HTTP server..."
    local waited=0 max_wait=30 ready=false
    while [ $waited -lt $max_wait ]; do
        if podman exec -t rocm bash -c \
               "curl -sf http://localhost:${tabby_port}/health > /dev/null" 2>/dev/null; then
            ready=true
            break
        fi
        sleep 3
        waited=$((waited + 3))
        info "  ...waiting ($waited/${max_wait}s)"
    done
    if ! $ready; then
        podman exec -t rocm bash -c "cat '${tabby_log}'" 2>/dev/null || true
        abort "TabbyAPI HTTP server did not start within ${max_wait}s"
    fi
    pass "TabbyAPI HTTP server started"

    # --- Wait for model to finish loading (/v1/model returns id when ready) ---
    info "Waiting for model to load (up to 300 s)..."
    local mwaited=0 mmax=300 mready=false
    while [ $mwaited -lt $mmax ]; do
        if podman exec -t rocm bash -c \
               "curl -sf http://localhost:${tabby_port}/v1/model | grep -q '\"id\"'" 2>/dev/null; then
            mready=true
            break
        fi
        sleep 5
        mwaited=$((mwaited + 5))
        info "  ...loading model ($mwaited/${mmax}s)"
    done

    if $mready; then
        pass "TabbyAPI model loaded and ready"
    else
        podman exec -t rocm bash -c "cat '${tabby_log}'" 2>/dev/null || true
        abort "TabbyAPI model did not load within ${mmax}s"
    fi

    # --- Send test query (/v1/completions – works for base models without chat template) ---
    info "Sending test query to TabbyAPI..."
    local api_response
    api_response=$(podman exec -t rocm bash -c "
        curl -sf http://localhost:${tabby_port}/v1/completions \
            -H 'Content-Type: application/json' \
            -d '{
                \"prompt\": \"Reply with one word: OK\",
                \"max_tokens\": 16,
                \"temperature\": 0
            }'
    " 2>/dev/null) || true

    if echo "$api_response" | grep -q '"text"'; then
        local answer
        answer=$(echo "$api_response" \
            | grep -o '"text": *"[^"]*"' \
            | head -1 \
            | sed 's/"text": *"//;s/"//') || answer=""
        info "  Query:  \"Reply with one word: OK\""
        info "  Answer: \"$answer\""
        pass "TabbyAPI responded"
    else
        info "Raw API response: $api_response"
        podman exec -t rocm bash -c "cat '${tabby_log}'" 2>/dev/null || true
        abort "TabbyAPI did not return expected response (missing 'text' field)"
    fi

    # --- Stop server ---
    info "Stopping TabbyAPI..."
    podman exec -t rocm bash -c "pkill -f 'python main.py' 2>/dev/null || true" || true
    local kw=0
    while podman exec -t rocm bash -c "pgrep -f 'python main.py' > /dev/null" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "TabbyAPI server stopped"

    info "Phase 8 DONE"
}

main() { phase8_verify_tabbyapi; }
main "$@"
