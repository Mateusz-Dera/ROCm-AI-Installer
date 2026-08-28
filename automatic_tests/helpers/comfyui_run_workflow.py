#!/usr/bin/env python3
"""
ComfyUI API test helper.
Reads the workflow JSON (LiteGraph UI format), converts it to ComfyUI API format
using /object_info, submits it, waits for completion and prints the result.

Usage: python3 comfyui_run_workflow.py <workflow_json_path>
Output lines (stdout):
  OUTPUT_OK:<abs_path>:<bytes>   – one line per output file
  OUTPUT_FAIL:<reason>           – on failure
"""
import sys, os, json, time, uuid, asyncio
import aiohttp
import requests

BASE_URL   = "http://localhost:8188"
WS_URL     = "ws://localhost:8188/ws"
STALL_SECS = float(os.environ.get("COMFY_STALL_SECS", "600"))
CLIENT_ID  = str(uuid.uuid4())
OUTPUT_DIR = "/AI/ComfyUI/output"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
def log(msg):
    print(f"[comfyui] {msg}", file=sys.stderr, flush=True)

# ---------------------------------------------------------------------------
# LiteGraph → ComfyUI API format converter
# ---------------------------------------------------------------------------
def fetch_object_info():
    r = requests.get(f"{BASE_URL}/object_info", timeout=30)
    r.raise_for_status()
    return r.json()

def convert(workflow_json, object_info):
    """
    Convert LiteGraph UI-format workflow to ComfyUI API-format prompt dict.
    Links: [link_id, from_node_id, from_slot, to_node_id, to_slot, type]
    Node.inputs[i].link  → link_id of the connection *into* that input slot
    Node.widgets_values  → ordered list of non-linked parameter values
    """
    # link_id → (str(from_node_id), from_slot)
    link_src = {}
    for lnk in workflow_json.get("links", []):
        lid, fn, fs, _tn, _ts, _typ = lnk
        link_src[lid] = (str(fn), fs)

    api = {}
    for node in workflow_json.get("nodes", []):
        node_id    = str(node["id"])
        class_type = node.get("type", "")

        # --- build map: input_name → [src_node_id, src_slot] ---
        linked = {}
        for inp in node.get("inputs", []):
            lid = inp.get("link")
            if lid is not None:
                src = link_src.get(lid)
                if src:
                    linked[inp["name"]] = list(src)

        inputs = dict(linked)  # start with linked inputs

        # --- assign widget values to remaining required parameters ---
        wvals = list(node.get("widgets_values", []))
        widx  = 0

        node_info = object_info.get(class_type, {}).get("input", {})

        for section in ("required", "optional"):
            for pname, pdef in node_info.get(section, {}).items():
                if pname in inputs:
                    continue                    # already linked
                if widx >= len(wvals):
                    break
                val = wvals[widx]
                widx += 1
                inputs[pname] = val

                # After certain widget values the frontend appends extra UI-only
                # values that are NOT API parameters – skip them:
                pdef_opts = pdef[1] if len(pdef) > 1 and isinstance(pdef[1], dict) else {}
                # • image_upload: appends the string "image" (upload type marker)
                if pdef_opts.get("image_upload") and widx < len(wvals):
                    widx += 1
                # • control_after_generate: appends the seed-control string
                #   ("randomize", "fixed", "increment", "decrement")
                if pdef_opts.get("control_after_generate") and widx < len(wvals):
                    widx += 1

        api[node_id] = {"class_type": class_type, "_meta": {"title": class_type}, "inputs": inputs}

    return api

# ---------------------------------------------------------------------------
# ComfyUI API calls
# ---------------------------------------------------------------------------
def submit_prompt(prompt):
    r = requests.post(
        f"{BASE_URL}/prompt",
        json={"prompt": prompt, "client_id": CLIENT_ID},
        timeout=30)
    r.raise_for_status()
    resp = r.json()
    if resp.get("error"):
        raise RuntimeError(f"Prompt validation error: {resp['error']}")
    return resp["prompt_id"]

