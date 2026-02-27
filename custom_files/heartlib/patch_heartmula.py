#!/usr/bin/env python3
"""Patch heartmula for torchtune compatibility"""

import sys

# Read the file
with open(sys.argv[1], 'r') as f:
    content = f.read()

# Find and replace the setup_caches method
old_setup_caches = '''    def setup_caches(self, max_batch_size: int):
        dtype = next(self.parameters()).dtype
        device = next(self.parameters()).device

        try:
            self.reset_caches()
        except RuntimeError:
            pass

        with device:
            self.backbone.setup_caches(max_batch_size, dtype)
            self.decoder.setup_caches(
                max_batch_size,
                dtype,
                decoder_max_seq_len=self.config.audio_num_codebooks,
            )

        self.register_buffer(
            "backbone_causal_mask",
            _create_causal_mask(self.backbone.max_seq_len, device),
        )
        self.register_buffer(
            "decoder_causal_mask",
            _create_causal_mask(self.config.audio_num_codebooks, device),
        )'''

new_setup_caches = '''    def setup_caches(self, max_batch_size: int):
        dtype = next(self.parameters()).dtype
        device = next(self.parameters()).device

        try:
            self.reset_caches()
        except RuntimeError:
            pass

        with device:
            self.backbone.setup_caches(max_batch_size, dtype)
        # Initialize RoPE caches for all position embedding modules
        for module in self.backbone.modules():
            if hasattr(module, "rope_init"):
                module.rope_init()
                module.to(device=device, dtype=dtype)

        with device:
            self.decoder.setup_caches(
                max_batch_size,
                dtype,
                decoder_max_seq_len=self.config.audio_num_codebooks,
            )
        for module in self.decoder.modules():
            if hasattr(module, "rope_init"):
                module.rope_init()
                module.to(device=device, dtype=dtype)

        self.register_buffer(
            "backbone_causal_mask",
            _create_causal_mask(self.backbone.max_seq_len, device),
        )
        self.register_buffer(
            "decoder_causal_mask",
            _create_causal_mask(self.config.audio_num_codebooks, device),
        )'''

if old_setup_caches in content:
    content = content.replace(old_setup_caches, new_setup_caches)
    with open(sys.argv[1], 'w') as f:
        f.write(content)
    print("Patched setup_caches successfully")
else:
    print("Could not find original setup_caches - may already be patched or different version")
