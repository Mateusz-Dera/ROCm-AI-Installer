#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

APP_DIR="/AI/Krea-2-Turbo"
APP_PORT=7860
APP_LOG="/tmp/krea2_server.log"
PROC_PAT="app\.py"

VRAM_HEADROOM_MB=512
SIZE=1024
STEPS=8
CAT_SEED=42
PERSON_SEED=43
STYLE_LORA="Retro Anime"
IMG_STD_MIN=30
IMG_UNIQUE_MIN=0.8
PROMPT_HAMMING_MIN=60
LORA_HAMMING_MIN=60
EDIT_HAMMING_MIN=30

CAT_PROMPT="A photo of a ginger cat sitting on a wooden floor in a bright living room"
PERSON_PROMPT="A studio portrait photo of a young woman with short dark hair, plain grey background"
EDIT_INSTRUCTION="the woman is sitting on the floor next to the ginger cat"

_cleanup() {
    stop_app "$PROC_PAT" "$APP_PORT" > /dev/null 2>&1 || true
    reset_container || true
}
trap _cleanup EXIT INT TERM

_field() { printf '%s' "$1" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$2'))"; }

_gate() {
    local label="$1" value="$2" expr="$3"
    python3 -c "import sys; v=float('${value}'); sys.exit(0 if ${expr} else 1)" 2>/dev/null \
        || abort "Krea 2: ${label} = ${value}, expected ${expr}"
}

_call() {
    local endpoint="$1" payload="$2" out="$3"
    ctr "cd ${APP_DIR} && source .venv/bin/activate && \
         python /tmp/gradio6_call.py ${APP_PORT} ${endpoint} 2400 '${payload}'" \
        > "$out" 2>"${out}.err" \
        || { dump_lines "tail -8 '${out}.err'"; abort "Krea 2: ${endpoint} failed"; }
    python3 -c "import json,sys; print(json.load(open('$out'))[0]['path'])" 2>/dev/null \
        || abort "Krea 2: ${endpoint} returned no image"
}

_analyze() {
    ctr "cd ${APP_DIR} && source .venv/bin/activate && python /tmp/media_analyze.py $* 2>/dev/null | tail -1"
}

_hamming() { _field "$(_analyze "'$1' --compare '$2'")" hamming; }

_check_image() {
    local label="$1" path="$2" m
    m=$(_analyze "'${path}'")
    [ -n "$m" ] || abort "Krea 2: the analyzer returned nothing for ${label}"
    info "  ${label}: ${m}"

    _gate "width for ${label}" "$(_field "$m" width)" "v == ${SIZE}"
    _gate "height for ${label}" "$(_field "$m" height)" "v == ${SIZE}"
    _gate "pixel spread for ${label}" "$(_field "$m" std)" "v > ${IMG_STD_MIN}"
    _gate "tonal range for ${label}" "$(_field "$m" unique_ratio)" "v > ${IMG_UNIQUE_MIN}"
    pass "${label}: ${SIZE}x${SIZE}, neither blank nor flat (std $(_field "$m" std))"
}

test_krea2() {
    info "============================================="
    info "TEST: Krea 2 Turbo (generate, style LoRA, two-image edit)"
    info "============================================="

    require_container
    require_hf_token "Krea 2 Turbo"
    clean_hf_incomplete

    stop_app "$PROC_PAT" "$APP_PORT"
    run_install "Krea 2 Turbo" install_krea2 "$APP_DIR"
    require_gpu_pin "Krea 2 Turbo" Krea-2-Turbo
    require_tests_venv "$APP_DIR" pillow numpy httpx

    podman cp "${TESTS_DIR}/helpers/gradio6_call.py" "rocm:/tmp/gradio6_call.py" \
        || abort "Krea 2: could not copy the API helper into the container"
    podman cp "${TESTS_DIR}/helpers/media_analyze.py" "rocm:/tmp/media_analyze.py" \
        || abort "Krea 2: could not copy the analyzer into the container"

    start_app Krea-2-Turbo "$APP_LOG" "KREA_VRAM_HEADROOM_MB=${VRAM_HEADROOM_MB}"

    info "Waiting for the model to load..."
    wait_for_http_or_abort "Krea 2" \
        "curl -sf --max-time 3 http://localhost:${APP_PORT}/gradio_api/info > /dev/null" \
        "$PROC_PAT" "$APP_LOG" 3600 "$APP_DIR"
    pass "Gradio API ready on port ${APP_PORT}"

    if ! listens_on_all_interfaces "$APP_PORT"; then
        fail "  Listening addresses: $(port_listen_addrs "$APP_PORT" | tr '\n' ' ')"
        abort "Krea 2: not listening on 0.0.0.0:${APP_PORT}"
    fi
    pass "Listening on 0.0.0.0:${APP_PORT}"

    local cat person combo styled h_prompt h_cat h_person h_lora

    info "--- Generating the cat (seed ${CAT_SEED}) ---"
    cat=$(_call generate \
        "[\"${CAT_PROMPT}\", \"\", \"None\", 1.0, ${STEPS}, 0.0, ${SIZE}, ${SIZE}, ${CAT_SEED}, false]" \
        /tmp/krea2_cat.json)
    pass "Cat image generated"
    _check_image "cat" "$cat"
    require_gpu_process "Krea 2 Turbo" "$PROC_PAT"

    info "--- Generating the person (seed ${PERSON_SEED}) ---"
    person=$(_call generate \
        "[\"${PERSON_PROMPT}\", \"\", \"None\", 1.0, ${STEPS}, 0.0, ${SIZE}, ${SIZE}, ${PERSON_SEED}, false]" \
        /tmp/krea2_person.json)
    pass "Person image generated"
    _check_image "person" "$person"

    h_prompt=$(_hamming "$person" "$cat")
    _gate "hamming between the two prompts" "$h_prompt" "v >= ${PROMPT_HAMMING_MIN}"
    pass "The two prompts produce different images (hamming ${h_prompt}/256)"

    info "--- Combining both images (two-image edit) ---"
    combo=$(_call edit \
        "[{\"__file__\": \"${cat}\"}, {\"__file__\": \"${person}\"}, \"${EDIT_INSTRUCTION}\", 640, ${STEPS}, 4.0, ${CAT_SEED}, false]" \
        /tmp/krea2_combo.json)
    pass "Combined image produced"

    h_cat=$(_hamming "$combo" "$cat")
    h_person=$(_hamming "$combo" "$person")
    info "  combined vs cat: ${h_cat}, vs person: ${h_person}"
    _gate "hamming between the combination and the scene" "$h_cat" "v >= ${EDIT_HAMMING_MIN}"
    _gate "hamming between the combination and the person" "$h_person" "v >= ${EDIT_HAMMING_MIN}"
    pass "The combination differs from both sources (${h_cat} / ${h_person})"

    _gate "the combination should stay closer to the scene" "$h_cat" "v < ${h_person}"
    pass "The combination stays closer to the scene than to the person (${h_cat} < ${h_person})"

    info "--- Generating with the '${STYLE_LORA}' LoRA, same prompt and seed as the cat ---"
    styled=$(_call generate \
        "[\"${CAT_PROMPT}\", \"\", \"${STYLE_LORA}\", 1.0, ${STEPS}, 0.0, ${SIZE}, ${SIZE}, ${CAT_SEED}, false]" \
        /tmp/krea2_lora.json)
    pass "Styled image generated after the edit"
    _check_image "styled" "$styled"

    h_lora=$(_hamming "$styled" "$cat")
    _gate "hamming between the styled and the plain image" "$h_lora" "v >= ${LORA_HAMMING_MIN}"
    pass "The LoRA changes the image at the same seed (hamming ${h_lora}/256)"

    stop_app "$PROC_PAT" "$APP_PORT"
    pass "Krea 2 Turbo stopped"

    ctr "rm -f /tmp/gradio6_call.py /tmp/media_analyze.py '${APP_LOG}'"
    rm -f /tmp/krea2_*.json /tmp/krea2_*.json.err
    info "Test krea2 DONE"
}

main() { test_krea2; }
main "$@"
