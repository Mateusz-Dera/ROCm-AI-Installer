
Main changes:
- Docker image was changed to the official Debian image.
- Replaced PyTorch ROCm repo (https://repo.radeon.com/rocm/manylinux)
- All PyTorch-based applications now use ROCm 7.2
- Updated ROCm to 7.2.2

Added:
- HeartMuLa
- Soprano
- TabbyAPI

Removed:
- Matcha-TTS
- Dia
- KaniTTS
- Text generation web UI

Updated:
- llama.cpp
- KoboldCPP
- SillyTavern
- WhisperSpeech web UI
- F5-TTS
- ComfyUI

ComfyUI:
- Manager and ComfyUI-GGUF are installed by default
- Qwen-Image-Edit and Qwen-Image-Edit-2509 replaced by Qwen-Image-Edit-2511
- Qwen-Image replaced by  Qwen-Image-Edit-2512
- Removed Aura models