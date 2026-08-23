#!/usr/bin/env python3

import sys

PATH = "/AI/vllm-gemma4/turboquant/integration/vllm.py"

OLD_BATCH = """    runner = getattr(state, "_runner", None)
    batch = getattr(runner, "_tq_batch", None) if runner is not None else None
    ids = getattr(batch, "req_ids", None) if batch is not None else None
    return ids if ids else None"""

NEW_BATCH = """    runner = getattr(state, "_runner", None)
    batch = getattr(runner, "_tq_batch", None) if runner is not None else None
    ids = getattr(batch, "req_ids", None) if batch is not None else None
    if ids:
        return ids
    batch = getattr(runner, "input_batch", None) if runner is not None else None
    ids = getattr(batch, "req_ids", None) if batch is not None else None
    return ids if ids else None"""

OLD_LIVE = """    runner = getattr(state, "_runner", None)
    reqs = getattr(runner, "req_states", None) if runner is not None else None
    table = getattr(reqs, "req_id_to_index", None) if reqs is not None else None
    if not table:
        return None
    return set(table.keys())"""

NEW_LIVE = """    runner = getattr(state, "_runner", None)
    reqs = getattr(runner, "req_states", None) if runner is not None else None
    table = getattr(reqs, "req_id_to_index", None) if reqs is not None else None
    if not table:
        batch = getattr(runner, "input_batch", None) if runner is not None else None
        table = getattr(batch, "req_id_to_index", None) if batch is not None else None
    if not table:
        return None
    return set(table.keys())"""


def main():
    with open(PATH, encoding="utf-8") as handle:
        text = handle.read()

    applied = []
    for name, old, new in (("_batch_req_ids", OLD_BATCH, NEW_BATCH),
                           ("_live_req_ids", OLD_LIVE, NEW_LIVE)):
        if new in text:
            applied.append(f"{name}: already patched")
        elif text.count(old) == 1:
            text = text.replace(old, new)
            applied.append(f"{name}: patched")
        else:
            print(f"ERROR: {name} anchor not found ({text.count(old)} matches)")
            return 1

    with open(PATH, "w", encoding="utf-8") as handle:
        handle.write(text)
    for line in applied:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
