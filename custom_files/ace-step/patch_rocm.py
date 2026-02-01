#!/usr/bin/env python3
"""
ROCm compatibility patches for ACE-Step.
Fixes:
1. Adds warmup decode after model load to speed up first generation
2. Replaces torchaudio.save with soundfile to avoid torchcodec issues
"""

import re

PIPELINE_FILE = 'acestep/pipeline_ace_step.py'

with open(PIPELINE_FILE, 'r') as f:
    content = f.read()

# Patch 1: Add ROCm warmup after model load
warmup_code = '''
        # ROCm warmup: Run a short decode to initialize kernels
        if torch.cuda.is_available() and hasattr(self, "music_dcae"):
            try:
                print("Running ROCm warmup decode (this speeds up first generation)...")
                warmup_latent = torch.randn(1, 8, 16, 54, device=self.device, dtype=self.dtype)
                with torch.no_grad():
                    _, _ = self.music_dcae.decode(warmup_latent, sr=48000)
                print("Warmup complete.")
            except Exception as e:
                print(f"Warmup skipped: {e}")
'''

# Find the line "self.loaded = True" and add warmup after it
if 'ROCm warmup' not in content:
    content = content.replace(
        '        self.loaded = True\n',
        '        self.loaded = True\n' + warmup_code
    )
    print("Patch 1 applied: Added ROCm warmup")
else:
    print("Patch 1 skipped: ROCm warmup already present")

# Patch 2: Replace torchaudio.save with soundfile
old_save = '''        target_wav = target_wav.float()
        backend = "soundfile"
        if format == "ogg":
            backend = "sox"
        logger.info(f"Saving audio to {output_path_wav} using backend {backend}")
        torchaudio.save(
            output_path_wav, target_wav, sample_rate=sample_rate, format=format, backend=backend
        )'''

new_save = '''        target_wav = target_wav.float()
        # Ensure the output path has the correct extension
        if not output_path_wav.endswith(f".{format}"):
            output_path_wav = f"{output_path_wav}.{format}"
        logger.info(f"Saving audio to {output_path_wav}")
        import soundfile as sf
        # Convert from (channels, samples) to (samples, channels) for soundfile
        wav_numpy = target_wav.cpu().numpy().T
        sf.write(output_path_wav, wav_numpy, sample_rate)'''

if 'soundfile as sf' not in content:
    content = content.replace(old_save, new_save)
    print("Patch 2 applied: Replaced torchaudio.save with soundfile")
else:
    print("Patch 2 skipped: soundfile save already present")

with open(PIPELINE_FILE, 'w') as f:
    f.write(content)

print("ROCm patches complete!")
