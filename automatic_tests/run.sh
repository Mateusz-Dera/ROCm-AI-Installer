#!/bin/bash

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
LOG_FILE="$SCRIPT_DIR/test.log"

SELECTED_TESTS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --test)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                SELECTED_TESTS+=("$1")
                shift
            done
            if [ ${#SELECTED_TESTS[@]} -eq 0 ]; then
                echo "Usage: $0 [--test name [name ...]]" >&2
                exit 1
            fi
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--test name [name ...]]" >&2
            exit 1
            ;;
    esac
done

: > "$LOG_FILE"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*" | tee -a "$LOG_FILE"; }

log "============================================="
log "ROCm-AI-Installer Automated Test Suite"
log "Started: $(date '+%Y-%m-%d_%H-%M-%S')"
log "Log: $LOG_FILE"
log "============================================="

mapfile -t ALL_FILES < <(
    find "$TESTS_DIR" -maxdepth 1 -name '*.sh' -not -name 'run.sh' -not -name 'common.sh' \
        | sort
)

if [ ${#ALL_FILES[@]} -eq 0 ]; then
    log "No test files found in $TESTS_DIR"
    exit 1
fi

if [ ${#SELECTED_TESTS[@]} -gt 0 ]; then
    log "Running selected tests: ${SELECTED_TESTS[*]}"
    TEST_FILES=()
    for name in "${SELECTED_TESTS[@]}"; do
        match="$TESTS_DIR/${name}.sh"
        if [ -f "$match" ]; then
            TEST_FILES+=("$match")
        else
            log "WARN: No test file found for '${name}' – skipping"
        fi
    done
    mapfile -t TEST_FILES < <(printf '%s\n' "${TEST_FILES[@]}" | sort)
    if [ ${#TEST_FILES[@]} -eq 0 ]; then
        log "None of the requested tests exist"
        exit 1
    fi
else
    TEST_FILES=("${ALL_FILES[@]}")
fi

pass_count=0
fail_count=0
failed_files=()

for test_file in "${TEST_FILES[@]}"; do
    log ""
    log "Stopping container 'rocm'..."
    podman stop rocm 2>/dev/null || true
    log "Starting container 'rocm'..."
    podman start rocm || { log "FAIL: Failed to start container 'rocm'"; exit 1; }
    log "Container 'rocm' ready"
    log ""
    log "========================================"
    log " Running: $(basename "$test_file")"
    log "========================================"
    if bash "$test_file"; then
        log "----------------------------------------"
        log " PASS: $(basename "$test_file")"
        log "----------------------------------------"
        pass_count=$((pass_count + 1))
    else
        log "----------------------------------------"
        log " FAIL: $(basename "$test_file")"
        log "----------------------------------------"
        fail_count=$((fail_count + 1))
        failed_files+=("$(basename "$test_file")")
        break
    fi
done

log ""
log "========================================"
log "RESULTS: ${pass_count} passed, ${fail_count} failed"
if [ ${#failed_files[@]} -gt 0 ]; then
    log "Failed: ${failed_files[*]}"
fi
log "========================================"

[ $fail_count -eq 0 ]