async def _watch(prompt):
    async with aiohttp.ClientSession() as session:
        async with session.ws_connect(f"{WS_URL}?clientId={CLIENT_ID}", heartbeat=30) as ws:
            prompt_id = submit_prompt(prompt)
            log(f"  prompt_id={prompt_id}")
            last = time.monotonic()
            node = None
            while True:
                left = STALL_SECS - (time.monotonic() - last)
                if left <= 0:
                    raise TimeoutError(
                        f"no progress for {STALL_SECS:.0f}s"
                        + (f" while running node {node}" if node else ""))
                try:
                    msg = await asyncio.wait_for(ws.receive(), timeout=left)
                except asyncio.TimeoutError:
                    continue
                if msg.type == aiohttp.WSMsgType.BINARY:
                    last = time.monotonic()
                    continue
                if msg.type != aiohttp.WSMsgType.TEXT:
                    raise RuntimeError(
                        "ComfyUI closed the websocket - the server died or was restarted "
                        f"(frame {msg.type})")

                event = json.loads(msg.data)
                etype = event.get("type")
                data = event.get("data", {})
                if data.get("prompt_id") not in (None, prompt_id):
                    continue
                last = time.monotonic()

                if etype == "executing":
                    node = data.get("node")
                    if node is not None:
                        log(f"  node {node}")
                elif etype == "progress":
                    v, m = data.get("value", 0), data.get("max", 0)
                    if m and (v == m or v % max(1, m // 4) == 0):
                        log(f"  node {node}: {v}/{m}")
                elif etype == "execution_error":
                    raise RuntimeError(
                        f"node {data.get('node_id')} ({data.get('node_type')}): "
                        f"{data.get('exception_type')}: {data.get('exception_message')}")
                elif etype == "execution_interrupted":
                    raise RuntimeError(f"execution interrupted at node {data.get('node_id')}")
                elif etype == "execution_success":
                    return prompt_id


def run_and_wait(prompt):
    prompt_id = asyncio.run(_watch(prompt))
    r = requests.get(f"{BASE_URL}/history/{prompt_id}", timeout=30)
    r.raise_for_status()
    entry = r.json().get(prompt_id, {})
    return entry.get("outputs", {})


def find_outputs(outputs):
    """Return list of (abs_path, size) for all output files."""
    results = []
    for node_id, node_out in outputs.items():
        for key in ("images", "gifs", "videos"):
            for item in node_out.get(key, []):
                subfolder = item.get("subfolder", "")
                filename  = item.get("filename", "")
                if not filename:
                    continue
                if subfolder:
                    path = os.path.join(OUTPUT_DIR, subfolder, filename)
                else:
                    path = os.path.join(OUTPUT_DIR, filename)
                sz = os.path.getsize(path) if os.path.exists(path) else 0
                results.append((path, sz))
    return results

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    if len(sys.argv) < 2:
        print("Usage: comfyui_run_workflow.py <workflow_json_path>", file=sys.stderr)
        sys.exit(1)

    wf_path = sys.argv[1]
    if not os.path.exists(wf_path):
        print(f"OUTPUT_FAIL:workflow file not found: {wf_path}", flush=True)
        sys.exit(1)

    with open(wf_path) as f:
        workflow_json = json.load(f)

    if "nodes" in workflow_json:
        log("Fetching ComfyUI node object_info...")
        object_info = fetch_object_info()
        log(f"  {len(object_info)} node types known")
        log("Converting workflow to API format...")
        prompt = convert(workflow_json, object_info)
    else:
        prompt = workflow_json
    log(f"  {len(prompt)} nodes in prompt")

    log(f"Submitting prompt (abort after {STALL_SECS:.0f}s without progress)...")
    outputs = run_and_wait(prompt)
    log("  Prompt completed!")

    results = find_outputs(outputs)
    if not results:
        print("OUTPUT_FAIL:no output files in history", flush=True)
        sys.exit(1)

    for path, sz in results:
        print(f"OUTPUT_OK:{path}:{sz}", flush=True)

if __name__ == "__main__":
    main()
