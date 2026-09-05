TRELLIS_PORT=8081
TRELLIS_UI_PORT=7860
TRELLIS_PROC="app\.py"
TRELLIS_ENGINE="trellis-server"
TRELLIS_LOG="/tmp/trellis_cpp_ui.log"

TRELLIS_IOU_MIN=0.65
TRELLIS_HU_MAX=0.30
TRELLIS_TEX_STD_MIN=20
TRELLIS_TEX_UNIQUE_MIN=0.5

TRELLIS_VARIANTS="q8 full q4"
declare -A TRELLIS_LABEL=(
    [q8]="q8 (10.0 GB)"
    [full]="full (16.5 GB)"
    [q4]="q4 (6.5 GB)"
)

_trellis_field() {
    printf '%s' "$1" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$2'))"
}

_trellis_gate() {
    local label="$1" value="$2" expr="$3"
    python3 -c "import sys; v=float('${value}'); sys.exit(0 if ${expr} else 1)" 2>/dev/null \
        || abort "trellis.cpp: ${label} = ${value}, expected ${expr}"
}

_trellis_variant() {
    local app_dir="$1" variant="$2" label="${TRELLIS_LABEL[$2]}"
    local source_image="${app_dir}/assets/goblin.png"
    local out glb m

    info "--- ${variant}: generating from goblin.png through the web UI ---"
    out="/tmp/trellis_${variant}.json"
    ctr "cd ${app_dir} && source .venv/bin/activate && \
         python /tmp/gradio6_call.py ${TRELLIS_UI_PORT} generate 5400 \
         '[{\"__file__\": \"${source_image}\"}, \"${label}\", \"512\", \"auto\", \"xatlas\", 42, \"off\"]'" \
        > "$out" 2>"${out}.err" \
        || { dump_lines "tail -8 '${TRELLIS_LOG}'"; fail "  $(tail -3 "${out}.err")"; \
             abort "trellis.cpp: generating with the ${variant} weights failed"; }

    glb=$(python3 -c "import json;print(json.load(open('$out'))[0]['path'])" 2>/dev/null) \
        || abort "trellis.cpp: the web UI returned no model for ${variant}"
    pass "${variant}: the web UI returned $(basename "$glb")"

    ctr "head -c4 '${glb}' | grep -q glTF" \
        || abort "trellis.cpp: the ${variant} output is not a GLB"
    pass "${variant}: GLB written ($(ctr "stat -c%s '${glb}'") bytes, glTF header verified)"

    require_gpu_process "trellis.cpp" "$TRELLIS_ENGINE"

    m=$(ctr "cd ${app_dir}/tests && source .venv/bin/activate && \
         python /tmp/mesh_compare.py '${glb}' '${source_image}' 2>/dev/null | tail -1")
    [ -n "$m" ] || abort "trellis.cpp: the mesh comparer returned nothing for ${variant}"
    info "  ${m}"

    _trellis_gate "${variant} vertex count" "$(_trellis_field "$m" vertices)" "v > 100"
    _trellis_gate "${variant} face count" "$(_trellis_field "$m" faces)" "v > 100"
    pass "${variant}: mesh has geometry ($(_trellis_field "$m" vertices) vertices, $(_trellis_field "$m" faces) faces)"

    _trellis_gate "${variant} silhouette IoU" "$(_trellis_field "$m" silhouette_iou)" "v > ${TRELLIS_IOU_MIN}"
    _trellis_gate "${variant} Hu distance" "$(_trellis_field "$m" hu_distance)" "v < ${TRELLIS_HU_MAX}"
    pass "${variant}: shape matches the source image (IoU $(_trellis_field "$m" silhouette_iou), Hu $(_trellis_field "$m" hu_distance))"

    _trellis_gate "${variant} texture presence" "$(_trellis_field "$m" has_texture)" "v == 1"
    _trellis_gate "${variant} UV coordinates" "$(_trellis_field "$m" uv_coords)" "v > 100"
    _trellis_gate "${variant} texture size" "$(_trellis_field "$m" texture_width)" "v >= 256"
    _trellis_gate "${variant} texture spread" "$(_trellis_field "$m" texture_std)" "v > ${TRELLIS_TEX_STD_MIN}"
    _trellis_gate "${variant} texture tonal range" "$(_trellis_field "$m" texture_unique_ratio)" "v > ${TRELLIS_TEX_UNIQUE_MIN}"
    pass "${variant}: model is textured ($(_trellis_field "$m" texture_width)x$(_trellis_field "$m" texture_height) atlas, std $(_trellis_field "$m" texture_std))"

    ctr "rm -f '${glb}'"
    rm -f "$out" "${out}.err"
}

