#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

test_krea2() {
    info "============================================="
    info "TEST: Krea 2 Turbo (install + generate image)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."
    clean_hf_incomplete

    # --- Install ---
    run_install "Krea 2 Turbo" install_krea2 "/AI/Krea-2-Turbo"

    # --- Start server ---
    local app_dir="/AI/Krea-2-Turbo"
    local app_port=7860
    local app_log="/tmp/krea2_server.log"

    podman exec -t rocm bash -c "pkill -f 'app.py' 2>/dev/null; sleep 1; : > '$app_log'" || true

    info "Starting Krea 2 Turbo (port $app_port)..."
    podman exec -d rocm bash -c \
        "cd '$app_dir' && source .venv/bin/activate && \
         PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512 \
         TORCH_BLAS_PREFER_HIPBLASLT=1 \
         python app.py >> '$app_log' 2>&1"

    info "Waiting for Krea 2 Turbo to become ready (model download + load)..."
    local waited=0 max_wait=1800 ready=false
    while [ $waited -lt $max_wait ]; do
        if podman exec -t rocm bash -c \
               "curl -sf http://localhost:${app_port}/ > /dev/null" 2>/dev/null; then
            ready=true; break
        fi
        if ! podman exec -t rocm bash -c "pgrep -f 'python app.py' > /dev/null" 2>/dev/null; then
            info "Process died. Last log lines:"
            podman exec -t rocm bash -c "tail -30 '$app_log'" 2>/dev/null || true
            abort "Krea 2 Turbo process died before becoming ready"
        fi
        local cur_log
        cur_log=$(podman exec -t rocm bash -c "tail -1 '$app_log' 2>/dev/null" | tr -d '\r') || cur_log=""
        if [ -n "$cur_log" ]; then
            info "  log: $cur_log"
        fi
        sleep 10; waited=$((waited + 10))
        info "  ...waiting ($waited/${max_wait}s)"
    done
    if ! $ready; then
        podman exec -t rocm bash -c "tail -50 '$app_log'" 2>/dev/null || true
        abort "Krea 2 Turbo did not start within ${max_wait}s"
    fi
    pass "Krea 2 Turbo is running on port $app_port"

    info "Waiting for Gradio API to become ready..."
    local api_info="" api_waited=0 api_max=120
    while [ $api_waited -lt $api_max ]; do
        api_info=$(podman exec -t rocm bash -c \
            "curl -sf http://localhost:${app_port}/gradio_api/info" 2>/dev/null \
            | tr -d '\r') || true
        if echo "$api_info" | grep -q '"named_endpoints"'; then break; fi
        sleep 5; api_waited=$((api_waited + 5))
        info "  ...API not ready yet ($api_waited/${api_max}s)"
    done
    if ! echo "$api_info" | grep -q '"named_endpoints"'; then
        abort "Krea 2 Turbo Gradio API did not become ready within ${api_max}s"
    fi
    pass "Gradio API ready"

    # --- Helper: generate via Gradio v2 API ---
    _krea2_generate() {
        local desc="$1"
        local json_data="$2"

        info "Testing: ${desc}..."
        local event_id
        event_id=$(podman exec -t rocm bash -c "
            curl -sf -X POST http://localhost:${app_port}/gradio_api/call/v2/generate \
                -H 'Content-Type: application/json' \
                -d '${json_data}' | tr -d '\r'
        " 2>/dev/null | grep -o '"event_id":"[^"]*"' | grep -o '[^:]*$' | tr -d '"') || true

        if [ -z "$event_id" ]; then
            podman exec -t rocm bash -c "tail -30 '$app_log'" 2>/dev/null || true
            abort "Krea 2 Turbo (${desc}): no event_id returned"
        fi
        info "  event_id: $event_id – holding SSE connection..."

        local gen_result
        gen_result=$(podman exec -t rocm bash -c "
            curl -sf --max-time 300 -N \
                http://localhost:${app_port}/gradio_api/call/generate/${event_id} \
            | tr -d '\r'
        " 2>/dev/null) || true

        if echo "$gen_result" | grep -q 'event: complete'; then
            local data_line
            data_line=$(echo "$gen_result" | grep -A1 'event: complete' | grep '^data:' | head -1)
            if echo "$data_line" | grep -qE '"path"|\.png|"url"'; then
                pass "Krea 2 Turbo (${desc}) OK"
            else
                info "Complete event data: $data_line"
                abort "Krea 2 Turbo (${desc}): complete event has no image data"
            fi
        elif echo "$gen_result" | grep -q 'event: error'; then
            local err_data
            err_data=$(echo "$gen_result" | grep -A1 'event: error' | grep '^data:' | head -1)
            info "Generation error: $err_data"
            podman exec -t rocm bash -c "tail -30 '$app_log'" 2>/dev/null || true
            abort "Krea 2 Turbo (${desc}): generation returned an error"
        else
            info "Raw SSE result: $gen_result"
            podman exec -t rocm bash -c "tail -30 '$app_log'" 2>/dev/null || true
            abort "Krea 2 Turbo (${desc}): no complete/error event in SSE stream"
        fi
    }

    # --- Generate without LoRA ---
    _krea2_generate "no LoRA, 1024x1024, 8 steps" \
        '{"prompt": "a red fox sitting in snow, photorealistic", "negative_prompt": "", "lora_name": "None", "lora_strength": 1.0, "steps": 8, "guidance": 0.0, "width": 1024, "height": 1024, "seed": 42, "randomize": false}'

    # --- Generate with LoRA ---
    _krea2_generate "Retro Anime LoRA, 1024x1024, 8 steps" \
        '{"prompt": "a deer grazing in the forest, Purple retro anime style", "negative_prompt": "", "lora_name": "Retro Anime", "lora_strength": 1.0, "steps": 8, "guidance": 0.0, "width": 1024, "height": 1024, "seed": 42, "randomize": false}'

    # --- Cleanup ---
    info "Stopping Krea 2 Turbo..."
    podman exec -t rocm bash -c "pkill -f 'python app.py' 2>/dev/null || true" || true
    local kw=0
    while podman exec -t rocm bash -c "pgrep -f 'python app.py' > /dev/null" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "Krea 2 Turbo stopped"

    info "Test krea2 DONE"
}

main() { test_krea2; }
main "$@"
