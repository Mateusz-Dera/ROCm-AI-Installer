LLAMA_PORT=8080
LLAMA_PROC="llama-server"
LLAMA_LOG="/tmp/llama_server.log"

_llama_entry() {
    local want="${LLAMA_TQ_MODEL%.gguf}"
    ctr "curl -sf http://localhost:${LLAMA_PORT}/v1/models" | python3 -c "
import sys, json
data = json.load(sys.stdin).get('data') or []
if not data:
    sys.exit(1)
entry = next((d for d in data if d.get('id') == '${want}'), data[0])
print(json.dumps({'id': entry['id'],
                  'args': ' '.join(entry.get('status', {}).get('args') or []),
                  'count': len(data)}))" 2>/dev/null
}

llama_model_id()   { _llama_entry | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])' 2>/dev/null; }
llama_model_args() { _llama_entry | python3 -c 'import sys,json; print(json.load(sys.stdin)["args"])' 2>/dev/null; }
llama_model_count() { _llama_entry | python3 -c 'import sys,json; print(json.load(sys.stdin)["count"])' 2>/dev/null; }

# llama_ask <label> <model id> <prompt> <expected regex>
llama_ask() {
    local label="$1" model="$2" prompt="$3" expected="$4"

    local response
    response=$(ctr "curl -sf --max-time 600 http://localhost:${LLAMA_PORT}/v1/chat/completions \
        -H 'Content-Type: application/json' \
        -d '{\"model\": \"${model}\",
             \"messages\": [{\"role\": \"user\", \"content\": \"${prompt}\"}],
             \"max_tokens\": 256, \"temperature\": 0}'")

    if ! printf '%s' "$response" | grep -q '"choices"'; then
        fail "  Response: $(printf '%s' "$response" | head -c 300)"
        dump_lines "tail -30 '${LLAMA_LOG}'"
        abort "${label}: the API did not return a completion"
    fi

    local answer
    answer=$(printf '%s' "$response" | python3 -c '
import sys, json
m = json.load(sys.stdin)["choices"][0]["message"]
print((m.get("content") or m.get("reasoning_content") or "").strip())') \
        || abort "${label}: could not parse the answer"

    info "  Q: ${prompt}"
    info "  A: \"${answer}\""

    [ -n "$answer" ] || abort "${label}: the model returned an empty answer"
    printf '%s' "$answer" | grep -qiE "$expected" \
        || abort "${label}: the answer does not match /${expected}/ - the model is answering noise"
    pass "${label}: correct answer"

    LLAMA_LAST_TIMINGS=$(printf '%s' "$response" | python3 -c '
import sys, json
t = json.load(sys.stdin).get("timings") or {}
print(json.dumps({k: round(v, 2) for k, v in t.items()
                  if k in ("prompt_per_second", "predicted_per_second",
                           "prompt_n", "predicted_n")}))' 2>/dev/null) || LLAMA_LAST_TIMINGS=""
}

llama_report_speed() {
    local label="$1"
    [ -n "${LLAMA_LAST_TIMINGS:-}" ] || { info "${label}: the API reported no timings"; return 0; }

    local gen prompt
    gen=$(printf '%s' "$LLAMA_LAST_TIMINGS" \
          | python3 -c 'import sys,json; print(json.load(sys.stdin).get("predicted_per_second",0))')
    prompt=$(printf '%s' "$LLAMA_LAST_TIMINGS" \
             | python3 -c 'import sys,json; print(json.load(sys.stdin).get("prompt_per_second",0))')

    python3 -c "import sys; sys.exit(0 if $gen > 0 else 1)" \
        || abort "${label}: generation speed reported as ${gen} tok/s"
    pass "${label}: ${gen} tok/s generated, ${prompt} tok/s prompt"
}

# llama_run_variant <label> <folder> <install function>
llama_run_variant() {
    local label="$1" folder="$2" install_fn="$3"
    local app_dir="/AI/${folder}"

    require_container

    stop_app "$LLAMA_PROC" "$LLAMA_PORT"
    stash_user_models "$folder"

    run_install "$label" "$install_fn" "$app_dir"
    require_gpu_pin "$label" "$folder"

    restore_user_models

    container_file_exists "/AI/${folder}/user-models/${LLAMA_TQ_MODEL}" \
        || abort "${label}: the installer did not place ${LLAMA_TQ_MODEL} in user-models/"
    container_file_exists "/AI/${folder}/drafts/${LLAMA_TQ_MTP}" \
        || abort "${label}: the installer did not place ${LLAMA_TQ_MTP} in drafts/"
    pass "Model and MTP draft downloaded"

    start_app "$folder" "$LLAMA_LOG"

    info "Waiting for the router..."
    wait_for_http_or_abort "$label" \
        "curl -sf http://localhost:${LLAMA_PORT}/health -o /dev/null" \
        "$LLAMA_PROC" "$LLAMA_LOG" 900 "$app_dir"
    pass "Router ready on port ${LLAMA_PORT}"

    if ! listens_on_all_interfaces "$LLAMA_PORT"; then
        fail "  Listening addresses: $(port_listen_addrs "$LLAMA_PORT" | tr '\n' ' ')"
        abort "${label}: not listening on 0.0.0.0:${LLAMA_PORT}"
    fi
    pass "Listening on 0.0.0.0:${LLAMA_PORT}"

    local model_id args
    model_id=$(llama_model_id)
    [ -n "$model_id" ] || abort "${label}: /v1/models listed no model"
    [ "$model_id" = "${LLAMA_TQ_MODEL%.gguf}" ] \
        || abort "${label}: /v1/models does not list ${LLAMA_TQ_MODEL%.gguf} (got ${model_id})"
    pass "Model served: ${model_id} (router lists $(llama_model_count) model(s))"

    args=$(llama_model_args)
    [ -n "$args" ] || abort "${label}: /v1/models reported no launch arguments"
    info "  Model server args: ${args}"

    printf '%s' "$args" | grep -q -- '--cache-type-k turbo3' \
        || abort "${label}: the K cache is not turbo3"
    printf '%s' "$args" | grep -q -- '--cache-type-v turbo3' \
        || abort "${label}: the V cache is not turbo3"
    pass "TurboQuant KV cache active (K and V on turbo3)"

    printf '%s' "$args" | grep -q -- '--ctx-size 262144' \
        || abort "${label}: the context size is not 262144"
    pass "Context size 262144"

    printf '%s' "$args" | grep -qE -- '--flash-attn (on|auto)' \
        || abort "${label}: flash attention is not enabled"
    pass "Flash attention enabled"

    printf '%s' "$args" | grep -q -- "--model-draft .*${LLAMA_TQ_MTP}" \
        || abort "${label}: the MTP draft is not attached to ${model_id}"
    pass "MTP draft attached from models.ini"

    info "--- Generation ---"
    llama_ask "$label" "$model_id" \
        "Name the capital of France. Answer with the city name only." "paris"
    llama_report_speed "$label"

    llama_ask "$label" "$model_id" \
        "What is 17 plus 25? Answer with the number only." "42"

    require_gpu_process "$label" "$LLAMA_PROC"

    stop_app "$LLAMA_PROC" "$LLAMA_PORT"
    pass "${label} stopped"

    ctr "rm -f '${LLAMA_LOG}'"
}
