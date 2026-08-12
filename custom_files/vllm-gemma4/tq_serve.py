"""OpenAI-compatible server with the TurboQuant plugin active.

`vllm serve` cannot be used directly: the plugin installs its hooks through
enable_no_alloc(), which has to run in the serving process *before* the model
is built. So this mirrors api_server.py's __main__ block and only inserts that
call ahead of it. Every vLLM serve flag still works.

Defaults are the configuration verified today: 4-bit keys, 2-bit values, K/V
sharing on. Override the bit widths with TQ_KEY_BITS / TQ_VALUE_BITS.
"""
import os
import sys

os.environ.setdefault("VLLM_ENABLE_V1_MULTIPROCESSING", "0")
os.environ.setdefault("TQ_KV_SHARE", "1")

from turboquant.vllm_attn_backend import enable_no_alloc  # noqa: E402

enable_no_alloc(
    key_bits=int(os.environ.get("TQ_KEY_BITS", "4")),
    value_bits=int(os.environ.get("TQ_VALUE_BITS", "2")),
)

import uvloop  # noqa: E402
from vllm.entrypoints.openai.api_server import run_server  # noqa: E402
from vllm.entrypoints.openai.cli_args import (  # noqa: E402
    make_arg_parser,
    validate_parsed_serve_args,
)
from vllm.entrypoints.serve.utils.api_utils import cli_env_setup  # noqa: E402
from vllm.utils.argparse_utils import FlexibleArgumentParser  # noqa: E402


def main() -> None:
    cli_env_setup()
    parser = FlexibleArgumentParser(
        description="vLLM OpenAI API server with TurboQuant compression."
    )
    parser = make_arg_parser(parser)
    args = parser.parse_args()
    validate_parsed_serve_args(args)
    print("[tq_serve] wtyczka aktywna: k%s v%s, dzielenie K/V=%s"
          % (os.environ.get("TQ_KEY_BITS", "4"),
             os.environ.get("TQ_VALUE_BITS", "2"),
             os.environ.get("TQ_KV_SHARE")), flush=True)
    uvloop.run(run_server(args))


if __name__ == "__main__":
    sys.exit(main())
