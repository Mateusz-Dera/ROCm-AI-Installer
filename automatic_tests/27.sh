#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 27: RUN AND VERIFY – kimodo (motion generation UI)
# ============================================================
phase27_verify_kimodo() {
    info "============================================="
    info "PHASE 27: RUN AND VERIFY (kimodo)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local app_dir="/AI/kimodo.git"
    local app_port=7860
    local app_log="/tmp/kimodo_server.log"

    # --- Kill any leftover processes ---
    podman exec -t rocm bash -c \
        "pkill -f 'kimodo_demo' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; sleep 1; : > '${app_log}'" || true

    # --- Start kimodo ---
    info "Starting kimodo on port ${app_port} (model loading may take several minutes)..."
    podman exec -d rocm bash -c \
        "cd '${app_dir}' && source .venv/bin/activate && \
         TEXT_ENCODER_DEVICE=cpu kimodo_demo >> '${app_log}' 2>&1"
    sleep 5

    # --- Wait for HTTP (viser server starts only after models are fully loaded) ---
    wait_for_http \
        "curl -sf --max-time 3 http://localhost:${app_port}/ > /dev/null" \
        "kimodo_demo" \
        "${app_log}" \
        300 \
        "Viser server started"

    local wait_rc=$?
    if [ $wait_rc -eq 1 ]; then
        podman exec -t rocm bash -c "tail -30 '${app_log}'" 2>/dev/null || true
        abort "kimodo process died during startup"
    elif [ $wait_rc -eq 2 ]; then
        podman exec -t rocm bash -c "tail -30 '${app_log}'" 2>/dev/null || true
        abort "kimodo did not become ready within 300s"
    fi
    pass "kimodo HTTP server ready on port ${app_port}"

    # --- Verify UI serves valid HTML ---
    local html_ok=false
    podman exec -t rocm bash -c \
        "curl -sf --max-time 5 http://localhost:${app_port}/ | grep -qi 'doctype html'" 2>/dev/null \
        && html_ok=true || true
    $html_ok || abort "kimodo UI did not return valid HTML on port ${app_port}"
    pass "kimodo UI serving valid HTML"

    # --- Stop kimodo ---
    info "Stopping kimodo..."
    podman exec -t rocm bash -c \
        "pkill -f 'kimodo_demo' 2>/dev/null; \
         sleep 2; fuser -k ${app_port}/tcp 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c \
            "fuser ${app_port}/tcp > /dev/null 2>&1" 2>/dev/null; do
        sleep 2; kw=$((kw + 2))
        [ $kw -ge 20 ] && break
    done
    pass "kimodo stopped"

    info "Phase 27 DONE"
}

main() { phase27_verify_kimodo; }
main "$@"
