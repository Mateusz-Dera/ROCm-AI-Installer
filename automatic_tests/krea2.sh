#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

test_krea2() {
    info "============================================="
    info "TEST: Krea 2 Turbo + Edit (install + generate + identity edit)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."
    clean_hf_incomplete

    # --- Install ---
    run_install "Krea 2 Turbo + Edit" install_krea2 "/AI/Krea-2-Turbo"

    # --- Start server ---
    local app_dir="/AI/Krea-2-Turbo"
    local app_port=7860
    local app_log="/tmp/krea2_server.log"

    podman exec -t rocm bash -c "pkill -f 'app.py' 2>/dev/null; sleep 1; : > '$app_log'" || true

    info "Starting Krea 2 Turbo + Edit (port $app_port)..."
    podman exec -d rocm bash -c \
        "cd '$app_dir' && source .venv/bin/activate && \
         PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512 \
         TORCH_BLAS_PREFER_HIPBLASLT=1 \
         python app.py >> '$app_log' 2>&1"

    info "Waiting for Krea 2 Turbo + Edit to become ready (model download + load)..."
    local waited=0 max_wait=1800 ready=false
    while [ $waited -lt $max_wait ]; do
        if podman exec -t rocm bash -c \
               "curl -sf http://localhost:${app_port}/ > /dev/null" 2>/dev/null; then
            ready=true; break
        fi
        if ! podman exec -t rocm bash -c "pgrep -f 'python app.py' > /dev/null" 2>/dev/null; then
            info "Process died. Last log lines:"
            podman exec -t rocm bash -c "tail -30 '$app_log'" 2>/dev/null || true
            abort "Krea 2 Turbo + Edit process died before becoming ready"
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
        abort "Krea 2 Turbo + Edit did not start within ${max_wait}s"
    fi
    pass "Krea 2 Turbo + Edit is running on port $app_port"

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
        abort "Krea 2 Turbo + Edit Gradio API did not become ready within ${api_max}s"
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
            abort "Krea 2 Turbo + Edit (${desc}): no event_id returned"
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
                pass "Krea 2 Turbo + Edit (${desc}) OK"
            else
                info "Complete event data: $data_line"
                abort "Krea 2 Turbo + Edit (${desc}): complete event has no image data"
            fi
        elif echo "$gen_result" | grep -q 'event: error'; then
            local err_data
            err_data=$(echo "$gen_result" | grep -A1 'event: error' | grep '^data:' | head -1)
            info "Generation error: $err_data"
            podman exec -t rocm bash -c "tail -30 '$app_log'" 2>/dev/null || true
            abort "Krea 2 Turbo + Edit (${desc}): generation returned an error"
        else
            info "Raw SSE result: $gen_result"
            podman exec -t rocm bash -c "tail -30 '$app_log'" 2>/dev/null || true
            abort "Krea 2 Turbo + Edit (${desc}): no complete/error event in SSE stream"
        fi
    }

    # --- Generate without LoRA ---
    _krea2_generate "no LoRA, 1024x1024, 8 steps" \
        '{"prompt": "a red fox sitting in snow, photorealistic", "negative_prompt": "", "lora_name": "None", "lora_strength": 1.0, "steps": 8, "guidance": 0.0, "width": 1024, "height": 1024, "seed": 42, "randomize": false}'

    # --- Generate with LoRA ---
    _krea2_generate "Retro Anime LoRA, 1024x1024, 8 steps" \
        '{"prompt": "a deer grazing in the forest, Purple retro anime style", "negative_prompt": "", "lora_name": "Retro Anime", "lora_strength": 1.0, "steps": 8, "guidance": 0.0, "width": 1024, "height": 1024, "seed": 42, "randomize": false}'

    # --- Helper: identity edit via Gradio v2 API ---
    # Separate from _krea2_generate: the edit endpoint takes image inputs and needs a
    # far longer timeout (the first call downloads and converts the ~1.8 GB LoRA).
    _krea2_edit() {
        local desc="$1"
        local json_data="$2"
        local timeout_s="$3"

        info "Testing: ${desc}..."
        local event_id
        event_id=$(podman exec -t rocm bash -c "
            curl -sf -X POST http://localhost:${app_port}/gradio_api/call/v2/edit \
                -H 'Content-Type: application/json' \
                -d '${json_data}' | tr -d '\r'
        " 2>/dev/null | grep -o '"event_id":"[^"]*"' | grep -o '[^:]*$' | tr -d '"') || true

        if [ -z "$event_id" ]; then
            podman exec -t rocm bash -c "tail -30 '$app_log'" 2>/dev/null || true
            abort "Krea 2 Turbo + Edit (${desc}): no event_id returned"
        fi
        info "  event_id: $event_id – holding SSE connection (up to ${timeout_s}s)..."

        local edit_result
        edit_result=$(podman exec -t rocm bash -c "
            curl -sf --max-time ${timeout_s} -N \
                http://localhost:${app_port}/gradio_api/call/edit/${event_id} \
            | tr -d '\r'
        " 2>/dev/null) || true

        if echo "$edit_result" | grep -q 'event: complete'; then
            local data_line
            data_line=$(echo "$edit_result" | grep -A1 'event: complete' | grep '^data:' | head -1)
            if echo "$data_line" | grep -qE '"path"|\.png|"url"'; then
                pass "Krea 2 Turbo + Edit (${desc}) OK"
            else
                info "Complete event data: $data_line"
                abort "Krea 2 Turbo + Edit (${desc}): complete event has no image data"
            fi
        elif echo "$edit_result" | grep -q 'event: error'; then
            local err_data
            err_data=$(echo "$edit_result" | grep -A1 'event: error' | grep '^data:' | head -1)
            info "Edit error: $err_data"
            podman exec -t rocm bash -c "tail -30 '$app_log'" 2>/dev/null || true
            abort "Krea 2 Turbo + Edit (${desc}): edit returned an error"
        else
            info "Raw SSE result: $edit_result"
            podman exec -t rocm bash -c "tail -30 '$app_log'" 2>/dev/null || true
            abort "Krea 2 Turbo + Edit (${desc}): no complete/error event in SSE stream"
        fi
    }

    # --- Identity Edit: prepare inputs ---
    # 512x512 keeps the token count low: the edit path prepends one source latent block
    # per reference, so cost scales with (1 + n_refs) against the target.
    info "Creating test images for Identity Edit..."
    podman exec -t rocm bash -c "cd '$app_dir' && source .venv/bin/activate && python3 -c \"
from PIL import Image
Image.new('RGB', (512, 512), (120, 90, 70)).save('/tmp/krea2_scene.png')
Image.new('RGB', (512, 512), (200, 170, 150)).save('/tmp/krea2_person.png')
\"" || abort "Krea 2 Turbo + Edit: failed to create Identity Edit test images"

    local scene_path person_path
    scene_path=$(podman exec -t rocm bash -c \
        "curl -sf -X POST http://localhost:${app_port}/gradio_api/upload \
            -F 'files=@/tmp/krea2_scene.png'" \
        | tr -d '\r' | python3 -c "import sys,json; print(json.load(sys.stdin)[0])") || true
    person_path=$(podman exec -t rocm bash -c \
        "curl -sf -X POST http://localhost:${app_port}/gradio_api/upload \
            -F 'files=@/tmp/krea2_person.png'" \
        | tr -d '\r' | python3 -c "import sys,json; print(json.load(sys.stdin)[0])") || true

    if [ -z "$scene_path" ] || [ -z "$person_path" ]; then
        abort "Krea 2 Turbo + Edit: failed to upload Identity Edit test images"
    fi
    info "  Uploaded scene: $scene_path, person: $person_path"

    # --- Identity Edit: single image ---
    # First edit call also downloads + converts the identity LoRA, hence the long timeout.
    info "Note: the first edit downloads and converts the ~1.8 GB identity-edit LoRA."
    _krea2_edit "identity edit, single image, 512x512, 8 steps" \
        "{\"source_image\": {\"path\": \"${scene_path}\"}, \"person_image\": null, \"instruction\": \"make the background a night market with neon lights\", \"grounding_px\": 768, \"steps\": 8, \"guidance\": 0.0, \"seed\": 42, \"randomize\": false}" \
        2400

    # --- Identity Edit: two images (scene + person) ---
    # Training-fixed order: scene is image 1, person is image 2.
    _krea2_edit "identity edit, two images (scene + person), 512x512, 8 steps" \
        "{\"source_image\": {\"path\": \"${scene_path}\"}, \"person_image\": {\"path\": \"${person_path}\"}, \"instruction\": \"create a photo of this person standing in the scene\", \"grounding_px\": 768, \"steps\": 8, \"guidance\": 0.0, \"seed\": 42, \"randomize\": false}" \
        1800

    # --- Cleanup ---
    info "Stopping Krea 2 Turbo + Edit..."
    podman exec -t rocm bash -c "rm -f /tmp/krea2_scene.png /tmp/krea2_person.png" 2>/dev/null || true
    podman exec -t rocm bash -c "pkill -f 'python app.py' 2>/dev/null || true" || true
    local kw=0
    while podman exec -t rocm bash -c "pgrep -f 'python app.py' > /dev/null" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "Krea 2 Turbo + Edit stopped"

    info "Test krea2 DONE"
}

main() { test_krea2; }
main "$@"
