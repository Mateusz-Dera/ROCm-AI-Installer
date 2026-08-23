#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

APP_DIR="/AI/ACE-Step-1.5"
APP_PORT=7860
APP_LOG="/tmp/ace_step_server.log"
PROC_PAT="acestep_v15_pipeline"

SONG_TAGS="instrumental electronic, steady four-on-the-floor kick drum, simple bass line, no vocals, clean production, constant tempo"
SONG_BPM=120
SONG_KEY="C Major"
SONG_SECONDS=30
SONG_SEED=42

_cleanup() {
    stop_app "$PROC_PAT" "$APP_PORT" > /dev/null 2>&1 || true
    reset_container || true
}
trap _cleanup EXIT INT TERM

_field() { printf '%s' "$1" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$2'))"; }

_gate() {
    local label="$1" value="$2" expr="$3"
    python3 -c "import sys; v=float('${value}'); sys.exit(0 if ${expr} else 1)" 2>/dev/null \
        || abort "ACE-Step: ${label} = ${value}, expected ${expr//v/value}"
}

test_ace_step() {
    info "============================================="
    info "TEST: ACE-Step 1.5 (music generation)"
    info "============================================="

    require_container
    clean_hf_incomplete

    stop_app "$PROC_PAT" "$APP_PORT"
    run_install "ACE-Step-1.5" install_ace_step_1_5 "$APP_DIR"
    require_gpu_pin "ACE-Step-1.5" ACE-Step-1.5
    require_tests_venv "$APP_DIR" librosa soundfile numpy

    start_app ACE-Step-1.5 "$APP_LOG"

    info "Waiting for the Gradio API (model download on first run)..."
    wait_for_http_or_abort "ACE-Step-1.5" \
        "curl -sf http://localhost:${APP_PORT}/gradio_api/info -o /dev/null" \
        "$PROC_PAT" "$APP_LOG" 3600 "$APP_DIR"
    pass "Gradio API ready on port ${APP_PORT}"

    if ! listens_on_all_interfaces "$APP_PORT"; then
        fail "  Listening addresses: $(port_listen_addrs "$APP_PORT" | tr '\n' ' ')"
        abort "ACE-Step-1.5: not listening on 0.0.0.0:${APP_PORT}"
    fi
    pass "Listening on 0.0.0.0:${APP_PORT}"

    info "--- Generating ${SONG_SECONDS}s at ${SONG_BPM} BPM in ${SONG_KEY}, seed ${SONG_SEED} ---"
    local sse
    sse=$(gradio_call "$APP_PORT" generation_wrapper \
        "{\"data\": [\"${SONG_TAGS}\", \"\", ${SONG_BPM}, \"${SONG_KEY}\", \"4/4\", \"en\",
                     20, 7.0, false, ${SONG_SEED}, null, ${SONG_SECONDS}, 1, null, \"\",
                     0, -1, \"\", 0.0, 0.0, \"text2music\", false, false,
                     0.0, 1.0, 3.0, \"ode\", \"euler\", 0.0, 0.0,
                     false, \"double\", 0.05, 0.02, \"haar\", \"\",
                     \"wav\", \"128k\", 48000, 1.0, false, 1.0, 0, 1.0, \"\",
                     false, false, true, null,
                     false, false, false, false, 0.01, 1,
                     \"woodwinds\", [\"woodwinds\"],
                     false, -10.0, 0.0, 0.0, -0.2, 0.5, \"conservative\", 0.0, 0.0, \"\",
                     false, null, null, 0.0, 1.0, 1, false,
                     null, null, null, null]}" 1800) \
        || abort "ACE-Step-1.5: generation_wrapper did not return an event_id"

    if ! printf '%s' "$sse" | grep -q '^event: complete'; then
        fail "  SSE: $(printf '%s' "$sse" | head -5 | tr '\n' ' ')"
        dump_lines "tail -40 '${APP_LOG}'"
        abort "ACE-Step-1.5: no complete event in the SSE stream"
    fi

    local wav
    wav=$(gradio_complete_data "$sse" | python3 -c '
import sys, json
def find(node):
    if isinstance(node, dict):
        if node.get("path", "").endswith((".wav", ".mp3", ".flac")):
            return node["path"]
        for v in node.values():
            got = find(v)
            if got:
                return got
    elif isinstance(node, list):
        for v in node:
            got = find(v)
            if got:
                return got
    return None
print(find(json.load(sys.stdin)) or "")')
    [ -n "$wav" ] || abort "ACE-Step-1.5: no audio file in the complete event"
    container_file_exists "$wav" || abort "ACE-Step-1.5: the audio file ${wav} does not exist"
    pass "Generated ${wav##*/}"

    podman cp "${TESTS_DIR}/helpers/music_analyze.py" "rocm:/tmp/music_analyze.py" \
        || abort "ACE-Step-1.5: could not copy the analyser into the container"

    local m
    m=$(ctr "cd ${APP_DIR}/tests && source .venv/bin/activate && \
         python /tmp/music_analyze.py '${wav}' --bpm ${SONG_BPM} 2>/dev/null | tail -1")
    [ -n "$m" ] || abort "ACE-Step-1.5: the analyser returned nothing"
    info "  ${m}"

    _gate "duration" "$(_field "$m" seconds)" "v >= ${SONG_SECONDS} * 0.9 and v <= ${SONG_SECONDS} * 1.1"
    pass "Duration $(_field "$m" seconds) s matches the requested ${SONG_SECONDS} s"

    _gate "rms" "$(_field "$m" rms)" "v > 0.001"
    _gate "rms variation" "$(_field "$m" rms_variation)" "v > 0.05"
    pass "Audio is neither silent nor a constant drone (RMS $(_field "$m" rms), variation $(_field "$m" rms_variation))"

    _gate "clipped fraction" "$(_field "$m" clipped_fraction)" "v < 0.01"
    pass "No clipping ($(_field "$m" clipped_fraction) of samples at full scale)"

    _gate "spectral flatness" "$(_field "$m" spectral_flatness)" "v < 0.3"
    pass "Tonal, not noise (spectral flatness $(_field "$m" spectral_flatness))"

    _gate "harmonic fraction" "$(_field "$m" harmonic_fraction)" "v > 0.1"
    _gate "percussive fraction" "$(_field "$m" percussive_fraction)" "v > 0.1"
    pass "Both harmonic and percussive content present ($(_field "$m" harmonic_fraction) / $(_field "$m" percussive_fraction))"

    _gate "tempo error" "$(_field "$m" tempo_error)" "v < 0.06"
    pass "Tempo $(_field "$m" tempo) matches the requested ${SONG_BPM} BPM"

    _gate "beat interval spread" "$(_field "$m" beat_interval_cv)" "v < 0.15"
    pass "Steady beat over $(_field "$m" beat_count) beats (spread $(_field "$m" beat_interval_cv))"

    require_gpu_process "ACE-Step-1.5" "$PROC_PAT"

    stop_app "$PROC_PAT" "$APP_PORT"
    pass "ACE-Step-1.5 stopped"

    ctr "rm -f /tmp/music_analyze.py '${APP_LOG}'"
    info "Test ace_step_1_5 DONE"
}

main() { test_ace_step; }
main "$@"
