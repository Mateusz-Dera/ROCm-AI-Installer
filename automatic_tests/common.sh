COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.env"
LOG_FILE="${SCRIPT_DIR}/test.log"

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
attach_log "$LOG_FILE"

source "$SCRIPT_DIR/interfaces.sh"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

_ctr_gfx="$(podman exec rocm printenv TARGET_GFX 2>/dev/null | tr -d '\r')"
if [ -n "$_ctr_gfx" ]; then
    TARGET_GFX="$_ctr_gfx"
fi
export TARGET_GFX="${TARGET_GFX:-gfx1100}"
export GFX="$TARGET_GFX"

HANG_LIMIT="${HANG_LIMIT:-180}"

_log() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}
info()  { _log "INFO" "$*"; }
pass()  { _log "PASS" "$*"; }
fail()  { _log "FAIL" "$*"; }
abort() { fail "$*"; fail "=== TEST ABORTED ==="; exit 1; }

ctr() { podman exec rocm bash -c "$1" 2>/dev/null | tr -d '\r'; }

dump_lines() {
    local text; text=$(ctr "$1" 2>/dev/null) || true
    [ -n "$text" ] || return 0
    printf '%s\n' "$text" | while IFS= read -r line; do fail "  $line"; done
}

port_listen_addrs() {
    local hex; hex=$(printf '%04X' "$1")
    ctr "awk -v p=$hex '\$4==\"0A\"{split(\$2,a,\":\"); if (a[2]==p) print a[1]}' \
         /proc/net/tcp /proc/net/tcp6 2>/dev/null"
}

listens_on_all_interfaces() {
    port_listen_addrs "$1" | grep -qE '^(00000000|0{32})$'
}

container_dir_exists()  { podman exec rocm bash -c "[ -d '$1' ]" 2>/dev/null; }
container_file_exists() { podman exec rocm bash -c "[ -f '$1' ]" 2>/dev/null; }

require_container() {
    podman ps --format '{{.Names}}' 2>/dev/null | grep -q '^rocm$' \
        || abort "Container 'rocm' is not running."
}

reset_container() {
    info "Restarting container 'rocm' to release VRAM..."
    podman stop rocm > /dev/null 2>&1 || true
    podman start rocm > /dev/null 2>&1 || true
    local waited=0
    while ! podman exec rocm true 2>/dev/null; do
        sleep 2; waited=$((waited + 2))
        [ $waited -ge 60 ] && break
    done
    local held; held=$(gpu_pids | awk '{s+=$2} END {print s+0}')
    if [ "${held:-0}" -gt 0 ] 2>/dev/null; then
        info "  Warning: $((held / 1024 / 1024)) MB VRAM still held after the restart"
    else
        info "  VRAM released"
    fi
}

require_hf_token() {
    local app="$1"
    if [ -n "$(ctr 'printf "%s" "${HF_TOKEN:-}"')" ]; then
        info "HF_TOKEN is set in the container"
        return 0
    fi
    abort "HF_TOKEN is not set in the container. Set it via install.sh 'Variables', then re-run 'Create a container'. Required for ${app}."
}

clean_hf_incomplete() {
    local count
    count=$(ctr "find /root/.cache/huggingface/hub -name '*.incomplete' -mmin +30 -delete -print 2>/dev/null | wc -l")
    if [ "${count:-0}" -gt 0 ] 2>/dev/null; then
        info "Cleaned ${count} incomplete HuggingFace download(s)"
    fi
}

run_install() {
    local name="$1" install_fn="$2" check_dir="$3"

    info "--- Installing: $name ---"
    local -a install_cmd
    read -r -a install_cmd <<< "$install_fn"
    "${install_cmd[@]}" < /dev/null || abort "$name: install function returned non-zero"
    container_dir_exists "$check_dir" \
        || abort "$name: $check_dir not found after install"
    container_file_exists "$check_dir/run.sh" \
        || abort "$name: run.sh not found in $check_dir after install"
    pass "$name installed"
}

app_command() {
    local folder="$1" cmd
    cmd=$(ctr "cat '/AI/${folder}/run.sh'" \
          | python3 "${COMMON_DIR}/helpers/unwrap_runsh.py") \
        || abort "Could not read the launch command from /AI/${folder}/run.sh"
    [ -n "$cmd" ] || abort "Could not read the launch command from /AI/${folder}/run.sh"
    printf '%s' "$cmd"
}

