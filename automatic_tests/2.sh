#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 2: INSTALL ALL APPS
# ============================================================
phase2_install() {
    info "============================================="
    info "PHASE 2: INSTALL ALL APPS"
    info "============================================="

    # Helper: run install function, verify directory and (optionally) run.sh exist
    run_install() {
        local name="$1"
        local install_fn="$2"
        local check_dir="$3"
        local need_runsh="${4:-true}"

        info "--- Installing: $name ---"
        if ! "$install_fn"; then
            abort "$name: install function returned non-zero"
        fi

        if ! container_dir_exists "$check_dir"; then
            abort "$name: directory $check_dir not found after install"
        fi

        if $need_runsh && ! container_file_exists "$check_dir/run.sh"; then
            abort "$name: run.sh not found in $check_dir after install"
        fi

        pass "$name installed successfully"
    }

    # ---- Text generation ----
    run_install "KoboldCPP"   install_koboldcpp   "/AI/koboldcpp-rocm"
    run_install "TabbyAPI"    install_tabbyapi    "/AI/tabbyAPI"
    run_install "llama.cpp"   install_llama_cpp   "/AI/llama.cpp"

    # SillyTavern (run.sh uses &&, no venv activate needed)
    run_install "SillyTavern" install_sillytavern "/AI/SillyTavern"

    # SillyTavern – WhisperSpeech web UI extension
    info "--- Installing: SillyTavern WhisperSpeech extension ---"
    if ! install_sillytavern_whisperspeech_web_ui; then
        abort "SillyTavern WhisperSpeech extension: install function returned non-zero"
    fi
    local ws_ext="/AI/SillyTavern/public/scripts/extensions/third-party/whisperspeech-webui"
    if ! container_dir_exists "$ws_ext"; then
        abort "SillyTavern WhisperSpeech extension: directory $ws_ext not found"
    fi
    pass "SillyTavern WhisperSpeech extension installed successfully"

    # ---- Image & Video generation ----
    # Call install_comfyui with no addon args (base install only)
    run_install "ComfyUI" "install_comfyui" "/AI/ComfyUI"

    # ---- Music generation ----
    run_install "ACE-Step"   install_ace_step   "/AI/ACE-Step"
    run_install "HeartMuLa"  install_heartmula  "/AI/heartlib"

    # ---- Voice generation ----
    run_install "WhisperSpeech web UI" install_whisperspeech_web_ui "/AI/whisperspeech-webui"
    run_install "F5-TTS"              install_f5_tts              "/AI/F5-TTS"
    run_install "Soprano"             install_soprano             "/AI/soprano-rocm"

    # ---- 3D generation ----
    run_install "PartCrafter" install_partcrafter "/AI/PartCrafter"
    run_install "TRELLIS-AMD" install_trellis     "/AI/TRELLIS-AMD"

    info "Phase 2 DONE"
}

main() { phase2_install; }

main "$@"
