#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

test_autoremesher() {
    info "============================================="
    info "TEST: AutoRemesher (build + headless CLI remesh)"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    run_install "AutoRemesher" install_autoremesher "/AI/autoremesher"

    local app_dir="/AI/autoremesher"

    container_file_exists "${app_dir}/autoremesher" \
        || abort "AutoRemesher: binary ./autoremesher missing after build"
    pass "AutoRemesher binary built"

    info "Generating a test mesh (UV sphere)..."
    podman exec -t rocm bash -c "cd '${app_dir}' && python3 -c \"
import math
S=48; R=24  # stacks / rings -> a few thousand triangles
V=[]; F=[]
for i in range(S+1):
    la=math.pi*i/S
    for j in range(R):
        lo=2*math.pi*j/R
        V.append((math.sin(la)*math.cos(lo), math.cos(la), math.sin(la)*math.sin(lo)))
def idx(i,j): return i*R + (j%R) + 1
for i in range(S):
    for j in range(R):
        a=idx(i,j); b=idx(i+1,j); c=idx(i+1,j+1); d=idx(i,j+1)
        F.append((a,b,c)); F.append((a,c,d))
with open('sphere.obj','w') as f:
    for x,y,z in V: f.write(f'v {x:.5f} {y:.5f} {z:.5f}\n')
    for a,b,c in F: f.write(f'f {a} {b} {c}\n')
print('verts',len(V),'faces',len(F))
\"" 2>&1 | tr -d '\r' || abort "AutoRemesher: failed to generate test mesh"

    info "Running headless quad remesh via CLI..."
    if ! podman exec -t rocm bash -c "cd '${app_dir}' && \
            ./autoremesher --input sphere.obj --output remeshed.obj \
                --report remeshed_report.txt --target-quads 2000 \
                --edge-scaling 1.0 --sharp-edge 90.0 --smooth-normal 0.0 --adaptivity 1.0 \
            > /tmp/autoremesher_run.log 2>&1"; then
        podman exec -t rocm bash -c "tail -25 /tmp/autoremesher_run.log" 2>/dev/null || true
        abort "AutoRemesher: CLI remesh returned non-zero"
    fi

    local out_size
    out_size=$(podman exec -t rocm bash -c "stat -c %s '${app_dir}/remeshed.obj' 2>/dev/null" | tr -d '\r') || out_size=""
    if [ -z "$out_size" ] || [ "$out_size" -le 0 ] 2>/dev/null; then
        podman exec -t rocm bash -c "tail -25 /tmp/autoremesher_run.log" 2>/dev/null || true
        abort "AutoRemesher: output remeshed.obj is missing or empty"
    fi
    if ! podman exec -t rocm bash -c "grep -qE '^f( +[0-9]+){4}' '${app_dir}/remeshed.obj'"; then
        abort "AutoRemesher: output has no quad faces (remesh did not produce quads)"
    fi
    pass "AutoRemesher produced a quad mesh (${out_size} bytes)"

    podman exec -t rocm bash -c \
        "rm -f '${app_dir}/sphere.obj' '${app_dir}/remeshed.obj' '${app_dir}/remeshed_report.txt' /tmp/autoremesher_run.log" 2>/dev/null || true

    info "Test autoremesher DONE"
}

main() { test_autoremesher; }
main "$@"
