#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

APP_DIR="/AI/TripoSplat"
APP_PORT=7860
APP_LOG="/tmp/triposplat_server.log"
PROC_PAT="run_gradio"
EXAMPLES="${APP_DIR}/static/example_inputs"
SUBJECT_A="building_stone_house"
SUBJECT_B="creature_butterfly"
GAUSSIANS=65536
STEPS=20
COLOUR_MIN=0.60
EXTENT_MIN=0.15
OPACITY_MIN=0.05

_cleanup() {
    stop_app "$PROC_PAT" "$APP_PORT" > /dev/null 2>&1 || true
    reset_container || true
}
trap _cleanup EXIT INT TERM

_field() { printf '%s' "$1" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$2'))"; }

_gate() {
    local label="$1" value="$2" expr="$3"
    python3 -c "import sys; v=float('${value}'); sys.exit(0 if ${expr} else 1)" 2>/dev/null \
        || abort "TripoSplat: ${label} = ${value}, expected ${expr}"
}

_generate() {
    local subject="$1" out="$2"
    local marker="/tmp/triposplat_marker_${subject}"
    ctr "rm -f '${out}' && touch '${marker}'"

    local payload="[{\"__file__\": \"${EXAMPLES}/${subject}.webp\"}, 42, ${STEPS}, 3.0, \"${GAUSSIANS}\", \"ply\"]"
    ctr "cd ${APP_DIR}/tests && source .venv/bin/activate && \
         python /tmp/gradio6_call.py ${APP_PORT} generate 1800 '${payload}' > /dev/null" \
        || { dump_lines "tail -30 '${APP_LOG}'"; abort "TripoSplat: generating ${subject} failed"; }

    local ply
    ply=$(ctr "find ${APP_DIR}/gradio_outputs -name '*.ply' -newer '${marker}' 2>/dev/null | head -1")
    [ -n "$ply" ] || abort "TripoSplat: no PLY was written for ${subject}"
    ctr "cp '${ply}' '${out}' && rm -f '${marker}'"

    ctr "head -c3 '${out}' | grep -q ply" \
        || abort "TripoSplat: the output for ${subject} is not a PLY"
    pass "PLY written for ${subject} ($(ctr "stat -c%s '${out}'") bytes, PLY header verified)"
}

_compare() {
    ctr "cd ${APP_DIR}/tests && source .venv/bin/activate && \
         python /tmp/splat_compare.py '$1' '${EXAMPLES}/$2.webp' 2>/dev/null | tail -1"
}

_check_subject() {
    local subject="$1" ply="$2" other="$3" m cross own
    m=$(_compare "$ply" "$subject")
    [ -n "$m" ] || abort "TripoSplat: the splat comparer returned nothing for ${subject}"
    info "  ${subject}: ${m}"

    _gate "gaussian count for ${subject}" "$(_field "$m" gaussians)" "v > 1000"
    _gate "extent ratio for ${subject}" "$(_field "$m" extent_ratio)" "v > ${EXTENT_MIN}"
    pass "${subject}: $(_field "$m" gaussians) gaussians spread over three axes (extent ratio $(_field "$m" extent_ratio))"

    _gate "mean opacity for ${subject}" "$(_field "$m" mean_opacity)" "v > ${OPACITY_MIN}"
    pass "${subject}: gaussians are opaque enough to render (mean opacity $(_field "$m" mean_opacity))"

    own=$(_field "$m" colour_match)
    _gate "colour match for ${subject}" "$own" "v > ${COLOUR_MIN}"
    pass "${subject}: colour matches its source image (match ${own})"

    cross=$(_field "$(_compare "$ply" "$other")" colour_match)
    _gate "cross match ${subject} against ${other}" "$cross" "v < ${own}"
    pass "${subject}: matches its own image better than ${other} (${own} vs ${cross})"
}

test_triposplat() {
    info "============================================="
    info "TEST: TripoSplat (image to 3D gaussians)"
    info "============================================="

    require_container
    clean_hf_incomplete

    stop_app "$PROC_PAT" "$APP_PORT"
    run_install "TripoSplat" install_triposplat "$APP_DIR"
    require_gpu_pin "TripoSplat" TripoSplat
    require_tests_venv "$APP_DIR" trimesh pillow numpy httpx

    container_file_exists "${EXAMPLES}/${SUBJECT_A}.webp" \
        || abort "TripoSplat: the source image ${EXAMPLES}/${SUBJECT_A}.webp is missing"
    container_file_exists "${EXAMPLES}/${SUBJECT_B}.webp" \
        || abort "TripoSplat: the source image ${EXAMPLES}/${SUBJECT_B}.webp is missing"

    start_app TripoSplat "$APP_LOG"

    info "Waiting for the server..."
    wait_for_http_or_abort "TripoSplat" \
        "curl -sf --max-time 3 http://localhost:${APP_PORT}/gradio_api/info > /dev/null" \
        "$PROC_PAT" "$APP_LOG" 1800 "$APP_DIR"
    pass "Server ready on port ${APP_PORT}"

    if ! listens_on_all_interfaces "$APP_PORT"; then
        fail "  Listening addresses: $(port_listen_addrs "$APP_PORT" | tr '\n' ' ')"
        abort "TripoSplat: not listening on 0.0.0.0:${APP_PORT}"
    fi
    pass "Listening on 0.0.0.0:${APP_PORT}"

    podman cp "${TESTS_DIR}/helpers/gradio6_call.py" "rocm:/tmp/gradio6_call.py" \
        || abort "TripoSplat: could not copy the API helper into the container"
    podman cp "${TESTS_DIR}/helpers/splat_compare.py" "rocm:/tmp/splat_compare.py" \
        || abort "TripoSplat: could not copy the comparer into the container"

    info "--- Generating ${SUBJECT_A} and ${SUBJECT_B} (seed 42, ${STEPS} steps, ${GAUSSIANS} gaussians) ---"
    _generate "$SUBJECT_A" "/tmp/triposplat_${SUBJECT_A}.ply"
    _generate "$SUBJECT_B" "/tmp/triposplat_${SUBJECT_B}.ply"

    require_gpu_process "TripoSplat" "$PROC_PAT"

    _check_subject "$SUBJECT_A" "/tmp/triposplat_${SUBJECT_A}.ply" "$SUBJECT_B"
    _check_subject "$SUBJECT_B" "/tmp/triposplat_${SUBJECT_B}.ply" "$SUBJECT_A"

    stop_app "$PROC_PAT" "$APP_PORT"
    pass "TripoSplat stopped"

    ctr "rm -f /tmp/triposplat_*.ply /tmp/gradio6_call.py /tmp/splat_compare.py '${APP_LOG}'"
    info "Test triposplat DONE"
}

main() { test_triposplat; }
main "$@"
