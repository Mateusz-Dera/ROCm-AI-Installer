"""Quantize Gemma 4 31B to symmetric 4-bit W4A16 with group size 128.

Why this exact scheme: Sonar/Aphrodite only dispatches its RDNA3 WMMA kernel
(RDNA3W4A16LinearKernel) for scalar_types.uint4b8, i.e. *symmetric* 4-bit. The
public 4-bit Gemma 4 checkpoints are either asymmetric (ebircak, group 128,
19 GB) or symmetric but bloated (google -qat-w4a16-ct, group 32 with an untied
lm_head, 23.3 GB - which leaves 0.25 GiB for the KV cache on a 24 GB card).
This produces the missing combination: symmetric, group 128, embeddings left
tied, which lands around 19 GB.

Only the language tower is quantized. The vision and audio towers are dropped
by loading through Gemma4ForCausalLM - we serve text.

lm_head stays in the ignore list on purpose. Gemma 4 ties it to embed_tokens,
so quantizing it would break the tie and add a separate output matrix.

RTN (QuantizationModifier) is the default because it needs no calibration data
and runs on CPU, so it does not evict a running server from the GPU. It writes
the same on-disk format as GPTQ; GPTQ (--gptq) only buys accuracy.
"""

import argparse
import json
import os

import torch
from transformers import AutoConfig, AutoModelForCausalLM, AutoTokenizer

from llmcompressor import oneshot
from llmcompressor.modifiers.quantization import GPTQModifier, QuantizationModifier

DEFAULT_MODEL = "google/gemma-4-31B-it-qat-q4_0-unquantized"
DEFAULT_OUT = "/AI/vllm-gemma4/models/gemma-4-31B-qat-W4A16-sym-g128"

IGNORE = ["lm_head"]

KEY_MAPPING = {r"^model\.language_model": "model"}


def _text_class(model_id: str):
    """Text-only model class for a multimodal checkpoint."""
    from transformers import Gemma4ForCausalLM

    model_type = AutoConfig.from_pretrained(model_id).model_type
    if model_type.startswith("qwen3_5"):
        from transformers import Qwen3_5ForCausalLM

        return Qwen3_5ForCausalLM
    if model_type.startswith("gemma4"):
        return Gemma4ForCausalLM
    raise ValueError(f"nieznany model_type: {model_type}")


def load_multimodal(model_id: str):
    """Load the checkpoint whole, wrapper and all.

    AutoModelForCausalLM resolves Qwen 3.5/3.6 to the text-only class, which
    produces a checkpoint neither vLLM build can serve - both register only
    Qwen3_5ForConditionalGeneration. Naming the class explicitly keeps the
    wrapper (and the vision tower) intact.
    """
    from transformers import Qwen3_5ForConditionalGeneration

    model, info = Qwen3_5ForConditionalGeneration.from_pretrained(
        model_id, dtype=torch.bfloat16, device_map="cpu",
        output_loading_info=True,
    )
    missing = [
        k for k in info.get("missing_keys", [])
        if "rotary" not in k and not k.startswith("lm_head")
    ]
    if missing:
        raise RuntimeError(
            f"{len(missing)} wag brakuje, np. {missing[:5]}"
        )
    return model


def load_text_tower(model_id: str, trust_remote_code: bool = False):
    """Load only the language tower, and prove the weights really arrived.

    Gemma 4 itself ships as a multimodal checkpoint whose language weights sit
    under `model.language_model.*`, so it needs both the concrete class and the
    key remapping. Derivatives that are already text-only (uyu-2-28B, a pruned
    Gemma 4, stores plain `model.layers.*`) come with their own modeling code and
    have to go through the Auto path with trust_remote_code instead.
    """
    if trust_remote_code:
        model, info = AutoModelForCausalLM.from_pretrained(
            model_id,
            dtype=torch.bfloat16,
            device_map="cpu",
            trust_remote_code=True,
            output_loading_info=True,
        )
        _sd = model.state_dict()
        probe = next(
            (c for c in (
                "model.language_model.layers.0.mlp.down_proj.weight",
                "model.layers.0.mlp.down_proj.weight",
            ) if c in _sd),
            None,
        )
        if probe is None:
            raise RuntimeError("nie znaleziono tensora do weryfikacji w modelu")
        raw_name = None  # resolved against the files below
    else:
        cls = _text_class(model_id)
        model, info = cls.from_pretrained(
            model_id,
            dtype=torch.bfloat16,
            device_map="cpu",
            key_mapping=KEY_MAPPING,
            output_loading_info=True,
        )
        probe = "model.layers.0.mlp.down_proj.weight"
        raw_name = "model.language_model.layers.0.mlp.down_proj.weight"

    missing = [
        k for k in info.get("missing_keys", [])
        if "rotary" not in k and not k.startswith("lm_head")
    ]
    if missing:
        raise RuntimeError(
            f"{len(missing)} weights missing from the checkpoint, e.g. "
            f"{missing[:5]} - the key remapping did not apply"
        )

    import glob

    from safetensors import safe_open

    if os.path.isdir(model_id):
        _candidates = sorted(glob.glob(os.path.join(model_id, "*.safetensors")))
    else:
        _candidates = sorted(glob.glob(
            os.path.expanduser(
                f"~/.cache/huggingface/hub/models--{model_id.replace('/', '--')}"
                "/snapshots/*/*.safetensors"
            )
        ))
    for path in _candidates:
        with safe_open(path, "pt") as f:
            if raw_name is None:
                keys = set(f.keys())
                for candidate in (
                    "model.language_model.layers.0.mlp.down_proj.weight",
                    "model.layers.0.mlp.down_proj.weight",
                ):
                    if candidate in keys:
                        raw_name = candidate
                        break
                else:
                    continue
            if raw_name in f.keys():
                expected = f.get_tensor(raw_name)
                actual = model.state_dict()[probe]
                if not torch.equal(expected, actual):
                    raise RuntimeError(f"{probe} does not match the checkpoint")
                print(f"      verified {probe} against the raw checkpoint",
                      flush=True)
                break
    else:
        raise RuntimeError("nie znaleziono tensora do weryfikacji w plikach")

    return model


