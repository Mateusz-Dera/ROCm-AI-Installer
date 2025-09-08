#!/bin/bash
set -e

APP_NAME="$1"
AI_PATH="/opt/AI"

# Function to display help message
show_help() {
    echo "Usage: docker run <options> <image_name> [application]"
    echo ""
    echo "Available applications:"
    echo "  comfyui"
    echo "  text-generation-webui"
    echo "  sillytavern"
    echo "  llama.cpp"
    echo "  koboldcpp"
    echo "  ollama (service)"
    echo "  whisperspeech"
    echo "  cinemo"
    echo "  ovis"
    echo "  ace-step"
    echo "  f5-tts"
    echo "  matcha-tts"
    echo "  dia"
    echo "  ims-toucan"
    echo "  chatterbox"
    echo "  TripoSG"
    echo "  partcrafter"
    echo "  bash (to get an interactive shell)"
    echo ""
    echo "Example: docker run -it --rm -p 8188:8188 my-ai-image comfyui"
}

# Check if an application name is provided
if [ -z "$APP_NAME" ] || [ "$APP_NAME" == "--help" ]; then
    show_help
    exit 0
fi

# Navigate to the correct directory and execute the run script
case "$APP_NAME" in
    comfyui)
        cd "${AI_PATH}/ComfyUI" && ./run.sh
        ;;
    text-generation-webui)
        cd "${AI_PATH}/text-generation-webui" && ./run.sh
        ;;
    sillytavern)
        cd "${AI_PATH}/SillyTavern" && ./run.sh
        ;;
    llama.cpp)
        cd "${AI_PATH}/llama.cpp" && ./run.sh
        ;;
    koboldcpp)
        cd "${AI_PATH}/koboldcpp-rocm" && ./run.sh
        ;;
    ollama)
        echo "Starting Ollama service in the background..."
        sudo /usr/local/bin/ollama serve &
        echo "Ollama service started. Use 'ollama pull' or 'ollama run' in another terminal."
        # Keep the container alive
        tail -f /dev/null
        ;;
    whisperspeech)
        cd "${AI_PATH}/whisperspeech-webui" && ./run.sh
        ;;
    cinemo)
        cd "${AI_PATH}/Cinemo" && ./run.sh
        ;;
    ovis)
        cd "${AI_PATH}/Ovis-U1-3B" && ./run.sh
        ;;
    ace-step)
        cd "${AI_PATH}/ACE-Step" && ./run.sh
        ;;
    f5-tts)
        cd "${AI_PATH}/F5-TTS" && ./run.sh
        ;;
    matcha-tts)
        cd "${AI_PATH}/Matcha-TTS" && ./run.sh
        ;;
    dia)
        cd "${AI_PATH}/dia" && ./run.sh
        ;;
    ims-toucan)
        cd "${AI_PATH}/IMS-Toucan" && ./run.sh
        ;;
    chatterbox)
        cd "${AI_PATH}/Chatterbox" && ./run.sh
        ;;
    TripoSG)
        cd "${AI_PATH}/TripoSG" && ./run.sh
        ;;
    partcrafter)
        cd "${AI_PATH}/PartCrafter" && ./run.sh
        ;;
    bash)
        # Drop into an interactive shell
        exec /bin/bash
        ;;
    *)
        echo "Error: Unknown application '$APP_NAME'"
        echo ""
        show_help
        exit 1
        ;;
esac