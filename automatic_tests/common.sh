CONFIG_FILE="${SCRIPT_DIR}/.env"
LOG_FILE="${SCRIPT_DIR}/test.log"
TEST_TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"

# Load config and install helpers
source "$SCRIPT_DIR/interfaces.sh"
source "$SCRIPT_DIR/backup.sh"

# Load configuration (.env)
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    export GFX="${TARGET_GFX:-gfx1100}"
    AI_DIR="${AI_HOST_DIR:-$HOME/AI}"
else
    export GFX="gfx1100"
    AI_DIR="$HOME/AI"
fi

# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------
_log() {
    local level="$1"; shift
    local msg="$*"
    local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$level] $msg" | tee -a "$LOG_FILE"
}
info()  { _log "INFO"  "$*"; }
pass()  { _log "PASS"  "$*"; }
fail()  { _log "FAIL"  "$*"; }
abort() { fail "$*"; fail "=== TEST ABORTED ==="; exit 1; }

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

# Check whether a directory exists inside the container
container_dir_exists() {
    podman exec -t rocm bash -c "[ -d '$1' ]" 2>/dev/null
}

# Check whether a file exists inside the container
container_file_exists() {
    podman exec -t rocm bash -c "[ -f '$1' ]" 2>/dev/null
}

# wait_for_http CHECK_CMD PROC_PATTERN LOG_FILE MAX_WAIT [LOG_READY_PATTERN]
# Polls CHECK_CMD (bash snippet run inside the container) every 3 s.
# Monitors process liveness (pgrep -f PROC_PATTERN) – fails immediately if
# the process dies.  Tails LOG_FILE for live progress feedback.
# Optional LOG_READY_PATTERN: grep -qE in log → extra HTTP probe (early hint).
# Returns: 0 = ready, 1 = process died, 2 = timeout
wait_for_http() {
    local check_cmd="$1"
    local proc_pat="$2"
    local log_file="$3"
    local max_wait="$4"
    local log_ready="${5:-}"
    local waited=0 last_log="" cur_log

    while [ $waited -lt $max_wait ]; do
        # Fail fast: is the process still alive?
        if ! podman exec -t rocm bash -c "pgrep -f '$proc_pat' > /dev/null" 2>/dev/null; then
            info "  Process '$proc_pat' is gone. Last 5 log lines:"
            podman exec -t rocm bash -c "tail -5 '$log_file'" 2>/dev/null || true
            return 1
        fi
        # Main readiness probe (HTTP / grep)
        if podman exec -t rocm bash -c "$check_cmd" 2>/dev/null; then
            return 0
        fi
        # Log-based early-ready signal (optional)
        if [ -n "$log_ready" ] && \
           podman exec -t rocm bash -c "grep -qE '$log_ready' '$log_file' 2>/dev/null" 2>/dev/null; then
            info "  Ready signal in log ('$log_ready') – re-checking HTTP..."
            sleep 1
            if podman exec -t rocm bash -c "$check_cmd" 2>/dev/null; then
                return 0
            fi
        fi
        # Show latest changed log line for live progress
        cur_log=$(podman exec -t rocm bash -c \
            "tail -1 '$log_file' 2>/dev/null" | tr -d '\r') || cur_log=""
        if [ -n "$cur_log" ] && [ "$cur_log" != "$last_log" ]; then
            info "  log: $cur_log"
            last_log="$cur_log"
        fi
        sleep 3
        waited=$((waited + 3))
        info "  ...waiting ($waited/${max_wait}s)"
    done
    return 2
}

# ------------------------------------------------------------
# Inter-phase state (persisted via temp file)
# ------------------------------------------------------------
TEST_STATE_FILE="/tmp/rocm_ai_test_state.sh"
SILLYTAVERN_WAS_INSTALLED=false
TABBYAPI_WAS_INSTALLED=false
# Load state from previous phase if it exists
if [ -f "$TEST_STATE_FILE" ]; then
    source "$TEST_STATE_FILE"
fi
