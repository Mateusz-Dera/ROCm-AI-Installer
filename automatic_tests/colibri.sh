#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# Colibri's full install pulls a ~372 GB model and runs a disk-streamed 744B MoE
# at a few tok/s - neither fits an automated test. This test therefore covers the
# risk area: that the ROCm/HIP GPU backend and the web dashboard actually build on
# this hardware. It clones + builds the same commit the installer pins, verifies
# the GPU binary links against ROCm, and that the launcher runs. Model download and
# inference are intentionally NOT exercised.
test_colibri() {
    info "============================================="
    info "TEST: Colibri (GLM-5.2) ROCm/HIP build + web dashboard"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    local repo="https://github.com/noobdev-ph/colibri"
    local commit="7d17d9b5f18adb9c7b65f357d075f5f33e27b5ff"
    local app_dir="/AI/colibri"

    # --- Clone the pinned commit ---
    info "Cloning colibri @ ${commit:0:8}..."
    podman exec -t rocm bash -c "cd /AI && rm -rf colibri && \
        git clone $repo colibri && cd colibri && git checkout $commit" \
        > /dev/null 2>&1 || abort "Colibri: clone failed"
    pass "Colibri cloned"

    # --- Build the ROCm/HIP GPU backend (the point of this repo) ---
    info "Building ROCm/HIP GPU backend (make HIP=1 HIP_ARCH=${GFX})..."
    if ! podman exec -t rocm bash -c "cd ${app_dir} && \
            export ROCM_HOME=/opt/rocm PATH=/opt/rocm/bin:\$PATH && \
            make -C c glm HIP=1 HIP_ARCH=${GFX} ROCM_HOME=/opt/rocm \
                HIPCCFLAGS='-O3 -std=c++17 -x hip --offload-arch=${GFX} -fPIC -Wall -Wextra'" \
            > /tmp/colibri_build.log 2>&1; then
        podman exec -t rocm bash -c "tail -25 /tmp/colibri_build.log" 2>/dev/null || true
        abort "Colibri: HIP GPU build failed"
    fi
    container_file_exists "${app_dir}/c/colibri" \
        || abort "Colibri: engine binary c/colibri missing after build"
    pass "Colibri HIP GPU engine built"

    # --- Confirm the engine links against ROCm (not a CPU-only fallback) ---
    if ! podman exec -t rocm bash -c "ldd '${app_dir}/c/colibri' 2>/dev/null | grep -q 'libamdhip64'"; then
        abort "Colibri: engine is not linked against ROCm (libamdhip64)"
    fi
    pass "Colibri engine linked against ROCm (libamdhip64)"

    # --- Build the web dashboard ---
    info "Building web dashboard (npm install + build)..."
    if ! podman exec -t rocm bash -c "cd ${app_dir}/web && npm install && npm run build" \
            > /tmp/colibri_web.log 2>&1; then
        podman exec -t rocm bash -c "tail -25 /tmp/colibri_web.log" 2>/dev/null || true
        abort "Colibri: web dashboard build failed"
    fi
    container_dir_exists "${app_dir}/web/dist" \
        || abort "Colibri: web/dist missing after build"
    pass "Colibri web dashboard built"

    # --- Launcher smoke test (system detection; no model required) ---
    local info_out
    info_out=$(podman exec -t rocm bash -c \
        "cd ${app_dir} && COLI_NO_OMP_TUNE=1 ./c/coli info 2>&1" | tr -d '\r') || true
    if ! printf '%s' "$info_out" | grep -qiE 'GLM-5.2|744B|RAM'; then
        info "coli info output: $info_out"
        abort "Colibri: launcher 'coli info' did not run as expected"
    fi
    pass "Colibri launcher runs (coli info)"

    # --- Cleanup (drop the checkout; keeps disk free - no model was downloaded) ---
    podman exec -t rocm bash -c "rm -rf ${app_dir} /tmp/colibri_build.log /tmp/colibri_web.log" 2>/dev/null || true

    info "NOTE: model download (~372 GB) and inference were not tested (size/time)."
    info "Test colibri DONE"
}

main() { test_colibri; }
main "$@"