def _drop_tied_lm_head(out_dir: str) -> None:
    """Remove lm_head.weight when it is a verbatim copy of the embeddings.

    The QAT release ships lm_head.weight as a full tensor even though its config
    sets tie_word_embeddings: True, and it is bit-identical to
    embed_tokens.weight. At vocab 262144 x 5376 that redundant copy is 2.8 GB -
    2.8 GB the KV cache does not get, on a card where the whole KV budget is
    about 2 GB. It is the same bloat that makes Google's own QAT W4A16 release
    23.3 GB and unusable here.

    Equality is checked before removal: if a future release genuinely unties the
    head and trains it separately, dropping it would silently change the model,
    so in that case it stays.
    """
    import glob

    from safetensors import safe_open
    from safetensors.torch import save_file

    for path in sorted(glob.glob(os.path.join(out_dir, "*.safetensors"))):
        with safe_open(path, "pt") as fh:
            keys = list(fh.keys())
            if "lm_head.weight" not in keys:
                continue
            emb = next((k for k in keys if k.endswith("embed_tokens.weight")), None)
            if emb is None:
                continue
            if not torch.equal(fh.get_tensor("lm_head.weight").float(),
                               fh.get_tensor(emb).float()):
                print("      lm_head is not a copy of the embeddings - keeping it")
                return
            meta = fh.metadata() or {"format": "pt"}
            tensors = {k: fh.get_tensor(k) for k in keys if k != "lm_head.weight"}

        tmp = path + ".new"
        save_file(tensors, tmp, metadata=meta)
        os.replace(tmp, path)
        print("      dropped the tied lm_head copy (%.1f GB saved)"
              % (262144 * 5376 * 2 / 1e9))
        return


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--output", default=DEFAULT_OUT)
    ap.add_argument("--gptq", action="store_true",
                    help="use GPTQ instead of RTN: better accuracy, needs "
                         "calibration data and a GPU")
    ap.add_argument("--trust-remote-code", action="store_true",
                    help="for derivatives shipping their own modeling code")
    ap.add_argument("--full", action="store_true",
                    help="keep the multimodal wrapper instead of extracting the "
                         "text tower - needed when the engine only registers the "
                         "ForConditionalGeneration architecture")
    ap.add_argument("--ignore", default="",
                    help="extra comma-separated ignore patterns, e.g. "
                         "'re:.*linear_attn.*' for Mamba-style layers")
    ap.add_argument("--samples", type=int, default=256)
    ap.add_argument("--seqlen", type=int, default=2048)
    args = ap.parse_args()

    ignore = list(IGNORE) + [x for x in args.ignore.split(",") if x.strip()]
    print(f"[1/4] loading {args.model} (text tower only, bf16)", flush=True)
    print(f"      ignore: {ignore}", flush=True)
    if args.full:
        model = load_multimodal(args.model)
    else:
        model = load_text_tower(args.model, args.trust_remote_code)
    tokenizer = AutoTokenizer.from_pretrained(args.model)

    if args.gptq:
        from datasets import load_dataset

        print(f"[2/4] calibration: {args.samples} samples", flush=True)
        ds = load_dataset("HuggingFaceH4/ultrachat_200k", split="train_sft")
        ds = ds.shuffle(seed=42).select(range(args.samples))

        def preprocess(example):
            return {
                "text": tokenizer.apply_chat_template(
                    example["messages"], tokenize=False
                )
            }

        ds = ds.map(preprocess, remove_columns=ds.column_names)
        recipe = GPTQModifier(targets="Linear", scheme="W4A16", ignore=ignore)
        kwargs = dict(
            dataset=ds,
            max_seq_length=args.seqlen,
            num_calibration_samples=args.samples,
        )
    else:
        print("[2/4] RTN: no calibration data needed", flush=True)
        recipe = QuantizationModifier(
            targets="Linear", scheme="W4A16", ignore=ignore
        )
        kwargs = {}

    print("[3/4] quantizing -> W4A16 symmetric, group 128", flush=True)
    oneshot(model=model, recipe=recipe, output_dir=args.output, **kwargs)

    tokenizer.save_pretrained(args.output)

    _drop_tied_lm_head(args.output)

    config_path = os.path.join(args.output, "config.json")
    with open(config_path) as fh:
        config = json.load(fh)
    if config.pop("use_bidirectional_attention", None) is not None:
        with open(config_path, "w") as fh:
            json.dump(config, fh, indent=2)
        print("      dropped use_bidirectional_attention (text-only model)",
              flush=True)

    print(f"[4/4] written to {args.output}", flush=True)

    total = sum(
        os.path.getsize(os.path.join(args.output, f))
        for f in os.listdir(args.output)
        if f.endswith(".safetensors")
    )
    print(f"      safetensors: {total / 1e9:.1f} GB", flush=True)


if __name__ == "__main__":
    main()
