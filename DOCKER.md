# Docker guide

> [!Note]
> This guide describes how to build and run ROCm AI applications using Docker.<br>
> During the build process, you can choose which AI application to install.

> [!Important]
> Ensure your system has Docker and Docker Compose installed.<br>
> The host system must support ROCm-capable AMD GPUs.

## Instalation:

### Applications:

During the Docker build process, you can select one of the following applications to install:

|Application|Function|
|:---|:---|
|install_comfyui|Image & video generation|
|install_text_generation_web_ui|Text generation|
|install_sillytavern|Text generation frontend|
|install_sillytavern_whisperspeech_web_ui|SillyTavern with WhisperSpeech extension|
|install_llama_cpp|Text generation|
|install_koboldcpp|Text generation|
|install_ollama|Text generation|
|install_whisperspeech_web_ui|Voice generation|
|install_ace_step|Music generation|
|install_f5_tts|Voice generation|
|install_matcha_tts|Voice generation|
|install_dia|Voice generation|
|install_chatterbox|Voice generation|
|install_kanitts|Voice generation|
|install_kanitts_vllm|Voice generation|
|install_partcrafter|3D generation|
|install_fastfetch|System information tool|

### Build Process:

1\. Edit the Dockerfile to select your desired application:
```bash
nano Dockerfile
```

2\. Edit the INSTALL_APP section in the Dockerfile to specify which application to install.

3\. Uncomment the corresponding service section in docker-compose.yml:
```bash
nano docker-compose.yml
```

4\. Build the Docker image:
```bash
docker compose build
```

> [!Important]
> Ensure proper GPU passthrough configuration in your docker-compose.yml for ROCm support.

> [!Note]
> First build may take longer depending on your internet connection and system specifications.

> [!Info]
> In the docker-compose.yml file, application services are commented out by default. To run a specific application, uncomment the corresponding service block.

Example for ComfyUI:
```yaml
# ComfyUI
comfyui:
  <<: *common-config
  ports:
    - "8188:8188"
  command: cd /AI/ComfyUI && ./run.sh
```

## Running Applications

### Starting Services:

Use the following commands to start the desired AI application:

|Service|Command|
|:---|:---|
|ComfyUI|`docker compose up comfyui -d`|
|Text Generation WebUI|`docker compose up text-generation-webui -d`|
|SillyTavern|`docker compose up sillytavern -d`|
|SillyTavern with WhisperSpeech|`docker compose up sillytavern-whisperspeech -d`|
|llama.cpp|`docker compose up llama-cpp -d`|
|KoboldCPP|`docker compose up koboldcpp -d`|
|Ollama|`docker compose up ollama -d`|
|WhisperSpeech WebUI|`docker compose up whisperspeech -d`|
|ACE-Step|`docker compose up ace-step -d`|
|F5-TTS|`docker compose up f5-tts -d`|
|Matcha-TTS|`docker compose up matcha-tts -d`|
|Dia|`docker compose up dia -d`|
|Chatterbox Multilingual|`docker compose up chatterbox -d`|
|KaniTTS|`docker compose up kanitts -d`|
|KaniTTS-vLLM|`docker compose up kanitts-vllm -d`|
|PartCrafter|`docker compose up partcrafter -d`|
|Fastfetch|`docker compose up fastfetch -d`|

> [!Note]
> The `-d` flag runs containers in detached mode (background).

## Container Management

### Basic Commands:

|Command|Description|
|:---|:---|
|`docker ps`|List running containers|
|`docker compose down`|Stop and remove containers|
|`docker compose down -v`|Remove containers and volumes|
|`docker compose logs <service-name>`|View container logs|
|`docker compose logs -f <service-name>`|Follow container logs in real-time|
|`docker compose run --rm bash`|Access interactive bash shell inside the container|