trellis_run_variant() {
    local label="$1" folder="$2" install_fn="$3"
    local app_dir="/AI/${folder}"
    local models_dir="${app_dir}/models"
    local variant

    require_container
    clean_hf_incomplete

    stop_app "$TRELLIS_PROC" "$TRELLIS_UI_PORT"
    stop_app "$TRELLIS_ENGINE" "$TRELLIS_PORT"
    run_install "$label" "$install_fn" "$app_dir"
    require_gpu_pin "$label" "$folder"
    require_tests_venv "$app_dir" trimesh pillow numpy

    container_file_exists "${app_dir}/assets/goblin.png" \
        || abort "${label}: the source image is missing"
    container_file_exists "${app_dir}/examples/bottle.png" \
        || abort "${label}: the installer did not copy the example image"
    pass "Example image copied into the application directory"

    container_file_exists "${app_dir}/build/trellis-server" \
        || abort "${label}: the engine was not built in ${app_dir}/build"
    pass "Engine built in ${folder}/build"

    for variant in $TRELLIS_VARIANTS; do
        container_file_exists "${models_dir}/${variant}/ss_flow.gguf" \
            || abort "${label}: the installer did not download the ${variant} weights into ${models_dir}/${variant}"
    done
    pass "Every weight set lives inside the application directory"

    start_app "$folder" "$TRELLIS_LOG"

    info "Waiting for the web UI..."
    wait_for_http_or_abort "$label" \
        "curl -sf --max-time 3 http://localhost:${TRELLIS_UI_PORT}/gradio_api/info > /dev/null" \
        "$TRELLIS_PROC" "$TRELLIS_LOG" 600 "$app_dir"
    pass "Web UI ready on port ${TRELLIS_UI_PORT}"

    if ! listens_on_all_interfaces "$TRELLIS_UI_PORT"; then
        fail "  Listening addresses: $(port_listen_addrs "$TRELLIS_UI_PORT" | tr '\n' ' ')"
        abort "${label}: the web UI is not listening on 0.0.0.0:${TRELLIS_UI_PORT}"
    fi
    pass "Web UI listening on 0.0.0.0:${TRELLIS_UI_PORT}"

    if [ -n "$(ctr "pgrep -f '[t]rellis-server' | head -1")" ]; then
        abort "${label}: the engine runs before any generation was requested"
    fi
    pass "Engine starts on demand, not at launch"

    podman cp "${TESTS_DIR}/helpers/gradio6_call.py" "rocm:/tmp/gradio6_call.py" \
        || abort "${label}: could not copy the API helper into the container"
    podman cp "${TESTS_DIR}/helpers/mesh_compare.py" "rocm:/tmp/mesh_compare.py" \
        || abort "${label}: could not copy the comparer into the container"

    for variant in $TRELLIS_VARIANTS; do
        _trellis_variant "$app_dir" "$variant"
    done

    if ! listens_on_all_interfaces "$TRELLIS_PORT"; then
        fail "  Listening addresses: $(port_listen_addrs "$TRELLIS_PORT" | tr '\n' ' ')"
        abort "${label}: the engine is not listening on 0.0.0.0:${TRELLIS_PORT}"
    fi
    pass "Engine listening on 0.0.0.0:${TRELLIS_PORT}"

    stop_app "$TRELLIS_PROC" "$TRELLIS_UI_PORT"
    stop_app "$TRELLIS_ENGINE" "$TRELLIS_PORT"
    pass "${label} stopped"

    ctr "rm -f /tmp/mesh_compare.py /tmp/gradio6_call.py '${TRELLIS_LOG}'"
}
