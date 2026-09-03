#!/bin/bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
LOG_FILE="$SCRIPT_DIR/test.log"

usage() {
    echo "Usage: $0 [name ...]" >&2
    echo "  no arguments - run every test" >&2
    echo "  names        - run those tests, in the given order" >&2
    exit 1
}

TEST_FILES=()
if [ $# -eq 0 ]; then
    mapfile -t TEST_FILES < <(
        find "$TESTS_DIR" -maxdepth 1 -name '*.sh' \
            -not -name 'run.sh' -not -name 'common.sh' -not -name 'parakeet.sh' | sort
    )
    TEST_FILES=("$TESTS_DIR/parakeet.sh" "${TEST_FILES[@]}")
else
    for name in "$@"; do
        case "$name" in
            -*) usage ;;
        esac
        if [ -f "$TESTS_DIR/${name}.sh" ]; then
            TEST_FILES+=("$TESTS_DIR/${name}.sh")
        else
            echo "No test file for '${name}'" >&2
            exit 1
        fi
    done
fi

if [ ${#TEST_FILES[@]} -eq 0 ]; then
    echo "No tests found in $TESTS_DIR" >&2
    exit 1
fi

: > "$LOG_FILE"
source "$TESTS_DIR/lib/log.sh"
attach_log "$LOG_FILE"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "============================================="
log "ROCm-AI-Installer test suite"
log "Tests: $(printf '%s ' "${TEST_FILES[@]##*/}")"
log "Log:   $LOG_FILE"
log "============================================="

passed=0
failed_files=()

log "Restarting container 'rocm' for a clean start..."
podman stop rocm > /dev/null 2>&1 || true
podman start rocm > /dev/null || { log "FAIL: could not start container 'rocm'"; exit 1; }
while ! podman exec rocm true 2>/dev/null; do sleep 2; done

source "$TESTS_DIR/common.sh"

for test_file in "${TEST_FILES[@]}"; do
    log ""
    log "========================================"
    log " Running: $(basename "$test_file")"
    log "========================================"
    if bash "$test_file" < /dev/null; then
        log " PASS: $(basename "$test_file")"
        passed=$((passed + 1))
    else
        log " FAIL: $(basename "$test_file")"
        failed_files+=("$(basename "$test_file")")
        break
    fi
done

log ""
log "========================================"
log "RESULTS: ${passed} passed, ${#failed_files[@]} failed"
if [ ${#failed_files[@]} -gt 0 ]; then
    log "Failed: ${failed_files[*]}"
fi
log "========================================"

[ ${#failed_files[@]} -eq 0 ]
