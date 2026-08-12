"""Concurrent sessions through the TurboQuant plugin.

The plugin keeps one store per *layer*. With several sequences in flight they
would append into the same ring and read each other's history back - not
slower, wrong. So the point of this script is not throughput but proving
isolation, and a needle test that uses the same codes in every session cannot
prove it: a leaked history would return the expected answer.

Each session therefore gets its own code alphabet. Session 0 plants ALFA/BRAVO,
session 1 plants MIKE/NOVEMBER, and so on. A session is scored only against its
own codes, and any code from *another* session appearing in its answer is
reported as contamination - that is the failure this is built to catch.

Sizes are per session; the memory that matters is their sum, because the
plugin's store grows with total tokens across all of them.
"""
import argparse
import os
import time

os.environ.setdefault("VLLM_ENABLE_V1_MULTIPROCESSING", "0")

DEFAULT_MODEL = os.environ.get(
    "TQ_MODEL", "/AI/models/gemma-4-31B-qat-W4A16-sym-g128")
DEPTHS = [0.0, 0.25, 0.50, 0.75, 0.95]

ALPHABETS = [
    ["ALFA-7734", "BRAVO-2251", "CHARLIE-9013", "DELTA-4468", "ECHO-1195"],
    ["MIKE-3382", "NOVEMBER-6607", "OSCAR-1428", "PAPA-8891", "QUEBEC-5573"],
    ["SIERRA-2094", "TANGO-7715", "UNIFORM-3360", "VICTOR-9982", "WHISKEY-4126"],
    ["XRAY-6538", "YANKEE-1177", "ZULU-8843", "ROMEO-2265", "JULIETT-9704"],
]

QUESTION = (
    "\n\nWymien wszystkie piec kodow dostepu, ktore pojawily sie w tekscie, "
    "w kolejnosci od 1 do 5. Same kody."
)


def build(units: int, codes) -> str:
    unit = "The quick brown fox jumps over the lazy dog. "
    body = [unit] * max(1, units)
    for i, (code, depth) in enumerate(zip(codes, DEPTHS)):
        pos = min(len(body) - 1, int(len(body) * depth))
        body[pos] = f"\n\nZAPAMIETAJ: kod numer {i + 1} to {code}.\n\n"
    return "".join(body) + QUESTION


def count_tokens(tokenizer, prompt: str) -> int:
    """Token count as the engine sees it, chat template included."""
    try:
        encoded = tokenizer.apply_chat_template(
            [{"role": "user", "content": prompt}], add_generation_prompt=True,
        )
    except Exception:  # noqa: BLE001
        return len(tokenizer.encode(prompt))
    if isinstance(encoded, str):
        return len(tokenizer.encode(encoded))
    ids = encoded
    if hasattr(encoded, "input_ids"):
        ids = encoded.input_ids
    elif isinstance(encoded, dict):
        ids = encoded.get("input_ids", encoded)
    if ids and isinstance(ids, (list, tuple)) and isinstance(ids[0], (list, tuple)):
        ids = ids[0]
    return len(ids)


