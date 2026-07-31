#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

test_trellis2_c() {
    info "============================================="
    info "TEST: trellis2.c ROCm/HIP (install + generate)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."
    clean_hf_incomplete

    # trellis2.c uses public camenduru weight mirrors, so no HF_TOKEN is required.

    # --- Install (ROCm/HIP variant) ---
    # install_trellis2_c takes a backend arg, so wrap it for run_install (which
    # calls its install function with no arguments).
    _install_trellis2_c_hip() { install_trellis2_c hip; }
    run_install "trellis2.c (ROCm)" _install_trellis2_c_hip "/AI/trellis2.c"

    # --- Verify the HIP build produced the binaries ---
    local app_dir="/AI/trellis2.c"
    container_file_exists "${app_dir}/build-hip/trellis2-image-to-gltf" \
        || abort "trellis2.c (ROCm): CLI binary build-hip/trellis2-image-to-gltf missing"
    container_file_exists "${app_dir}/build-hip/trellis-gui" \
        || abort "trellis2.c (ROCm): GUI binary build-hip/trellis-gui missing"
    pass "trellis2.c (ROCm) HIP binaries built"

    # Confirm the CLI links against ROCm (rocBLAS/hipBLAS), not a CPU-only fallback.
    if ! podman exec -t rocm bash -c \
            "ldd '${app_dir}/build-hip/trellis2-image-to-gltf' 2>/dev/null | grep -q 'librocblas'"; then
        abort "trellis2.c (ROCm): CLI is not linked against rocBLAS"
    fi
    pass "trellis2.c (ROCm) CLI linked against ROCm libraries"

    # --- Generate a GLB headlessly via the CLI (the GUI needs an X server) ---
    local glb_out="/AI/trellis2.c/output/test_rocm.glb"
    local gen_log="/tmp/trellis2_c_gen.log"
    podman exec -t rocm bash -c "rm -f '${glb_out}' '${gen_log}'; mkdir -p /AI/trellis2.c/output" || true

    info "Running headless 3D generation via CLI (pipeline 512, seed 1)..."
    # Long timeout: first run also loads models. ~80-90s warm on a 7900XTX.
    if ! podman exec -t rocm bash -c "
            cd '${app_dir}' && export ROCM_PATH=/opt/rocm && \
            timeout 900 ./build-hip/trellis2-image-to-gltf \
                --model /AI/TRELLIS.2/TRELLIS.2-4B \
                --dino /AI/TRELLIS.2/dinov3-vitl16-pretrain-lvd1689m \
                --birefnet /AI/TRELLIS.2/BiRefNet/BiRefNet-F16.gguf \
                --image example_image/T.png \
                --pipeline 512 --seed 1 \
                --output '${glb_out}' > '${gen_log}' 2>&1"; then
        podman exec -t rocm bash -c "tail -30 '${gen_log}'" 2>/dev/null || true
        abort "trellis2.c (ROCm): CLI generation returned non-zero"
    fi

    # --- Verify GLB output ---
    local glb_size
    glb_size=$(podman exec -t rocm bash -c "stat -c %s '${glb_out}' 2>/dev/null" | tr -d '\r') || glb_size=""
    if [ -z "$glb_size" ] || [ "$glb_size" -le 0 ] 2>/dev/null; then
        podman exec -t rocm bash -c "tail -30 '${gen_log}'" 2>/dev/null || true
        abort "trellis2.c (ROCm): output GLB is missing or empty"
    fi
    pass "trellis2.c (ROCm) GLB generated (${glb_size} bytes)"

    # --- Cleanup ---
    podman exec -t rocm bash -c "rm -f '${glb_out}' '${gen_log}'" 2>/dev/null || true

    info "Test trellis2_c DONE"
}

main() { test_trellis2_c; }
main "$@"
