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

# Remove stale .incomplete files from HuggingFace cache (stuck downloads block startup)
clean_hf_incomplete() {
    local count
    count=$(podman exec rocm bash -c \
        "find /root/.cache/huggingface/hub -name '*.incomplete' -delete -print 2>/dev/null | wc -l" \
        | tr -d '\r\n') || count=0
    if [ "${count:-0}" -gt 0 ]; then
        info "Cleaned ${count} incomplete HuggingFace download(s)"
    fi
}

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

# Install an app via its interfaces.sh function, verify directory + run.sh
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
