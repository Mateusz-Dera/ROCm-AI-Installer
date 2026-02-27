#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 6: SillyTavern + WhisperSpeech integration
# ============================================================
phase6_sillytavern_integration() {
    info "============================================="
    info "PHASE 6: SILLYTAVERN + WHISPERSPEECH INTEGRATION"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local st_dir="/AI/SillyTavern"
    local st_port=8000
    # WhisperSpeech exposes two servers:
    #   7860 – Gradio web UI
    #   5050 – REST API used by the SillyTavern plugin (POST /generate → audio)
    local ws_api_port=5050
    local ws_gui_port=7860
    local st_log="/tmp/st_server.log"
    local ws_log="/tmp/whisper_server.log"
    local ws_api_url="http://127.0.0.1:${ws_api_port}"

    # --- Verify WhisperSpeech plugin is installed in SillyTavern ---
    local ws_ext_dir="${st_dir}/public/scripts/extensions/third-party/whisperspeech-webui"
    if container_dir_exists "$ws_ext_dir"; then
        pass "WhisperSpeech extension installed at $ws_ext_dir"
    else
        abort "WhisperSpeech extension NOT installed – ${ws_ext_dir} missing"
    fi

    # --- Ensure WhisperSpeech is running (REST API on port 5050) ---
    # The plugin connects to the REST API, not the Gradio GUI.
    if ! podman exec -t rocm bash -c \
           "curl -sf http://localhost:${ws_api_port}/ > /dev/null" 2>/dev/null; then
        info "WhisperSpeech REST API not running – starting it now..."
        podman exec -t rocm bash -c \
            "pkill -f 'webui.py' 2>/dev/null; sleep 1; : > '${ws_log}'" || true
        podman exec -d rocm bash -c \
            "cd /AI/whisperspeech-webui && source .venv/bin/activate \
             && uv run --extra rocm webui.py --listen --api \
             >> '${ws_log}' 2>&1"
        info "Waiting for WhisperSpeech REST API to become ready (up to 600s)..."
        local ws_waited=0 ws_ready=false
        while [ $ws_waited -lt 600 ]; do
            if podman exec -t rocm bash -c \
                   "curl -sf http://localhost:${ws_api_port}/ > /dev/null" 2>/dev/null; then
                ws_ready=true; break
            fi
            sleep 5; ws_waited=$((ws_waited + 5))
            info "  ...waiting for WhisperSpeech REST API ($ws_waited/600s)"
        done
        if ! $ws_ready; then
            podman exec -t rocm bash -c "cat '${ws_log}'" 2>/dev/null || true
            abort "WhisperSpeech REST API did not become ready within 600s"
        fi
        pass "WhisperSpeech REST API ready on port ${ws_api_port}"
    else
        info "WhisperSpeech REST API already running on port ${ws_api_port}"
    fi

    # --- Kill any leftover SillyTavern processes (including start.sh) ---
    podman exec -t rocm bash -c \
        "pkill -f 'start\.sh' 2>/dev/null; pkill -f 'node.*server' 2>/dev/null; true" || true
    sleep 3
    podman exec -t rocm bash -c \
        "fuser -k ${st_port}/tcp 2>/dev/null; true" || true
    sleep 1
    podman exec -t rocm bash -c ": > '$st_log'" || true

    # --- Read basicAuth credentials from config.yaml (default: user/password) ---
    local st_user st_pass
    st_user=$(podman exec -t rocm bash -c \
        "grep -A2 'basicAuthUser:' '$st_dir/config.yaml' | grep 'username:' \
         | sed 's/.*username: *\"//;s/\"//' | tr -d '\r'") || st_user="user"
    st_pass=$(podman exec -t rocm bash -c \
        "grep -A2 'basicAuthUser:' '$st_dir/config.yaml' | grep 'password:' \
         | sed 's/.*password: *\"//;s/\"//' | tr -d '\r'") || st_pass="password"
    # podman exec -t adds \r to line endings via TTY layer – strip on host side
    st_user=$(printf '%s' "$st_user" | tr -d '\r'); st_user="${st_user:-user}"
    st_pass=$(printf '%s' "$st_pass" | tr -d '\r'); st_pass="${st_pass:-password}"
    info "SillyTavern basicAuth: user='$st_user'"

    # --- Start SillyTavern (WhisperSpeech keeps running) ---
    info "Starting SillyTavern (WhisperSpeech keeps running)..."
    podman exec -d rocm bash -c \
        "cd '$st_dir' && bash start.sh >> '$st_log' 2>&1"

    # --- Wait for SillyTavern to become ready ---
    # SillyTavern startup can take up to ~10 min on first run (content file sync +
    # webpack compilation). "Go to:" is printed right after webpack finishes,
    # immediately before the server starts accepting HTTP connections.
    # The log is cleared above (: > '$st_log') so the log-based signal is safe.
    # The process monitor uses 'start.sh' (present from launch until ST exits).
    info "Waiting for SillyTavern to become ready (up to 900s)..."
    local max_wait=900
    local wait_rc=0
    wait_for_http \
        "curl -sf -u '${st_user}:${st_pass}' --max-time 5 http://localhost:${st_port}/ -o /dev/null" \
        "start\.sh" \
        "$st_log" \
        "$max_wait" \
        "Go to:" || wait_rc=$?

    if [ $wait_rc -ne 0 ]; then
        podman exec -t rocm bash -c "cat '$st_log'" 2>/dev/null || true
        if [ $wait_rc -eq 1 ]; then
            abort "SillyTavern process died unexpectedly"
        else
            abort "SillyTavern did not start within ${max_wait}s"
        fi
    fi
    pass "SillyTavern is running on port $st_port"

    # --- Verify main page ---
    info "Verifying SillyTavern main page..."
    # No -t to avoid TTY \r injection into 700KB HTML; retry up to 3x for race
    local st_html_ok=false
    for _i in 1 2 3; do
        info "  HTML check attempt $_i..."
        if podman exec rocm bash -c \
            "curl -sf -u '${st_user}:${st_pass}' http://localhost:${st_port}/ 2>/dev/null \
             | grep -qiE 'SillyTavern|<!DOCTYPE html'" 2>/dev/null; then
            st_html_ok=true; break
        fi
        sleep 2
    done
    if $st_html_ok; then
        pass "SillyTavern main page loads correctly (HTML content verified)"
    else
        podman exec -t rocm bash -c "cat '$st_log'" 2>/dev/null || true
        abort "SillyTavern page did not return expected HTML content"
    fi

    # --- Configure WhisperSpeech plugin URL in SillyTavern settings ---
    # The plugin connects to the REST API (port 5050), not the Gradio GUI (port 7860).
    info "Configuring WhisperSpeech extension URL in SillyTavern settings..."
    local settings_file="$st_dir/data/default-user/settings.json"

    # Wait for SillyTavern to write default settings (up to 30 s)
    local sw=0
    while ! container_file_exists "$settings_file" && [ $sw -lt 30 ]; do
        sleep 3; sw=$((sw + 3))
    done

    if container_file_exists "$settings_file"; then
        # Update plugin URL via python3 (available in container)
        podman exec -t rocm bash -c "
python3 - <<'PYEOF'
import json, sys
path = '$settings_file'
try:
    with open(path, 'r') as f:
        s = json.load(f)
except Exception:
    s = {}
ext = s.setdefault('extension_settings', {})
ws  = ext.setdefault('whisperspeech_webui', {})
ws['server_url'] = '$ws_api_url'
with open(path, 'w') as f:
    json.dump(s, f, indent=2)
print('Settings updated: whisperspeech_webui.server_url =', ws['server_url'])
PYEOF
        " || abort "Failed to update SillyTavern extension settings"
        pass "WhisperSpeech extension URL set to: $ws_api_url"
    else
        abort "SillyTavern settings.json not found – cannot configure extension"
    fi

    # --- Test TTS generation via the REST API (replicates the plugin's Test button) ---
    # The plugin sends POST /generate with JSON and expects a binary audio response.
    info "Testing TTS generation via WhisperSpeech REST API (POST /generate)..."
    local tts_size
    tts_size=$(podman exec -t rocm bash -c "
        curl -sf -X POST http://localhost:${ws_api_port}/generate \
            -H 'Content-Type: application/json' \
            -d '{\"text\": \"Hello, this is a test message!\", \"speed\": 13.5, \"format\": \"wav\", \"model\": \"tiny\"}' \
            -o /tmp/whisperspeech_test.wav \
            -w '%{size_download}' \
            --max-time 120
    " 2>/dev/null | tr -d '\r') || tts_size=0
    tts_size="${tts_size:-0}"

    if [[ "$tts_size" =~ ^[0-9]+$ ]] && [ "$tts_size" -gt 1000 ]; then
        pass "TTS generation OK – received ${tts_size} bytes of audio (WAV)"
    else
        podman exec -t rocm bash -c "cat '${ws_log}'" 2>/dev/null || true
        abort "TTS generation FAILED – /generate returned ${tts_size} bytes (expected > 1000)"
    fi

    # --- Shut down SillyTavern and WhisperSpeech ---
    info "Stopping SillyTavern..."
    podman exec -t rocm bash -c \
        "pkill -f 'start\.sh' 2>/dev/null; pkill -f 'node.*server' 2>/dev/null; \
         fuser -k ${st_port}/tcp 2>/dev/null; true" || true
    local kw=0
    while podman exec -t rocm bash -c "pgrep -f 'node.*server' > /dev/null" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "SillyTavern stopped"

    info "Stopping WhisperSpeech web UI..."
    podman exec -t rocm bash -c "pkill -f 'webui.py' 2>/dev/null || true" || true
    kw=0
    while podman exec -t rocm bash -c "pgrep -f 'webui.py' > /dev/null" 2>/dev/null; do
        sleep 2; kw=$((kw + 2)); if [ $kw -ge 20 ]; then break; fi
    done
    pass "WhisperSpeech web UI stopped"

    info "Phase 6 DONE"
}

main() { phase6_sillytavern_integration; }

main "$@"
