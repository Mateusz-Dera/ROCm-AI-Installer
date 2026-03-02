#!/bin/bash
# Runs all numbered phase scripts (1.sh, 2.sh, …) in order.
# Add a new N.sh to the directory to extend the test suite automatically.
#
# Usage: run.sh [--test N [N ...]]
#   --test N [N ...]   Run only the specified phase numbers (e.g. --test 2 5 6)
#   (no args)          Run all phases in order

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
LOG_FILE="$SCRIPT_DIR/test.log"
TEST_STATE_FILE="/tmp/rocm_ai_test_state.sh"

# ── Parse arguments ───────────────────────────────────────────
SELECTED_TESTS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --test)
            shift
            while [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; do
                SELECTED_TESTS+=("$1")
                shift
            done
            if [ ${#SELECTED_TESTS[@]} -eq 0 ]; then
                echo "Usage: $0 [--test N [N ...]]" >&2
                exit 1
            fi
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--test N [N ...]]" >&2
            exit 1
            ;;
    esac
done

# Reset state from any previous run
rm -f "$TEST_STATE_FILE"
: > "$LOG_FILE"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*" | tee -a "$LOG_FILE"; }

log "============================================="
log "ROCm-AI-Installer Automated Test Suite"
log "Started: $(date '+%Y-%m-%d_%H-%M-%S')"
log "Log: $LOG_FILE"
log "============================================="


# ── Collect and run phase files ───────────────────────────────
mapfile -t ALL_FILES < <(ls -v "$TESTS_DIR"/[0-9]*.sh 2>/dev/null)

if [ ${#ALL_FILES[@]} -eq 0 ]; then
    log "No test files found in $TESTS_DIR"
    exit 1
fi

# Filter to selected tests if --test was given
if [ ${#SELECTED_TESTS[@]} -gt 0 ]; then
    log "Running selected phases: ${SELECTED_TESTS[*]}"
    TEST_FILES=()
    for num in "${SELECTED_TESTS[@]}"; do
        match=$(printf '%s\n' "${ALL_FILES[@]}" | grep -E "/${num}\.sh$" || true)
        if [ -z "$match" ]; then
            log "WARN: No phase file found for number ${num} – skipping"
        else
            TEST_FILES+=("$match")
        fi
    done
    # Sort selected files in numeric order
    mapfile -t TEST_FILES < <(printf '%s\n' "${TEST_FILES[@]}" | sort -V)
    if [ ${#TEST_FILES[@]} -eq 0 ]; then
        log "None of the requested phase numbers exist"
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
        break   # stop on first failure (mirrors original abort-on-error behaviour)
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