app_gpu_clause() {
    ctr "grep -m1 -oE 'export HIP_VISIBLE_DEVICES=[0-9]+' '/AI/$1/run.sh' 2>/dev/null"
}

start_app() {
    local folder="$1" log_file="$2" env_prefix="${3:-}" cmd
    cmd=$(app_command "$folder")
    [ -n "$env_prefix" ] && cmd="export ${env_prefix} && ${cmd}"
    info "Launch command from run.sh: $cmd"
    ctr ": > '${log_file}'"
    podman exec -d rocm bash -c "${cmd} >> '${log_file}' 2>&1" > /dev/null
}

_bracket() {
    case "$1" in
        [A-Za-z0-9]*) printf '[%s]%s' "${1:0:1}" "${1:1}" ;;
        *)            printf '%s' "$1" ;;
    esac
}

_worker_pid() {
    ctr "all=\$(pgrep -f '$1'); \
         for p in \$all; do \
             case \"\$(cat /proc/\$p/comm 2>/dev/null)\" in \
                 bash|sh|dash|'') ;; \
                 *) echo \$p; exit 0 ;; \
             esac; \
         done; \
         printf '%s' \"\$all\" | head -1"
}

app_pid() { _worker_pid "$(_bracket "$1")"; }

stop_app() {
    local proc_pat="$1" port="$2"
    local pat; pat=$(_bracket "$proc_pat")
    ctr "pkill -f '${pat}' 2>/dev/null; true"
    local waited=0
    while [ -n "$(ctr "pgrep -f '${pat}' | head -1")" ] && [ $waited -lt 20 ]; do
        sleep 2; waited=$((waited + 2))
    done
    [ -n "$port" ] && ctr "fuser -k ${port}/tcp 2>/dev/null; true"
    return 0
}

_proc_progress() {
    ctr "awk '{print \$14+\$15}' /proc/$1/stat 2>/dev/null; \
         awk '/^read_bytes|^write_bytes/{print \$2}' /proc/$1/io 2>/dev/null; \
         awk '/^VmRSS/{print \$2}' /proc/$1/status 2>/dev/null"
}

_dump_hang() {
    local pid="$1" venv_dir="$2"
    fail "  wchan:  $(ctr "cat /proc/${pid}/wchan 2>/dev/null")"
    fail "  state:  $(ctr "awk '/^State:/{print \$2,\$3}' /proc/${pid}/status 2>/dev/null")"
    dump_lines "cd '${venv_dir}' && source .venv/bin/activate 2>/dev/null && \
                (command -v py-spy > /dev/null || uv pip install -q py-spy) && \
                py-spy dump --pid ${pid} 2>&1 | head -25"
}

wait_for_http() {
    local check_cmd="$1" proc_pat="$2" log_file="$3" max_wait="$4" venv_dir="${5:-}"
    local pat; pat=$(_bracket "$proc_pat")
    local waited=0 stalled=0 last_log="" last_prog="" cur_log cur_prog pid

    while [ $waited -lt "$max_wait" ]; do
        pid=$(_worker_pid "${pat}")
        if [ -z "$pid" ]; then
            fail "  Process '${proc_pat}' is gone. Last log lines:"
            dump_lines "tail -5 '${log_file}'"
            return 1
        fi

        if podman exec rocm bash -c "$check_cmd" > /dev/null 2>&1; then
            return 0
        fi

        cur_log=$(ctr "tail -1 '${log_file}' 2>/dev/null")
        cur_prog=$(_proc_progress "$pid")

        if [ "$cur_log" = "$last_log" ] && [ "$cur_prog" = "$last_prog" ]; then
            stalled=$((stalled + 5))
            if [ $stalled -ge "$HANG_LIMIT" ]; then
                fail "  No CPU time, no disk reads and no log output for ${stalled}s - hung."
                [ -n "$venv_dir" ] && _dump_hang "$pid" "$venv_dir"
                return 3
            fi
        else
            stalled=0
            [ "$cur_log" != "$last_log" ] && [ -n "$cur_log" ] && info "  log: $cur_log"
        fi
        last_log="$cur_log"; last_prog="$cur_prog"

        sleep 5; waited=$((waited + 5))
        info "  ...waiting (${waited}/${max_wait}s)"
    done
    return 2
}

