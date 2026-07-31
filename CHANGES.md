Added:
    - Krea-2-Turbo
    - trellis2.c (ROCm/HIP and Vulkan variants)
    - Pixal3D Experimental (Pixal3D image-to-3D via trellis2.c ROCm; custom OOM patch to fit 24 GB)
    - AutoRemesher (non-AI quad-remeshing helper for retopologizing 3D-generation outputs)
    - ARDY (NVIDIA autoregressive-diffusion motion generation, viser demo)
    - Fine-tuning category with Unsloth (LoRA/QLoRA fine-tuning + Unsloth Studio, ROCm)
    - vLLM Gemma 4 (Gemma 4 31B on an OpenAI-compatible API, quantized to 4-bit W4A16 during
      install, with a compressed KV cache: 150k tokens in one session or two concurrent
      sessions of 150k, against 111k on plain fp8)

Updated:
    - Installer now warns that changing any variable requires recreating the container
    - Automatic tests read build variables from the running container instead of the host .env
    - llama.cpp / llama.cpp Vulkan / turboquant now run in router mode (pick/switch models from the WebUI)

Removed:
    - TRELLIS.2_rocm (superseded by the trellis2.c implementation)
    - Kimodo (superseded by ARDY, the newer real-time autoregressive motion model from the same lab)
    - KoboldCPP
