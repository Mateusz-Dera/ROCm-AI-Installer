#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

APP_DIR="/AI/PartCrafter"
APP_PORT=7860
APP_LOG="/tmp/partcrafter_server.log"
PROC_PAT="partcrafter_webui"
SOURCE_IMAGE="${APP_DIR}/assets/images/np3_2f6ab901c5a84ed6bbdf85a67b22a2ee.png"
OUT_GLB="/tmp/partcrafter_test.glb"
NUM_PARTS=3
IOU_MIN=0.65
HU_MAX=0.30

_cleanup() {
    stop_app "$PROC_PAT" "$APP_PORT" > /dev/null 2>&1 || true
    reset_container || true
}
trap _cleanup EXIT INT TERM

_field() { printf '%s' "$1" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$2'))"; }

_gate() {
    local label="$1" value="$2" expr="$3"
    python3 -c "import sys; v=float('${value}'); sys.exit(0 if ${expr} else 1)" 2>/dev/null \
        || abort "PartCrafter: ${label} = ${value}, expected ${expr}"
}

_result_paths() {
    printf '%s' "$1" | python3 -c '
import sys, json
data = json.load(sys.stdin)
index = int(sys.argv[1])
item = data[index] if index < len(data) else None
items = item if isinstance(item, list) else [item]
for entry in items:
    if isinstance(entry, dict) and entry.get("path"):
        print(entry["path"])
' "$2"
}

test_partcrafter() {
    info "============================================="
    info "TEST: PartCrafter (image to multi-part 3D)"
    info "============================================="

    require_container
    clean_hf_incomplete

    stop_app "$PROC_PAT" "$APP_PORT"
    run_install "PartCrafter" install_partcrafter "$APP_DIR"
    require_gpu_pin "PartCrafter" PartCrafter
    require_tests_venv "$APP_DIR" trimesh pillow numpy httpx

    container_file_exists "$SOURCE_IMAGE" \
        || abort "PartCrafter: the source image ${SOURCE_IMAGE} is missing"

    start_app PartCrafter "$APP_LOG"

    info "Waiting for the server..."
    wait_for_http_or_abort "PartCrafter" \
        "curl -sf --max-time 3 http://localhost:${APP_PORT}/gradio_api/info > /dev/null" \
        "$PROC_PAT" "$APP_LOG" 1800 "$APP_DIR"
    pass "Server ready on port ${APP_PORT}"

    if ! listens_on_all_interfaces "$APP_PORT"; then
        fail "  Listening addresses: $(port_listen_addrs "$APP_PORT" | tr '\n' ' ')"
        abort "PartCrafter: not listening on 0.0.0.0:${APP_PORT}"
    fi
    pass "Listening on 0.0.0.0:${APP_PORT}"

    local endpoint
    endpoint=$(ctr "curl -sf http://localhost:${APP_PORT}/gradio_api/info" \
               | python3 -c '
import sys, json
for name in json.load(sys.stdin).get("named_endpoints", {}):
    if "generate" in name:
        print(name.lstrip("/")); break')
    [ -n "$endpoint" ] || abort "PartCrafter: no generate endpoint in /gradio_api/info"
    pass "Generate endpoint exposed: /${endpoint}"

    podman cp "${TESTS_DIR}/helpers/gradio6_call.py" "rocm:/tmp/gradio6_call.py" \
        || abort "PartCrafter: could not copy the API helper into the container"
    podman cp "${TESTS_DIR}/helpers/mesh_compare.py" "rocm:/tmp/mesh_compare.py" \
        || abort "PartCrafter: could not copy the comparer into the container"

    info "--- Generating ${NUM_PARTS} parts (seed 42, 1024 tokens, 50 steps) ---"
    ctr "rm -f '${OUT_GLB}'"

    local payload
    payload="[{\"__file__\": \"${SOURCE_IMAGE}\"}, ${NUM_PARTS}, 42, 1024, 50, 7.0, false, false, true]"

    local result
    result=$(ctr "cd ${APP_DIR}/tests && source .venv/bin/activate && \
              python /tmp/gradio6_call.py ${APP_PORT} ${endpoint} 3600 '${payload}'") \
        || { dump_lines "tail -30 '${APP_LOG}'"; abort "PartCrafter: the generate call failed"; }

    local merged
    merged=$(_result_paths "$result" 0 | head -1)
    [ -n "$merged" ] || { fail "  Response: $(printf '%s' "$result" | head -c 300)"
                          abort "PartCrafter: no merged GLB in the response"; }
    ctr "cp '${merged}' '${OUT_GLB}'"

    ctr "head -c4 '${OUT_GLB}' | grep -q glTF" \
        || abort "PartCrafter: the merged output is not a GLB"
    pass "Merged GLB written ($(ctr "stat -c%s '${OUT_GLB}'") bytes, glTF header verified)"

    local parts count
    parts=$(_result_paths "$result" 3)
    count=$(printf '%s' "$parts" | grep -c '\.glb$' || true)
    [ "$count" -eq "$NUM_PARTS" ] \
        || abort "PartCrafter: asked for ${NUM_PARTS} parts, got ${count} part files"
    pass "Split into ${count} separate part GLBs"

    local part
    while read -r part; do
        [ -n "$part" ] || continue
        ctr "head -c4 '${part}' | grep -q glTF" \
            || abort "PartCrafter: part ${part} is not a GLB"
        ctr "test \$(stat -c%s '${part}') -gt 1024" \
            || abort "PartCrafter: part ${part} is smaller than 1 KiB"
    done <<< "$parts"
    pass "Every part is a non-trivial GLB"

    local gif
    gif=$(_result_paths "$result" 2 | head -1)
    [ -n "$gif" ] || abort "PartCrafter: no rendered GIF in the response"
    ctr "head -c3 '${gif}' | grep -q GIF" \
        || abort "PartCrafter: the rendered animation is not a GIF"
    pass "Rendered animation produced ($(ctr "stat -c%s '${gif}'") bytes)"

    require_gpu_process "PartCrafter" "$PROC_PAT"

    local m
    m=$(ctr "cd ${APP_DIR}/tests && source .venv/bin/activate && \
         python /tmp/mesh_compare.py '${OUT_GLB}' '${SOURCE_IMAGE}' 2>/dev/null | tail -1")
    [ -n "$m" ] || abort "PartCrafter: the mesh comparer returned nothing"
    info "  ${m}"

    _gate "vertex count" "$(_field "$m" vertices)" "v > 100"
    _gate "face count" "$(_field "$m" faces)" "v > 100"
    pass "Mesh has geometry ($(_field "$m" vertices) vertices, $(_field "$m" faces) faces)"

    _gate "silhouette IoU" "$(_field "$m" silhouette_iou)" "v > ${IOU_MIN}"
    pass "Silhouette matches the source image (IoU $(_field "$m" silhouette_iou))"

    _gate "Hu distance" "$(_field "$m" hu_distance)" "v < ${HU_MAX}"
    pass "Shape descriptor matches the source image (Hu distance $(_field "$m" hu_distance))"

    stop_app "$PROC_PAT" "$APP_PORT"
    pass "PartCrafter stopped"

    ctr "rm -f '${OUT_GLB}' /tmp/gradio6_call.py /tmp/mesh_compare.py '${APP_LOG}'"
    info "Test partcrafter DONE"
}

main() { test_partcrafter; }
main "$@"
