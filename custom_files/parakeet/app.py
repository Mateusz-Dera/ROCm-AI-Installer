#!/usr/bin/env python3
# Parakeet

import argparse
import time

import gradio as gr
import librosa
import torch
from transformers import AutoProcessor, ParakeetForTDT

MODEL_ID = "nvidia/parakeet-tdt-0.6b-v3"
SAMPLE_RATE = 16000
MAX_NEW_TOKENS = 4096

if not torch.cuda.is_available():
    raise SystemExit("No ROCm/CUDA device available - Parakeet runs on the GPU only.")

DEVICE = "cuda"
DTYPE = torch.bfloat16

print(f"Loading {MODEL_ID} on {torch.cuda.get_device_name(0)}...", flush=True)
processor = AutoProcessor.from_pretrained(MODEL_ID)
model = ParakeetForTDT.from_pretrained(MODEL_ID, dtype=DTYPE).to(DEVICE).eval()
print("Model ready.", flush=True)


def _to_device(batch):
    out = {}
    for key, value in batch.items():
        if torch.is_tensor(value) and value.dtype.is_floating_point:
            out[key] = value.to(DEVICE).to(DTYPE)
        elif torch.is_tensor(value):
            out[key] = value.to(DEVICE)
        else:
            out[key] = value
    return out


def transcribe(audio_path):
    if not audio_path:
        raise gr.Error("Upload or record an audio file first.")

    waveform, _ = librosa.load(audio_path, sr=SAMPLE_RATE, mono=True)
    duration = len(waveform) / SAMPLE_RATE
    if duration <= 0:
        raise gr.Error("The audio file is empty.")

    inputs = processor(waveform, sampling_rate=SAMPLE_RATE, return_tensors="pt")
    inputs = _to_device(inputs)

    torch.cuda.synchronize()
    started = time.perf_counter()
    with torch.inference_mode():
        generated = model.generate(**inputs, max_new_tokens=MAX_NEW_TOKENS)
    torch.cuda.synchronize()
    elapsed = time.perf_counter() - started

    text = processor.batch_decode(generated.sequences, skip_special_tokens=True)[0].strip()

    stats = (
        f"Audio: {duration:.2f} s | "
        f"Transcription: {elapsed:.2f} s | "
        f"Real-time factor: {elapsed / duration:.3f}x | "
        f"Peak VRAM: {torch.cuda.max_memory_allocated() / 1e9:.2f} GB"
    )
    return text, stats


def build_ui():
    with gr.Blocks(title="Parakeet") as demo:
        gr.Markdown(f"# Parakeet\n`{MODEL_ID}`")

        with gr.Row():
            with gr.Column(scale=4):
                audio = gr.Audio(
                    label="Audio",
                    type="filepath",
                    sources=["upload", "microphone"],
                )
                run = gr.Button("Transcribe", variant="primary")
            with gr.Column(scale=6):
                text = gr.Textbox(label="Transcription", lines=10)
                stats = gr.Textbox(label="Stats", interactive=False)

        run.click(transcribe, audio, [text, stats])
    return demo


def main():
    parser = argparse.ArgumentParser(description="Parakeet")
    parser.add_argument("--ip", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=7860)
    args = parser.parse_args()

    build_ui().launch(server_name=args.ip, server_port=args.port)


if __name__ == "__main__":
    main()
