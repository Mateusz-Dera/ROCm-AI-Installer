#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 13: RUN AND VERIFY – PartCrafter (image-to-3D parts)
# ============================================================
phase13_verify_partcrafter() {
    info "============================================="
    info "PHASE 13: RUN AND VERIFY (PartCrafter)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local app_dir="/AI/PartCrafter"
    local app_port=7860
    local app_log="/tmp/partcrafter_server.log"
    local example_img="/AI/PartCrafter/assets/images/np3_2f6ab901c5a84ed6bbdf85a67b22a2ee.png"
    local output_glb="/tmp/partcrafter_object.glb"

    # --- Kill old instances and clear log ---
    podman exec -t rocm bash -c \
        "pkill -f 'partcrafter_webui' 2>/dev/null; pkill -f 'partcrafter' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; sleep 1; : > '${app_log}'" || true

    # --- Start PartCrafter ---
    info "Starting PartCrafter on port ${app_port}..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         uv run partcrafter_webui.py >> '${app_log}' 2>&1"

    # --- Wait for Gradio API (model downloads + loads at startup) ---
    info "Waiting for PartCrafter Gradio API to become ready (up to 600s)..."
    local waited=0 max_wait=600 ready=false
    while [ $waited -lt $max_wait ]; do
        if podman exec -t rocm bash -c \
               "curl -sf http://localhost:${app_port}/gradio_api/info \
                | grep -q '\"named_endpoints\"'" 2>/dev/null; then
            ready=true; break
        fi
        sleep 5; waited=$((waited + 5))
        info "  ...waiting ($waited/${max_wait}s)"
    done
    if ! $ready; then
        podman exec -t rocm bash -c "cat '${app_log}'" 2>/dev/null || true
        abort "PartCrafter did not become ready within ${max_wait}s"
    fi
    pass "PartCrafter Gradio API ready on port ${app_port}"

    # --- Resolve actual endpoint name from /gradio_api/info ---
    local endpoint_name
    endpoint_name=$(podman exec -t rocm bash -c "
        curl -sf http://localhost:${app_port}/gradio_api/info | tr -d '\r'
    " 2>/dev/null \
    | grep -o '\"\/[a-zA-Z_0-9]*generate[a-zA-Z_0-9]*\"' \
    | head -1 | tr -d '"') || endpoint_name=""
    if [ -z "$endpoint_name" ]; then
        endpoint_name="/generate_parts"
        info "Could not detect endpoint from info – using default: ${endpoint_name}"
    else
        info "Detected endpoint: ${endpoint_name}"
    fi

    # --- Upload example image ---
    info "Uploading example image..."
    local upload_response
    upload_response=$(podman exec -t rocm bash -c "
        curl -sf -X POST http://localhost:${app_port}/gradio_api/upload \
            -F 'files=@${example_img}' | tr -d '\r'
    " 2>/dev/null) || upload_response=""

    local uploaded_path
    uploaded_path=$(echo "$upload_response" \
        | grep -o '"[^"]*"' | head -1 \
        | tr -d '"') || uploaded_path=""

    if [ -z "$uploaded_path" ]; then
        info "Upload response: $upload_response"
        abort "PartCrafter: failed to upload example image"
    fi
    info "Image uploaded: ${uploaded_path}"

    # --- Request 3D generation (2 parts, 10 steps, no render → faster test) ---
    info "Requesting 3D generation (2 parts, 10 inference steps)..."
    local event_id
    event_id=$(podman exec -t rocm bash -c "
        curl -sf -X POST http://localhost:${app_port}/gradio_api/call${endpoint_name} \
            -H 'Content-Type: application/json' \
            -d '{\"data\": [
                {\"path\": \"${uploaded_path}\", \"meta\": {\"_type\": \"gradio.FileData\"}},
                2,
                42,
                512,
                10,
                7.0,
                false,
                false,
                false
            ]}' | tr -d '\r'
    " 2>/dev/null \
    | grep -o '\"event_id\":\"[^\"]*\"' \
    | grep -o '[^:]*$' \
    | tr -d '"') || true

    if [ -z "$event_id" ]; then
        podman exec -t rocm bash -c "tail -20 '${app_log}'" 2>/dev/null || true
        abort "PartCrafter: no event_id returned from ${endpoint_name}"
    fi
    info "Generation started (event_id: $event_id) – polling result (up to 30 min)..."

    # --- Poll SSE stream – 3D generation is slow (up to 1800s) ---
    local gen_result
    gen_result=$(podman exec -t rocm bash -c "
        curl -sf --max-time 1800 \
            http://localhost:${app_port}/gradio_api/call${endpoint_name}/${event_id} \
        | tr -d '\r'
    " 2>/dev/null) || true

    if echo "$gen_result" | grep -q '"path"'; then
        pass "PartCrafter 3D generation OK (files returned)"

        # Extract object.glb path (first output = merged model)
        local glb_path
        glb_path=$(echo "$gen_result" \
            | grep -o '"path": *"[^"]*\.glb[^"]*"' | head -1 \
            | sed 's/"path": *"//;s/"//') || glb_path=""

        if [ -n "$glb_path" ]; then
            podman exec -t rocm bash -c "cp '${glb_path}' '${output_glb}'" 2>/dev/null || true
            local fsize
            fsize=$(podman exec -t rocm bash -c \
                "stat -c%s '${output_glb}' 2>/dev/null || echo 0" \
                | tr -d '\r\n') || fsize=0
            info "  object.glb saved: ${output_glb} ($(( ${fsize:-0} / 1024 )) KB)"
            if [ "${fsize:-0}" -lt 1024 ]; then
                abort "object.glb is suspiciously small (${fsize} bytes)"
            fi
        else
            info "  Warning: could not extract GLB path from result"
            info "  Raw result: $gen_result"
        fi
    else
        info "Raw result: $gen_result"
        podman exec -t rocm bash -c "tail -30 '${app_log}'" 2>/dev/null || true
        abort "PartCrafter generation did not return file data"
    fi

    # --- Stop server ---
    info "Stopping PartCrafter..."
    podman exec -t rocm bash -c \
        "pkill -f 'partcrafter_webui' 2>/dev/null; pkill -f 'partcrafter' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c \
            "fuser ${app_port}/tcp > /dev/null 2>&1" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "PartCrafter stopped"

    info "Phase 13 DONE"
}

main() { phase13_verify_partcrafter; }
main "$@"
