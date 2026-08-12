Added:
    - Krea-2-Turbo
    - trellis.cpp, ROCm and Vulkan (TRELLIS.2-4B image-to-3D in C++/GGML with no Python at
      runtime, served over HTTP on port 8081; prebuilt GGUF weights, q8 by default).
      The card chosen at install time is enforced by hiding the others from the backend:
      left alone the engine takes whichever device reports the most memory, which on a
      machine with an integrated GPU is the integrated one - it reports shared system RAM
      and then runs an image-to-3D pass 20x slower than the discrete card
    - AutoRemesher (non-AI quad-remeshing helper for retopologizing 3D-generation outputs)
    - ARDY (NVIDIA autoregressive-diffusion motion generation, viser demo)
    - Fine-tuning category with Unsloth (LoRA/QLoRA fine-tuning + Unsloth Studio, ROCm)
    - vLLM Gemma 4 (Gemma 4 31B on an OpenAI-compatible API, quantized to 4-bit W4A16 during
      install, with a compressed KV cache: 150k tokens in one session or two concurrent
      sessions of 150k, against 111k on plain fp8)
    - llama.cpp TurboQuant, ROCm and Vulkan (TheTom/llama-cpp-turboquant: the turbo2/turbo3/turbo4
      KV-cache types as real GGML types; both builds run turbo3, the only level the Vulkan
      backend implements, at Gemma 4's full 262144 context)
    - GPU detection: architectures are read from the kernel's KFD topology and preselected,
      and packages are installed for every selected one
    - Each application asks which card to use while it is being installed; the answer is written
      into that application's own run.sh
    - Krea 2: Outpaint tab (yijunwang2/krea2-outpaint), extending an image into a larger canvas
      with the source pixels kept exactly and only the new area generated

Updated:
    - Installer now warns that changing any variable requires recreating the container
    - Automatic tests read build variables from the running container instead of the host .env
    - Both llama.cpp TurboQuant builds run in router mode (pick/switch models from the WebUI)
    - ROCm 7.14 from repo.amd.com, with per-architecture packages instead of one build for
      every GPU AMD ships. Ubuntu 26.04 packages, so the libxml2.so.2 compatibility symlink is gone
    - Python 3.14 is the default for every application (was 3.13), and torch comes from AMD's
      multi-architecture wheel stream: torch 2.12.0+rocm7.14.0, torchvision 0.27.0, torchaudio
      2.11.0, triton 3.7.1. The kernels sit in separate amd-torch-device-<gfx> wheels, installed
      for the architectures selected at container creation, so a freeze file no longer ties an
      installation to one card
    - vLLM Gemma 4 now quantizes the QAT release instead of the plain checkpoint (28-50% better
      perplexity at the same scheme, size and speed), shares K/V with 4-bit values, and enables
      tool calling and reasoning
    - HSA_OVERRIDE_GFX_VERSION removed from the Variables menu: per-architecture ROCm packages
      made it unnecessary, and on a machine with more than one GPU it relabels the others too,
      which can stop ROCm finding any device. Still honoured if added to .env by hand
    - OmniVoice: three source patches that no longer matched the pinned commit removed - the
      version installed loads the audio tokenizer on CPU by itself. Voice cloning in the
      automatic test was missing the Instruct field the same commit added
    - Krea 2: the weights became a gated HuggingFace repository, which needs the licence
      accepted on the model page before the token works. The UI notice now also carries the
      AI-disclosure and commercial-use terms (sections 4.3 and 2.3) beside the existing
      attribution and content-filter ones
    - The demo chat UI asks the server for the model name instead of assuming it
    - Diagnostic scripts take --model or TQ_MODEL instead of a hardcoded container path

Removed:
    - TRELLIS.2_rocm and trellis2.c, with the Pixal3D Experimental variant built on it
      (all superseded by trellis.cpp)
    - Kimodo (superseded by ARDY, the newer real-time autoregressive motion model from the same lab)
    - KoboldCPP
    - llama.cpp, llama.cpp Vulkan and turboquant-rocm-llamacpp (all three superseded by the two
      llama.cpp TurboQuant builds)
    - Container-wide GPU pinning (HIP_VISIBLE_DEVICES, GPU_DEVICE_ORDINAL), which hid every card
      but the first from every application
    - ComfyUI addons Qwen-Image-2512-GGUF and Qwen-Image-2511-Edit-GGUF, with their workflows
      and tests (Krea 2 covers both generation and editing with better results)
