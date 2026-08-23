#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

APP_DIR="/AI/trellis.cpp"
APP_PORT=8081
APP_LOG="/tmp/trellis_cpp_server.log"
PROC_PAT="trellis-server"
SOURCE_IMAGE="${APP_DIR}/assets/goblin.png"
OUT_GLB="/tmp/trellis_cpp_test.glb"
IOU_MIN=0.65
HU_MAX=0.30

export TRELLIS_CPP_WEIGHTS="${TRELLIS_CPP_WEIGHTS:-q8}"

_cleanup() {
    stop_app "$PROC_PAT" "$APP_PORT" > /dev/null 2>&1 || true
    reset_container || true
}
trap _cleanup EXIT INT TERM

_field() { printf '%s' "$1" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$2'))"; }

_gate() {
    local label="$1" value="$2" expr="$3"
    python3 -c "import sys; v=float('${value}'); sys.exit(0 if ${expr} else 1)" 2>/dev/null \
        || abort "trellis.cpp: ${label} = ${value}, expected ${expr}"
}

test_trellis_cpp() {
    info "============================================="
    info "TEST: trellis.cpp (image to 3D)"
    info "============================================="

    require_container
    clean_hf_incomplete

    stop_app "$PROC_PAT" "$APP_PORT"
    run_install "trellis.cpp" "install_trellis_cpp vulkan" "$APP_DIR"
    require_tests_venv "$APP_DIR" trimesh pillow numpy

    container_file_exists "$SOURCE_IMAGE" \
        || abort "trellis.cpp: the source image ${SOURCE_IMAGE} is missing"

    start_app trellis.cpp "$APP_LOG"

    info "Waiting for the server..."
    wait_for_http_or_abort "trellis.cpp" \
        "curl -sf --max-time 3 http://localhost:${APP_PORT}/health > /dev/null" \
        "$PROC_PAT" "$APP_LOG" 1800 "$APP_DIR"
    pass "Server ready on port ${APP_PORT}"

    if ! listens_on_all_interfaces "$APP_PORT"; then
        fail "  Listening addresses: $(port_listen_addrs "$APP_PORT" | tr '\n' ' ')"
        abort "trellis.cpp: not listening on 0.0.0.0:${APP_PORT}"
    fi
    pass "Listening on 0.0.0.0:${APP_PORT}"

    info "--- Generating a GLB from goblin.png (resolution 512, seed 42) ---"
    ctr "rm -f '${OUT_GLB}'"
    ctr "curl -sf --max-time 3600 -o '${OUT_GLB}' \
            -F 'image=@${SOURCE_IMAGE}' -F 'resolution=512' -F 'seed=42' \
            http://localhost:${APP_PORT}/generate" \
        || { dump_lines "tail -30 '${APP_LOG}'"; abort "trellis.cpp: /generate failed"; }

    container_file_exists "$OUT_GLB" || abort "trellis.cpp: no GLB was written"
    ctr "head -c4 '${OUT_GLB}' | grep -q glTF" \
        || abort "trellis.cpp: the output is not a GLB"
    pass "GLB written ($(ctr "stat -c%s '${OUT_GLB}'") bytes, glTF header verified)"

    require_gpu_process "trellis.cpp" "$PROC_PAT"

    podman cp "${TESTS_DIR}/helpers/mesh_compare.py" "rocm:/tmp/mesh_compare.py" \
        || abort "trellis.cpp: could not copy the comparer into the container"

    local m
    m=$(ctr "cd ${APP_DIR}/tests && source .venv/bin/activate && \
         python /tmp/mesh_compare.py '${OUT_GLB}' '${SOURCE_IMAGE}' 2>/dev/null | tail -1")
    [ -n "$m" ] || abort "trellis.cpp: the mesh comparer returned nothing"
    info "  ${m}"

    _gate "vertex count" "$(_field "$m" vertices)" "v > 100"
    _gate "face count" "$(_field "$m" faces)" "v > 100"
    pass "Mesh has geometry ($(_field "$m" vertices) vertices, $(_field "$m" faces) faces)"

    _gate "silhouette IoU" "$(_field "$m" silhouette_iou)" "v > ${IOU_MIN}"
    pass "Silhouette matches the source image (IoU $(_field "$m" silhouette_iou))"

    _gate "Hu distance" "$(_field "$m" hu_distance)" "v < ${HU_MAX}"
    pass "Shape descriptor matches the source image (Hu distance $(_field "$m" hu_distance))"

    stop_app "$PROC_PAT" "$APP_PORT"
    pass "trellis.cpp stopped"

    ctr "rm -f '${OUT_GLB}' /tmp/mesh_compare.py '${APP_LOG}'"
    info "Test trellis_cpp DONE"
}

main() { test_trellis_cpp; }
main "$@"
