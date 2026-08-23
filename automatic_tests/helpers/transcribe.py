#!/usr/bin/env python3

import json
import sys

import librosa
import torch
from transformers import AutoProcessor, ParakeetForTDT

MODEL_ID = "nvidia/parakeet-tdt-0.6b-v3"
SAMPLE_RATE = 16000


def main():
    audio_path = sys.argv[1]

    if not torch.cuda.is_available():
        print(json.dumps({"error": "no GPU available"}))
        sys.exit(1)

    waveform, _ = librosa.load(audio_path, sr=SAMPLE_RATE, mono=True)
    duration = len(waveform) / SAMPLE_RATE
    peak = float(abs(waveform).max()) if len(waveform) else 0.0
    rms = float((waveform ** 2).mean() ** 0.5) if len(waveform) else 0.0

    processor = AutoProcessor.from_pretrained(MODEL_ID)
    model = ParakeetForTDT.from_pretrained(MODEL_ID, dtype=torch.bfloat16).to("cuda").eval()

    inputs = processor(waveform, sampling_rate=SAMPLE_RATE, return_tensors="pt")
    inputs = {
        key: (value.to("cuda").to(torch.bfloat16)
              if value.dtype.is_floating_point else value.to("cuda"))
        for key, value in inputs.items()
    }

    with torch.inference_mode():
        generated = model.generate(**inputs, max_new_tokens=4096)

    text = processor.batch_decode(generated.sequences, skip_special_tokens=True)[0].strip()

    print(json.dumps({
        "text": text,
        "seconds": round(duration, 2),
        "peak": round(peak, 4),
        "rms": round(rms, 4),
    }))


if __name__ == "__main__":
    main()
