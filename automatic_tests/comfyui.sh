#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

APP_DIR="/AI/ComfyUI"
APP_PORT=8188
APP_LOG="/tmp/comfyui_server.log"
PROC_PAT="main\.py"
WORKFLOWS="${SCRIPT_DIR}/workflows"

STALL_SECS=900
IMG_STD_MIN=20
IMG_UNIQUE_MIN=0.3
MODEL_HAMMING_MIN=20
MOTION_MIN=0.8
STATIC_FRAC_MAX=0.4

_cleanup() {
    stop_app "$PROC_PAT" "$APP_PORT" > /dev/null 2>&1 || true
    reset_container || true
}
trap _cleanup EXIT INT TERM

_field() { printf '%s' "$1" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$2'))"; }

_gate() {
    local label="$1" value="$2" expr="$3"
    python3 -c "import sys; v=float('${value}'); sys.exit(0 if ${expr} else 1)" 2>/dev/null \
        || abort "ComfyUI: ${label} = ${value}, expected ${expr}"
}

_workflow_field() {
    python3 - "$1" "$2" <<'PYEOF'
import json, sys
nodes = json.load(open(sys.argv[1])).get("nodes", [])
for n in nodes:
    if n.get("type") == sys.argv[2]:
        print(*n.get("widgets_values", []))
        break
PYEOF
}

_run_workflow() {
    local file="$1" name="$2"
    podman cp "$file" "rocm:/tmp/wf_${name}.json" \
        || abort "ComfyUI: could not copy ${name} into the container"

    ctr "cd ${APP_DIR} && source .venv/bin/activate && \
         COMFY_STALL_SECS=${STALL_SECS} python /tmp/comfyui_run_workflow.py /tmp/wf_${name}.json" \
        > "/tmp/comfyui_${name}.out" 2>"/tmp/comfyui_${name}.err" \
        || { dump_lines "tail -6 '/tmp/comfyui_${name}.err'"; abort "ComfyUI: ${name} failed"; }

    grep -m1 '^OUTPUT_OK:' "/tmp/comfyui_${name}.out" | cut -d: -f2 \
        || abort "ComfyUI: ${name} produced no output file"
}

_analyze() {
    ctr "cd ${APP_DIR}/tests && source .venv/bin/activate && python /tmp/media_analyze.py $* 2>/dev/null | tail -1"
}

_check_image() {
    local label="$1" path="$2" want_w="$3" want_h="$4" m
    m=$(_analyze "'${path}'")
    [ -n "$m" ] || abort "ComfyUI: the analyzer returned nothing for ${label}"
    info "  ${label}: ${m}"

    _gate "width for ${label}" "$(_field "$m" width)" "v == ${want_w}"
    _gate "height for ${label}" "$(_field "$m" height)" "v == ${want_h}"
    _gate "pixel spread for ${label}" "$(_field "$m" std)" "v > ${IMG_STD_MIN}"
    _gate "tonal range for ${label}" "$(_field "$m" unique_ratio)" "v > ${IMG_UNIQUE_MIN}"
    pass "${label}: ${want_w}x${want_h}, neither blank nor flat (std $(_field "$m" std))"
}

_check_video() {
    local label="$1" path="$2" want_w="$3" want_h="$4" want_frames="$5" m
    m=$(_analyze "'${path}' --video")
    [ -n "$m" ] || abort "ComfyUI: the analyzer returned nothing for ${label}"
    info "  ${label}: ${m}"

    _gate "width for ${label}" "$(_field "$m" width)" "v == ${want_w}"
    _gate "height for ${label}" "$(_field "$m" height)" "v == ${want_h}"
    local got_frames
    got_frames=$(_field "$m" frames)
    _gate "frame count for ${label}" "$got_frames" \
        "v >= ${want_frames} and v % ${want_frames} == 0"
    pass "${label}: ${got_frames} frames of ${want_w}x${want_h} (workflow asks for ${want_frames} per batch item)"

    _gate "first frame spread for ${label}" "$(_field "$m" std)" "v > ${IMG_STD_MIN}"
    _gate "mean motion for ${label}" "$(_field "$m" motion_mean)" "v > ${MOTION_MIN}"
    _gate "static frame fraction for ${label}" \
        "$(python3 -c "print($(_field "$m" static_frames) / max(1, ${got_frames} - 1))")" \
        "v < ${STATIC_FRAC_MAX}"
    pass "${label}: the frames move (mean motion $(_field "$m" motion_mean), $(_field "$m" static_frames)/${got_frames} near-static)"
}

test_comfyui() {
    info "============================================="
    info "TEST: ComfyUI (every shipped workflow)"
    info "============================================="

    require_container
    clean_hf_incomplete

    stop_app "$PROC_PAT" "$APP_PORT"
    run_install "ComfyUI" "install_comfyui 1 2 3" "$APP_DIR"
    require_gpu_pin "ComfyUI" ComfyUI
    require_tests_venv "$APP_DIR" pillow numpy av

    for f in diffusion_models/z_image_turbo_bf16.safetensors \
             diffusion_models/z-anime-distill-4step-bf16.safetensors \
             diffusion_models/wan2.2_ti2v_5B_fp16.safetensors \
             text_encoders/qwen_3_4b-bf16.safetensors \
             text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors \
             vae/ae.safetensors vae/wan2.2_vae.safetensors; do
        container_file_exists "${APP_DIR}/models/${f}" \
            || abort "ComfyUI: the model ${f} is missing"
    done
    pass "Every workflow has its models on disk"

    for img in "$WORKFLOWS"/images/*; do
        container_file_exists "${APP_DIR}/input/$(basename "$img")" \
            || abort "ComfyUI: the installer did not copy $(basename "$img") into input/"
    done
    pass "Input images copied by the installer"

    start_app ComfyUI "$APP_LOG"

    info "Waiting for the server..."
    wait_for_http_or_abort "ComfyUI" \
        "curl -sf --max-time 3 http://localhost:${APP_PORT}/system_stats > /dev/null" \
        "$PROC_PAT" "$APP_LOG" 1800 "$APP_DIR"
    pass "Server ready on port ${APP_PORT}"

    if ! listens_on_all_interfaces "$APP_PORT"; then
        fail "  Listening addresses: $(port_listen_addrs "$APP_PORT" | tr '\n' ' ')"
        abort "ComfyUI: not listening on 0.0.0.0:${APP_PORT}"
    fi
    pass "Listening on 0.0.0.0:${APP_PORT}"

    if ctr "grep -q 'DynamicVRAM support detected and enabled' '${APP_LOG}'"; then
        abort "ComfyUI: DynamicVRAM is active - comfy-aimdo completes nothing on ROCm"
    fi
    pass "DynamicVRAM stays off"

    podman cp "${TESTS_DIR}/helpers/comfyui_run_workflow.py" "rocm:/tmp/comfyui_run_workflow.py" \
        || abort "ComfyUI: could not copy the workflow runner into the container"
    podman cp "${TESTS_DIR}/helpers/media_analyze.py" "rocm:/tmp/media_analyze.py" \
        || abort "ComfyUI: could not copy the analyzer into the container"

    local turbo anime latent w h frames out
    info "--- Z-Image-Turbo ---"
    read -r w h _ < <(_workflow_field "$WORKFLOWS/Z-Image-Turbo.json" EmptySD3LatentImage)
    turbo=$(_run_workflow "$WORKFLOWS/Z-Image-Turbo.json" z_image_turbo)
    pass "Z-Image-Turbo produced $(basename "$turbo")"
    _check_image "Z-Image-Turbo" "$turbo" "$w" "$h"
    require_gpu_process "ComfyUI" "$PROC_PAT"

    info "--- Z-Anime ---"
    read -r w h _ < <(_workflow_field "$WORKFLOWS/Z-Anime.json" EmptySD3LatentImage)
    anime=$(_run_workflow "$WORKFLOWS/Z-Anime.json" z_anime)
    pass "Z-Anime produced $(basename "$anime")"
    _check_image "Z-Anime" "$anime" "$w" "$h"

    local cmp
    cmp=$(_analyze "'${anime}' --compare '${turbo}'")
    info "  Z-Anime vs Z-Image-Turbo: ${cmp}"
    _gate "hamming distance between the two image models" "$(_field "$cmp" hamming)" "v >= ${MODEL_HAMMING_MIN}"
    pass "Z-Anime differs from Z-Image-Turbo (hamming $(_field "$cmp" hamming)/256)"

    for wf in text-to-video image-to-video; do
        info "--- Wan-2.2-5B ${wf} ---"
        read -r w h frames _ < <(_workflow_field "$WORKFLOWS/Wan-2.2-5B-${wf}.json" Wan22ImageToVideoLatent)
        out=$(_run_workflow "$WORKFLOWS/Wan-2.2-5B-${wf}.json" "wan_${wf}")
        pass "Wan-2.2-5B ${wf} produced $(basename "$out")"
        _check_video "Wan-2.2-5B ${wf}" "$out" "$w" "$h" "$frames"
    done

    stop_app "$PROC_PAT" "$APP_PORT"
    pass "ComfyUI stopped"

    ctr "rm -f /tmp/wf_*.json /tmp/comfyui_run_workflow.py /tmp/media_analyze.py '${APP_LOG}'"
    rm -f /tmp/comfyui_*.out /tmp/comfyui_*.err
    info "Test comfyui DONE"
}

main() { test_comfyui; }
main "$@"
