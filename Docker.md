# Docker Guide
## 📝 Interactive Installation

During the build process, you can choose which AI application to install into the dockerfile Plaintext. The Dockerfile includes an interactive menu installer. To use it, you need to set the `INSTALL_APP` argument when building the image.

```bash
# Edit the INSTALL_APP section from the dockerfile
nano Dockerfile
# Uncomment the Selected APP section from the docker-compose.yml
nano docker-compose.yml
# Build the Base Image
docker compose build
```

This will install your selected app during the build process. You can replace the installation option with any of the available options in the Dockerfile:

- install_comfyui
- install_text_generation_web_ui
- install_sillytavern
- install_sillytavern_whisperspeech_web_ui
- install_llama_cpp
- install_koboldcpp
- install_ollama
- install_whisperspeech_web_ui
- install_ace_step
- install_f5_tts
- install_matcha_tts
- install_dia
- install_chatterbox
- install_kanitts
- install_kanitts_vllm
- install_partcrafter
- install_fastfetch

## 📝 Uncomment the Service Selected

In the `docker-compose.yml` file, the app services are commented out by default. To run a specific app service, you need to uncomment the corresponding service. For example, to run ComfyUI, you would uncomment the following lines:

```yaml
# ComfyUI
comfyui:
  <<: *common-config
  ports:
    - "8188:8188"
  command: cd /AI/ComfyUI && ./run.sh
```

After uncommenting the desired service, you can start it using the `docker compose up` command followed by the service name.

## ✨ 3. Run the Applications

The Docker container provides various AI applications that you can run. To start any of these applications, you can use the `docker compose up` command followed by the name of the application.

### Available Services

Here is a list of available AI applications:

```bash
# Run ComfyUI in the foreground
docker compose up comfyui -d

# Run Text Generation WebUI in the foreground
docker compose up text-generation-webui -d

# Run SillyTavern in the foreground
docker compose up sillytavern -d

# Run SillyTavern in the foreground
docker compose up sillytavern-whisperspeech -d

# Run llama.cpp in the foreground
docker compose up llama-cpp -d

# Run Kobold.cpp in the foreground
docker compose up koboldcpp -d

# Run Ollama in the foreground
docker compose up ollama -d

# Run WhisperSpeech WebUI in the foreground
docker compose up whisperspeech -d

# Run ACE-Step in the foreground
docker compose up ace-step -d

# Run F5-TTS in the foreground
docker compose up f5-tts -d

# Run Matcha-TTS in the foreground
docker compose up matcha-tts -d

# Run Dia in the foreground
docker compose up dia -d

# Run Chatterbox Multilingual in the foreground
docker compose up chatterbox -d

# Run KaniTTS in the foreground
docker compose up kanitts -d

# Run KaniTTS-vLLM in the foreground
docker compose up kanitts-vllm -d

# Run PartCrafter in the foreground
docker compose up partcrafter -d

# Run fastfetch in the foreground
docker compose up fastfetch -d
```

You can run any of these services in detached mode by adding the `-d` flag to the `docker compose up` command.

## 🛠️ 4. Container Management

Here are some useful commands for managing your Docker containers:

* **List running containers:**
  ```bash
  docker ps
  ```

* **Stop and remove containers:**
  ```bash
  docker compose down
  ```

* **Remove Docker volumes (optional):**
  ```bash
  docker compose down -v
  ```

* **Access container logs:**
  ```bash
  docker compose logs <service-name>
  ```

* **Follow container logs in real-time:**
  ```bash
  docker compose logs -f <service-name>
  ```

## 📝 Customization and Adjustments

Please note that this is a basic implementation, and you might need to make further adjustments based on your specific requirements. Ensure that you handle any potential errors or edge cases that might arise during the interactive installation and service selection processes.

Feel free to explore and customize the Docker setup to fit your needs!

### Access the Shell

To get an interactive `bash` shell inside the running `rocm` container, use the following command:

```bash
docker compose run --rm bash
```

This will give you a terminal inside the container, allowing you to run commands and interact with the installed applications.