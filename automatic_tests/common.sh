CONFIG_FILE="${SCRIPT_DIR}/.env"
LOG_FILE="${SCRIPT_DIR}/test.log"
TEST_TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"

source "$SCRIPT_DIR/interfaces.sh"
source "$SCRIPT_DIR/backup.sh"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    AI_DIR="${AI_HOST_DIR:-$HOME/AI}"
else
    AI_DIR="$HOME/AI"
fi

_container_env() { podman exec rocm printenv "$1" 2>/dev/null | tr -d '\r'; }

_ctr_gfx="$(_container_env TARGET_GFX)"
if [ -n "$_ctr_gfx" ]; then
    TARGET_GFX="$_ctr_gfx"
fi
export TARGET_GFX="${TARGET_GFX:-gfx1100}"
export GFX="$TARGET_GFX"

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

clean_hf_incomplete() {
    local count
    count=$(podman exec rocm bash -c \
        "find /root/.cache/huggingface/hub -name '*.incomplete' -mmin +30 -delete -print 2>/dev/null | wc -l" \
        | tr -d '\r\n') || count=0
    if [ "${count:-0}" -gt 0 ]; then
        info "Cleaned ${count} incomplete HuggingFace download(s)"
    fi
}

require_hf_token() {
    local app="$1"
    local ctr_tok
    ctr_tok=$(podman exec -t rocm bash -c 'printf "%s" "${HF_TOKEN:-}"' | tr -d '\r')
    if [ -n "$ctr_tok" ]; then
        info "HF_TOKEN is set in the container"
        return 0
    fi
    if [ -n "${HF_TOKEN:-}" ]; then
        abort "HF_TOKEN is in ${CONFIG_FILE} but NOT in the container — the container predates the token. Re-run 'Create a container' (podman-compose down && up -d) to inject it, then retry. Required for ${app} model download."
    else
        abort "HF_TOKEN is not set — add it via install.sh 'Variables', then run 'Create a container'. Required for ${app} model download."
    fi
}

container_dir_exists() {
    podman exec -t rocm bash -c "[ -d '$1' ]" 2>/dev/null
}

container_file_exists() {
    podman exec -t rocm bash -c "[ -f '$1' ]" 2>/dev/null
}

wait_for_http() {
    local check_cmd="$1"
    local proc_pat="$2"
    local log_file="$3"
    local max_wait="$4"
    local log_ready="${5:-}"
    local waited=0 last_log="" cur_log

    while [ $waited -lt $max_wait ]; do
        if ! podman exec -t rocm bash -c "pgrep -f '[$]proc_pat' > /dev/null" 2>/dev/null; then
            info "  Process '$proc_pat' is gone. Last 5 log lines:"
            podman exec -t rocm bash -c "tail -5 '$log_file'" 2>/dev/null || true
            return 1
        fi
        if podman exec -t rocm bash -c "$check_cmd" 2>/dev/null; then
            return 0
        fi
        if [ -n "$log_ready" ] && \
           podman exec -t rocm bash -c "grep -qE '$log_ready' '$log_file' 2>/dev/null" 2>/dev/null; then
            info "  Ready signal in log ('$log_ready') – re-checking HTTP..."
            sleep 1
            if podman exec -t rocm bash -c "$check_cmd" 2>/dev/null; then
                return 0
            fi
        fi
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
