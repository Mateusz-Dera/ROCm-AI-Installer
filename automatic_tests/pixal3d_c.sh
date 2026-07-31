#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

test_pixal3d_c() {
    info "============================================="
    info "TEST: Pixal3D Experimental (trellis2.c ROCm) install + generate"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."
    clean_hf_incomplete

    # Pixal3D uses public TencentARC/Pixal3D + camenduru mirrors, so no HF_TOKEN.

    # --- Install ---
    # ~24 GB of Pixal3D weights + the trellis2.c ROCm build. Reuses an existing
    # trellis2.c checkout/weights if a trellis2.c install already ran.
    run_install "Pixal3D Experimental" install_pixal3d_c "/AI/trellis2.c"

    local app_dir="/AI/trellis2.c"

    # --- Verify the HIP build produced the Pixal3D CLI ---
    container_file_exists "${app_dir}/build-hip/pixal3d-image-to-gltf" \
        || abort "Pixal3D: CLI binary build-hip/pixal3d-image-to-gltf missing"
    pass "Pixal3D CLI binary built"

    # --- Verify the OOM patch is applied (chunked attention symbol present) ---
    if ! podman exec -t rocm bash -c \
            "grep -q 'trellis_ggml_attention_query_chunk' '${app_dir}/src/ops/ggml/ggml_layers.c'"; then
        abort "Pixal3D: trellis2.c OOM patch not applied (attention chunk missing)"
    fi
    pass "trellis2.c OOM patch applied"

    # --- Verify weights + NAF + manifest are in place ---
    container_file_exists "/AI/Pixal3D/Pixal3D/ckpts/ss_flow_img_dit_1_3B_64_bf16.safetensors" \
        || abort "Pixal3D: DIT weights missing"
    container_file_exists "/AI/Pixal3D/Pixal3D/ckpts/naf_release.safetensors" \
        || abort "Pixal3D: converted NAF weights missing"
    container_file_exists "/AI/Pixal3D/Pixal3D/model.json" \
        || abort "Pixal3D: model.json manifest missing"
    container_file_exists "/AI/Pixal3D/run.sh" \
        || abort "Pixal3D: run.sh missing"
    pass "Pixal3D weights, NAF and manifest present"

    # --- Generate a GLB via the CLI (the flags are what make it fit in 24 GB) ---
    # 1024_cascade is heavy (~1.5M voxels, ~9-10 min on a 7900XTX), hence the long
    # timeout. This is the real end-to-end fit-in-24GB test.
    local glb_out="/AI/trellis2.c/output/test_pixal3d.glb"
    local gen_log="/tmp/pixal3d_c_gen.log"
    podman exec -t rocm bash -c "rm -f '${glb_out}' '${gen_log}'; mkdir -p /AI/trellis2.c/output" || true

    info "Running headless Pixal3D generation (1024_cascade, ~9-10 min)..."
    if ! podman exec -t rocm bash -c "
            cd '${app_dir}' && export ROCM_PATH=/opt/rocm && \
            timeout 1500 ./build-hip/pixal3d-image-to-gltf \
                --model /AI/Pixal3D/Pixal3D \
                --dino /AI/TRELLIS.2/dinov3-vitl16-pretrain-lvd1689m \
                --birefnet /AI/TRELLIS.2/BiRefNet/BiRefNet-F16.gguf \
                --image example_image/T.png \
                --no-ggml-flash-attn \
                --model-cache-budget-mib 2048 \
                --vkmesh-gpu-workspace-budget-mib 12288 \
                --output '${glb_out}' > '${gen_log}' 2>&1"; then
        podman exec -t rocm bash -c "tail -30 '${gen_log}'" 2>/dev/null || true
        abort "Pixal3D: CLI generation returned non-zero (OOM or error)"
    fi

    # --- Verify GLB output (valid glTF header + non-empty) ---
    local glb_size
    glb_size=$(podman exec -t rocm bash -c "stat -c %s '${glb_out}' 2>/dev/null" | tr -d '\r') || glb_size=""
    if [ -z "$glb_size" ] || [ "$glb_size" -le 0 ] 2>/dev/null; then
        podman exec -t rocm bash -c "tail -30 '${gen_log}'" 2>/dev/null || true
        abort "Pixal3D: output GLB is missing or empty"
    fi
    if ! podman exec -t rocm bash -c "head -c 4 '${glb_out}' | grep -q 'glTF'"; then
        abort "Pixal3D: output is not a valid glTF/GLB file"
    fi
    pass "Pixal3D GLB generated (${glb_size} bytes, valid glTF)"

    # --- Cleanup ---
    podman exec -t rocm bash -c "rm -f '${glb_out}' '${gen_log}'" 2>/dev/null || true

    info "Test pixal3d_c DONE"
}

main() { test_pixal3d_c; }
main "$@"
