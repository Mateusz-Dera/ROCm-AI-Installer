#!/bin/bash

# Context size 
CONTEXT_SIZE=-1 # -1 AUTO

# GPU offload layers
GPU_LAYERS=-1 # -1 AUTO

# Model parameters
TEMPERATURE="0.7"
TOP_P="0.9"
TOP_K="40"
SYSTEM_PROMPT="You are a helpful AI assistant."
GGUF_PATH="./model.gguf"
MODEL_NAME="mycustommodel"

# Check if GGUF file exists
if [ ! -f "$GGUF_PATH" ]; then
    echo "Error: File $GGUF_PATH does not exist!"
    exit 1
fi

# Check if Ollama is installed
if ! command -v ollama &> /dev/null; then
    echo "Error: Ollama is not installed!"
    exit 1
fi

echo "Generating Modelfile..."

# Generate Modelfile in current directory
cat > Modelfile << EOF
FROM $GGUF_PATH

# Model parameters
PARAMETER temperature $TEMPERATURE
PARAMETER top_p $TOP_P
PARAMETER top_k $TOP_K
EOF

# Add context size if not -1
if [ "$CONTEXT_SIZE" != "-1" ]; then
    echo "PARAMETER num_ctx $CONTEXT_SIZE" >> Modelfile
fi

# Add GPU layers if not -1
if [ "$GPU_LAYERS" != "-1" ]; then
    echo "PARAMETER num_gpu $GPU_LAYERS" >> Modelfile
fi

# Add system prompt
cat >> Modelfile << EOF

# System prompt
SYSTEM "$SYSTEM_PROMPT"
EOF

echo "Modelfile has been created."

echo "Creating model '$MODEL_NAME' in Ollama..."

# Create and serve the model
if ollama create "$MODEL_NAME" -f Modelfile; then
    echo "Model '$MODEL_NAME' has been successfully created!"
    ollama serve
    sleep 2
    ollama run "$MODEL_NAME"
else
    echo "Error creating model!"
    exit 1
fi