wait_for_http_or_abort() {
    local name="$1"; shift
    local log_file="$3"
    local rc=0
    wait_for_http "$@" || rc=$?
    case $rc in
        0) return 0 ;;
        1) dump_lines "tail -40 '${log_file}'"
           abort "${name}: process died during startup" ;;
        3) abort "${name}: process hung during startup" ;;
        *) dump_lines "tail -40 '${log_file}'"
           abort "${name}: did not become ready in time" ;;
    esac
}

container_gpus() {
    ctr "rocm-smi --showproductname 2>/dev/null" | awk '
        /^GPU\[/ {
            idx = $0; sub(/^GPU\[/, "", idx); sub(/\].*/, "", idx)
            line = $0
            if (line ~ /Card Series:/) {
                sub(/.*Card Series:[ \t]*/, "", line)
                sub(/[ \t]+$/, "", line)
                series[idx] = line
            } else if (line ~ /GFX Version:/) {
                sub(/.*GFX Version:[ \t]*/, "", line)
                sub(/[ \t]+$/, "", line)
                gfx[idx] = line
            }
            if (idx + 0 > max) max = idx + 0
        }
        END {
            for (i = 0; i <= max; i++)
                if (i in series)
                    printf "%d|%s|%s\n", i, series[i], (i in gfx ? gfx[i] : "?")
        }'
}

select_test_gpu() {
    if [ -n "${GPU_PIN_INDEX:-}" ]; then
        export GPU_PIN_INDEX
        return 0
    fi

    local list count
    list=$(container_gpus)
    count=$(printf '%s\n' "$list" | grep -c . || true)

    if [ "${count:-0}" -le 1 ]; then
        export GPU_PIN_INDEX=0
        return 0
    fi

    local entries=() idx series gfx first=""
    while IFS='|' read -r idx series gfx; do
        [ -n "$idx" ] || continue
        [ -z "$first" ] && first="$idx"
        entries+=("$idx" "${series} (${gfx})" "$([ "$idx" = "$first" ] && echo ON || echo OFF)")
    done <<< "$list"

    local chosen=""
    if [ -r /dev/tty ]; then
        chosen=$(whiptail --title "GPU for the test run" --separate-output \
            --radiolist "The container sees ${count} GPUs.\n\nWhich one should the tests use?\nThe answer is used for every test in this run." \
            16 78 "$count" "${entries[@]}" 2>&1 > /dev/tty) || chosen=""
    fi
    [ -z "$chosen" ] && chosen="$first"

    export GPU_PIN_INDEX="$chosen"
    while IFS='|' read -r idx series gfx; do
        if [ "$idx" = "$chosen" ]; then
            info "Tests will run on GPU ${idx}: ${series} (${gfx})"
        fi
    done <<< "$list"
    return 0
}

select_test_gpu

gpu_pids() {
    ctr "rocm-smi --showpids 2>/dev/null" \
        | awk '$1 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/ && $4 > 0 {print $1, $4}'
}

_drm_vram_kib() {
    local pid="$1" max=0 value file
    for file in /proc/"${pid}"/fdinfo/*; do
        value=$(awk '/^drm-memory-vram:/{print $2; exit}' "$file" 2>/dev/null) || continue
        [ -n "$value" ] || continue
        [ "$value" -gt "$max" ] 2>/dev/null && max="$value"
    done
    printf '%s' "$max"
}

gpu_vram_mib() {
    local proc_pat="$1" best=0 pid vram mib

    while read -r pid vram; do
        [ -n "$pid" ] && [ -r "/proc/${pid}/cmdline" ] || continue
        tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null | grep -qE -- "$proc_pat" || continue
        mib=$((vram / 1024 / 1024))
        [ "$mib" -gt "$best" ] && best="$mib"
    done < <(gpu_pids)

    for pid in $(pgrep -f "$(_bracket "$proc_pat")" 2>/dev/null); do
        mib=$(( $(_drm_vram_kib "$pid") / 1024 ))
        [ "$mib" -gt "$best" ] && best="$mib"
    done

    printf '%s' "$best"
}

require_gpu_process() {
    local label="$1" proc_pat="$2"
    local mib; mib=$(gpu_vram_mib "$proc_pat")

    if [ "${mib:-0}" -le 0 ] 2>/dev/null; then
        dump_lines "rocm-smi --showpids 2>/dev/null"
        abort "${label}: no process matching '${proc_pat}' holds VRAM - not running on the GPU"
    fi
    pass "${label}: running on the GPU (${mib} MB VRAM)"
}

require_gpu_pin() {
    local label="$1" folder="$2"
    [ -n "$(gpu_pin_clause)" ] || return 0
    if ! ctr "grep -q 'HIP_VISIBLE_DEVICES' '/AI/${folder}/run.sh'"; then
        dump_lines "grep 'podman exec -it' '/AI/${folder}/run.sh'"
        abort "${label}: run.sh does not pin a GPU - is GPU_APP=1 missing in the installer?"
    fi
    pass "${label}: run.sh pins GPU ${GPU_PIN_INDEX}"
}

USER_MODELS_STASH=""
USER_MODELS_SUBDIR="user-models"

_stash_dir() { printf '/AI/.%s-stash-%s' "$USER_MODELS_SUBDIR" "$1"; }

restore_user_models() {
    [ -n "$USER_MODELS_STASH" ] || return 0
    local folder="$USER_MODELS_STASH"
    local src dst
    src=$(_stash_dir "$folder"); dst="/AI/${folder}/${USER_MODELS_SUBDIR}"

    container_dir_exists "$src" || { USER_MODELS_STASH=""; return 0; }

    ctr "mkdir -p '${dst}' && mv -n '${src}'/* '${dst}'/ 2>/dev/null; true"
    if [ -n "$(ctr "ls -A '${src}' 2>/dev/null")" ]; then
        info "Warning: files left in ${src} (name clash) - not deleted, move them back by hand"
    else
        ctr "rmdir '${src}' 2>/dev/null || true"
        info "Restored ${folder}/${USER_MODELS_SUBDIR}"
    fi
    USER_MODELS_STASH=""
}

stash_user_models() {
    local folder="$1"
    USER_MODELS_SUBDIR="${2:-user-models}"
    local src dst
    src="/AI/${folder}/${USER_MODELS_SUBDIR}"; dst=$(_stash_dir "$folder")

    USER_MODELS_STASH="$folder"
    restore_user_models

    container_dir_exists "$src" || return 0
    [ -n "$(ctr "ls -A '${src}' 2>/dev/null")" ] || return 0

    local count size
    count=$(ctr "find '${src}' -maxdepth 1 -name '*.gguf' | wc -l")
    size=$(ctr "du -sh '${src}' 2>/dev/null | cut -f1")
    ctr "mv '${src}' '${dst}'" || abort "Could not move ${src} out of the way"
    USER_MODELS_STASH="$folder"
    info "Moved ${folder}/${USER_MODELS_SUBDIR} aside for the reinstall (${count} .gguf, ${size})"
}

TEXT_MODEL_DIR="/AI/koboldcpp-rocm/models"
TEXT_MODEL_PATH=""
TEXT_DRAFT_PATH=""

_fetch_shared() {
    local name="$1" url="$2" dst="${TEXT_MODEL_DIR}/$1"
    if container_file_exists "$dst"; then
        pass "Model available: ${name}"
        return 0
    fi
    info "Downloading ${name}..."
    ctr "mkdir -p '${TEXT_MODEL_DIR}' && wget -q -O '${dst}' '${url}'"
    container_file_exists "$dst" || abort "Could not download ${name} into ${TEXT_MODEL_DIR}"
    pass "Downloaded ${name}"
}

require_text_model() {
    TEXT_MODEL_PATH="${TEXT_MODEL_DIR}/${LLAMA_TQ_MODEL}"
    TEXT_DRAFT_PATH="${TEXT_MODEL_DIR}/${LLAMA_TQ_MTP}"
    _fetch_shared "$LLAMA_TQ_MODEL" "${LLAMA_TQ_HF}/${LLAMA_TQ_MODEL}"
    _fetch_shared "$LLAMA_TQ_MTP" "${LLAMA_TQ_HF}/MTP/${LLAMA_TQ_MTP}"
}

require_tests_venv() {
    local app_dir="$1"; shift
    if ! container_file_exists "${app_dir}/tests/.venv/bin/activate"; then
        info "Creating the analysis venv in ${app_dir}/tests..."
        ctr "mkdir -p '${app_dir}/tests' && cd '${app_dir}/tests' && \
             uv venv --python 3.13 -q && source .venv/bin/activate && uv pip install -q $*"
    fi
    container_file_exists "${app_dir}/tests/.venv/bin/activate" \
        || abort "Could not create the analysis venv in ${app_dir}/tests"
    pass "Analysis venv ready (${*})"
}

PARAKEET_DIR="/AI/parakeet"

require_parakeet() {
    container_dir_exists "${PARAKEET_DIR}/.venv" \
        || abort "Parakeet is not installed - it is the reference transcriber for the speech tests. Install it first (Voice -> Install Parakeet) or run 'automatic_tests/run.sh parakeet'."
}

# transcribe <container_wav_path> -> {"text":..., "seconds":..., "peak":..., "rms":...}
transcribe() {
    podman cp "${TESTS_DIR}/helpers/transcribe.py" "rocm:/tmp/transcribe.py" > /dev/null 2>&1 \
        || return 1
    ctr "cd ${PARAKEET_DIR} && source .venv/bin/activate && \
         python /tmp/transcribe.py '$1' 2>/dev/null | tail -1"
}

# check_speech <label> <container_wav> <expected_text_file> <wer_limit>
check_speech() {
    local label="$1" wav="$2" expected="$3" limit="$4"

    local probe
    probe=$(transcribe "$wav") || abort "${label}: transcription helper failed"
    [ -n "$probe" ] || abort "${label}: transcription helper returned nothing"

    local text seconds rms
    text=$(printf '%s' "$probe" | python3 -c 'import sys,json; print(json.load(sys.stdin)["text"])') \
        || abort "${label}: could not parse the transcription (${probe})"
    seconds=$(printf '%s' "$probe" | python3 -c 'import sys,json; print(json.load(sys.stdin)["seconds"])')
    rms=$(printf '%s' "$probe" | python3 -c 'import sys,json; print(json.load(sys.stdin)["rms"])')

    info "  Audio:      ${seconds} s, RMS ${rms}"
    info "  Transcript: \"${text}\""

    python3 -c "import sys; sys.exit(0 if $rms > 0.001 else 1)" \
        || abort "${label}: the audio is silent (RMS ${rms})"

    local wer_json wer
    wer_json=$(printf '%s' "$text" | python3 "${TESTS_DIR}/helpers/wer.py" "$expected") \
        || abort "${label}: WER computation failed"
    wer=$(printf '%s' "$wer_json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["wer"])')
    info "  ${wer_json}"

    python3 -c "import sys; sys.exit(0 if $wer <= $limit else 1)" \
        || abort "${label}: WER ${wer} exceeds the ${limit} limit - the speech does not match the requested text"

    pass "${label}: speech matches the requested text (WER ${wer}, ${seconds} s)"
}

gradio_upload() {
    local port="$1" file="$2"
    ctr "curl -sf -X POST http://localhost:${port}/gradio_api/upload -F 'files=@${file}'" \
        | python3 -c 'import sys,json; print(json.load(sys.stdin)[0])' 2>/dev/null
}

gradio_call() {
    local port="$1" endpoint="$2" payload="$3" timeout_s="${4:-300}"
    local event_id
    event_id=$(ctr "curl -sf -X POST http://localhost:${port}/gradio_api/call/${endpoint} \
                    -H 'Content-Type: application/json' -d '${payload}'" \
               | grep -o '\"event_id\":\"[^\"]*\"' | grep -o '[^:]*$' | tr -d '\"')
    [ -n "$event_id" ] || return 1
    ctr "curl -sf --max-time ${timeout_s} -N \
         http://localhost:${port}/gradio_api/call/${endpoint}/${event_id}"
}

gradio_complete_data() {
    printf '%s\n' "$1" | grep -A1 '^event: complete' | grep '^data:' | head -1 | cut -c7-
}