def units_for(tokenizer, target: int, budget: int, codes) -> int:
    """Unit count landing near `target` and never above `budget`."""
    target = min(target, budget)
    probe = 200
    per_unit = max(0.1, count_tokens(tokenizer, build(probe, codes)) / probe)
    hard_max = int(budget / per_unit * 1.5) + 1000
    units = max(1, min(hard_max, int(target / per_unit)))
    actual = count_tokens(tokenizer, build(units, codes))
    for _ in range(6):
        if actual <= 0:
            break
        if actual <= budget and abs(actual - target) <= max(64, target * 0.01):
            break
        nxt = max(1, min(hard_max, int(units * target / actual)))
        if nxt == units:
            break
        units, actual = nxt, count_tokens(tokenizer, build(nxt, codes))
    while actual > budget and units > 1:
        units = max(1, int(units * 0.98))
        actual = count_tokens(tokenizer, build(units, codes))
    return units


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--sessions", type=int, default=2)
    ap.add_argument("--per-session", type=int, default=128000,
                    help="target prompt tokens per session")
    ap.add_argument("--key-bits", type=int, default=4)
    ap.add_argument("--value-bits", type=int, default=2)
    ap.add_argument("--kv-bytes", type=int, default=2_200_000_000)
    ap.add_argument("--max-len", type=int, default=132000)
    ap.add_argument("--max-tokens", type=int, default=256)
    ap.add_argument("--max-batched", type=int, default=512)
    ap.add_argument("--baseline", action="store_true")
    args = ap.parse_args()

    if not args.baseline:
        from turboquant.vllm_attn_backend import enable_no_alloc

        enable_no_alloc(key_bits=args.key_bits, value_bits=args.value_bits)

    from vllm import LLM, SamplingParams

    llm = LLM(
        model=args.model, max_model_len=args.max_len,
        max_num_seqs=args.sessions,
        max_num_batched_tokens=args.max_batched,
        kv_cache_memory_bytes=args.kv_bytes,
        kv_cache_dtype="fp8", enforce_eager=True,
    )
    sampling = SamplingParams(temperature=0.0, max_tokens=args.max_tokens)
    tokenizer = llm.get_tokenizer()
    budget = args.max_len - args.max_tokens

    convs, alphabets = [], []
    for s in range(args.sessions):
        codes = ALPHABETS[s % len(ALPHABETS)]
        alphabets.append(codes)
        units = units_for(tokenizer, args.per_session, budget, codes)
        convs.append([{"role": "user", "content": build(units, codes)}])

    label = "fp8-baseline" if args.baseline else f"tq-k{args.key_bits}v{args.value_bits}"
    start = time.time()
    outs = llm.chat(convs, sampling)
    elapsed = time.time() - start

    total_tokens, all_ok = 0, True
    for s, out in enumerate(outs):
        text = out.outputs[0].text
        mine = [c for c in alphabets[s] if c in text]
        foreign = [c for a in alphabets[:args.sessions] if a is not alphabets[s]
                   for c in a if c in text]
        n_tok = len(out.prompt_token_ids)
        total_tokens += n_tok
        ok = len(mine) == 5 and not foreign
        all_ok &= ok
        print("%s | sesja %d | %6d tok | %d/5 wlasnych%s"
              % (label, s, n_tok, len(mine),
                 "" if not foreign else
                 "  ZANIECZYSZCZENIE: %s" % ", ".join(foreign)),
              flush=True)
        print("    surowo: %r" % text.strip()[:120], flush=True)

    print("%s | %d sesji | razem %d tok | %.1f s | %s"
          % (label, args.sessions, total_tokens, elapsed,
             "OK" if all_ok else "BLAD"), flush=True)

    if not args.baseline:
        try:
            from turboquant.integration.vllm import get_stats

            runner = llm.llm_engine.engine_core.engine_core.model_executor \
                .driver_worker.worker.model_runner
            st = get_stats(runner)
            mb = st.get("total_memory_bytes", 0) / 2**20
            print("    magazyn wtyczki: %.0f MiB na %d warstwach = %.1f KB/token "
                  "(suma wszystkich sesji)"
                  % (mb, st.get("num_layers", 0),
                     mb * 1024 / max(1, total_tokens)), flush=True)

            states = getattr(runner, "_tq_layer_states", {}) or {}
            for name, lstate in list(states.items())[:1]:
                pairs = getattr(lstate, "_per_req", {})
                rn = getattr(lstate, "_runner", None)
                ib = getattr(rn, "input_batch", None)
                for _k, (_st, _en) in list(pairs.items())[:2]:
                    _f = _st.get_flat_cache()
                    print("    magazyn %r: share_kv=%s chunkow=%d tokenow=%d "
                          "ring=%d flat=%s prod_q_None=%s value_q_None=%s"
                          % (str(_k)[:14], _st.share_kv, _st.num_chunks,
                             _st.num_tokens, _en.ring.size,
                             _f is not None,
                             None if _f is None else (_f.prod_q is None),
                             None if _f is None else (_f.value_q is None)),
                          flush=True)
                print("    sciezki: forward=%d domyslny_magazyn=%d hybryda=%d"
                      % (getattr(lstate, "_c_forward", 0),
                         getattr(lstate, "_c_default_store", 0),
                         getattr(lstate, "_c_hybrid", 0)), flush=True)
                klog = getattr(lstate, "_key_log", {"keys": set(), "resets": 0})
                print("    warstwa %s: szczyt %d magazynow / %d tokenow, "
                      "szczyt zywych zadan=%d, zadania=%d, eksmisje=%d, wznowienia=%d"
                      % (name, klog.get("peak_stores", 0),
                         klog.get("peak_tokens", 0),
                         klog.get("peak_live", 0),
                         len([k for k in klog["keys"] if "warmup" not in str(k)]),
                         klog["resets"], klog.get("restarts", 0)), flush=True)
        except Exception as exc:  # noqa: BLE001
            print("    magazyn wtyczki: nieodczytany (%s)" % exc, flush=True)


if __name__ == "__main__":
    main()
