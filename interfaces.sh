#!/bin/bash

# ROCM-AI-Installer
# Copyright © 2023-2025 Mateusz Dera

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>

# FlashAttention
install_flash_attention() {
    git clone https://github.com/Dao-AILab/flash-attention
    cd flash-attention
    git checkout fd2fc9d85c8e54e5c20436465bca709bc1a6c5a1
    export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"
    python setup.py install
}

# KoboldCPP
install_koboldcpp() {
    install "https://github.com/YellowRoseCx/koboldcpp-rocm.git" "ae89be8ce4d0c0139fd8345a41bc83696537a786" "python koboldcpp.py"
    make LLAMA_HIPBLAS=1 -j4
}

# Text generation web UI
install_text_generation_web_ui() {
    install "https://github.com/oobabooga/text-generation-webui.git" "ace8afb825c80925ed21ab26dbf66b538ab06285" 'export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE" && python server.py --api --listen --extensions sd_api_pictures send_pictures gallery'

    # Additional requirements
    pip install git+https://github.com/ROCm/bitsandbytes.git@35266ead8b7669c55db26505115de941eed178de --extra-index-url https://download.pytorch.org/whl/rocm6.3
    install_flash_attention
    pip install https://github.com/turboderp/exllamav2/releases/download/v0.2.9/exllamav2-0.2.9+rocm6.3.torch2.7.0-cp312-cp312-linux_x86_64.whl
    pip install https://github.com/oobabooga/llama-cpp-binaries/releases/download/v0.9.0/llama_cpp_binaries-0.9.0+vulkan-py3-none-linux_x86_64.whl
}

# SillyTavern
install_sillytavern() {
    mkdir -p $installation_path
    cd $installation_path
    if [ -d "SillyTavern" ]
    then
        rm -rf SillyTavern
    fi
    git clone https://github.com/SillyTavern/SillyTavern.git
    cd SillyTavern
    git checkout 689637b36c178478545b46a4bec0f25ae3b97471

    mv ./start.sh ./run.sh

    # Default config
    cd ./default
    sed -i 's/listen: false/listen: true/' config.yaml
    sed -i 's/whitelistMode: true/whitelistMode: false/' config.yaml
    sed -i 's/basicAuthMode: false/basicAuthMode: true/' config.yaml
}

# llama.cpp
install_llama_cpp() {
    cd $installation_path
    if [ -d "llama.cpp" ]
    then
        rm -rf llama.cpp
    fi
    git clone https://github.com/ggerganov/llama.cpp.git
    cd llama.cpp
    git checkout 2f54e348ad2999c4e31b8777592247622b20420f
    
    HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
    cmake -S . -B build -DLLAMA_CURL=OFF -DGGML_HIP=ON -DAMDGPU_TARGETS=$GFX -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --config Release -- -j 16

    tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=$HSA_OVERRIDE_GFX_VERSION
export CUDA_VISIBLE_DEVICES=0
export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1
export TORCH_BLAS_PREFER_HIPBLASLT=0
./build/bin/llama-server -m model.gguf --host 0.0.0.0 --port 8080 --ctx-size 32768 --gpu-layers 1
EOF
    chmod +x run.sh
}

# Artist
install_artist() {
    install "https://github.com/songrise/Artist.git" "a1b3a978b2cfcbb47201259a4ab60b58173d5bf7" "python injection_main.py --mode app"
    sed -i 's/app.launch()/app.launch(share=False, server_name="0.0.0.0")/' injection_main.py
    mv ./example_config.yaml ./config.yaml
}

# Cinemo
install_cinemo() {
    install "https://huggingface.co/spaces/maxin-cn/Cinemo" "9a3fcb44aced3210e8b5e4cf164a8ad3ce3e07fd" "python demo.py"
    sed -i 's/demo.launch(debug=False, share=True)/demo.launch(debug=False, share=False, server_name="0.0.0.0")/' demo.py
}

# ComfyUI
install_comfyui() {
    install "https://github.com/comfyanonymous/ComfyUI.git" "0cf2e46b1725a5d0d6cb7b177a524026ca00f5a4" "python3 ./main.py --listen --use-split-cross-attention"

    install_flash_attention

    local gguf=0

    # Process each selected choice
    for choice in $CHOICES; do
        case $choice in
            '"0"')
                # ComfyUI-Manager
                cd $installation_path/ComfyUI/custom_nodes
                git clone https://github.com/ltdrdata/ComfyUI-Manager
                cd ComfyUI-Manager
                git checkout e16e9d7a0ef80d094a513111febe4cb8d6e38a37
                ;;
            '"1"')
                gguf=1
                ;;
            '"2"')
                # AuraSR
                cd $installation_path/ComfyUI/custom_nodes
                git clone https://github.com/alexisrolland/ComfyUI-AuraSR --recursive
                cd ComfyUI-AuraSR
                git checkout fab70362f423dc63bd0e7980eb740b0d84605be7

                cd $installation_path/ComfyUI/models/checkpoints
                huggingface-cli download fal/AuraSR-v2 model.safetensors --revision f452185a7c8b51206dd62c21c292e7baad5c3a3 --local-dir $installation_path/ComfyUI/models/checkpoints
                mv ./model.safetensors ./aura_sr_v2.safetensors
                huggingface-cli download fal/AuraSR model.safetensors --revision 87da2f52b29b6351391f71c74de581c393fc19f5 --local-dir $installation_path/ComfyUI/models/checkpoints
                mv ./model.safetensors ./aura_sr.safetensors

                pip install aura-sr==0.0.4
                ;;
            '"3"')
                # AuraFlow
                huggingface-cli download fal/AuraFlow-v0.3 aura_flow_0.3.safetensors --revision 2cd8588f04c886002be4571697d84654a50e3af3 --local-dir $installation_path/ComfyUI/models/checkpoints
                ;;
            '"4"')
                gguf=1
                # Flux
                huggingface-cli download city96/FLUX.1-schnell-gguf flux1-schnell-Q8_0.gguf --revision f495746ed9c5efcf4661f53ef05401dceadc17d2 --local-dir $installation_path/ComfyUI/models/unet
                ;;
            '"5"')
                gguf=1
                # AnimePro FLUX
                huggingface-cli download advokat/AnimePro-FLUX animepro-Q5_K_M.gguf --revision be1cbbe8280e6d038836df868c79cdf7687ad39d --local-dir $installation_path/ComfyUI/models/unet
                ;;
            '"6"')
                gguf=1
                # AnimePro FLUX
                huggingface-cli download hum-ma/Flex.1-alpha-GGUF Flex.1-alpha-Q8_0.gguf --revision 2ccb9cb781dfbafdf707e21b915c654c4fa6a07d --local-dir $installation_path/ComfyUI/models/unet
                ;;
            "")
                break
                ;;
            *)
                echo "Unknown option: $choice"
                ;;
        esac
    done

    if [ $gguf -eq 1 ]; then
        cd $installation_path/ComfyUI/custom_nodes
        git clone https://github.com/city96/ComfyUI-GGUF
        cd ComfyUI-GGUF
        git checkout a2b75978fd50c0227a58316619b79d525b88e570
        
        cd $installation_path/ComfyUI/models/text_encoders
        huggingface-cli download city96/t5-v1_1-xxl-encoder-bf16 model.safetensors --revision 1b9c856aadb864af93c1dcdc226c2774fa67bc86 --local-dir $installation_path/ComfyUI/models/text_encoders
        mv ./model.safetensors ./t5-v1_1-xxl-encoder-bf16.safetensors
        huggingface-cli download openai/clip-vit-large-patch14 model.safetensors --revision 32bd64288804d66eefd0ccbe215aa642df71cc41 --local-dir $installation_path/ComfyUI/models/text_encoders
        mv ./model.safetensors ./clip-vit-large-patch14.safetensors
        
        huggingface

        cd $installation_path/ComfyUI/models/vae
        huggingface-cli download black-forest-labs/FLUX.1-schnell vae/diffusion_pytorch_model.safetensors --revision 741f7c3ce8b383c54771c7003378a50191e9efe9 --local-dir $installation_path/ComfyUI/models/vae
    fi
}

# ACE-Step
install_ace_step() {
    install "https://github.com/ace-step/ACE-Step" "9bf891fb2880383cc845309c3a2dd9a46e1942d6" "python app.py --server_name 0.0.0.0"
}

# WhisperSpeech web UI
install_whisperspeech_web_ui(){
    install "https://github.com/Mateusz-Dera/whisperspeech-webui.git" "d4628117816293d8a068cb1dd653359540f0aa15" "python3 webui.py --listen"
    pip install -r requirements_rocm_6.3.txt
}

# F5-TTS
install_f5_tts(){
    install "https://github.com/SWivid/F5-TTS.git" "c47687487c34dbff1d9c58ad420e705bd046b283" "f5-tts_infer-gradio --host 0.0.0.0"
    git submodule update --init --recursive
    pip install -e . --extra-index-url https://download.pytorch.org/whl/rocm6.3
}

# Matcha-TTS
install_matcha_tts(){
    install "https://github.com/shivammehta25/Matcha-TTS" "108906c603fad5055f2649b3fd71d2bbdf222eac" "matcha-tts-app"
    cd ./matcha
    sed -i 's/demo\.queue().launch(share=True)/demo.queue().launch(server_name="0.0.0.0")/' "app.py"
    cd $installation_path/Matcha-TTS
    sed -i 's/cython==0.29.35/cython/' "pyproject.toml"
    sed -i 's/numpy==1.24.3/numpy/' "pyproject.toml"
    rm requirements.txt
    touch requirements.txt
    pip install -e .
}

# Dia
install_dia(){
    install "https://github.com/tralamazza/dia.git" "8da0c755661e3cb71dc81583400012be6c3f62be" "MIOPEN_FIND_MODE=FAST uv run --extra rocm app.py"
    pip install uv==0.6.16
    sed -i 's/demo.launch(share=args.share)/demo.launch(share=args.share,server_name="0.0.0.0")/' "app.py"
}

# Orpheus-TTS
install_orpheus_tts(){
    install "https://huggingface.co/spaces/MohamedRashad/Orpheus-TTS" "e45257580188c1f3232781a9ec98089303c2be22" 'export HIP_VISIBLE_DEVICES=0 && export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE" && python3 app.py'

    install_flash_attention

    cp -r /opt/rocm/share/amd_smi ./
    cd ./amd_smi
    pip install -e . --extra-index-url https://download.pytorch.org/whl/rocm6.3

    git clone https://github.com/vllm-project/vllm.git
    cd ./vllm
    git checkout ed6e9075d31e32c8548b480a47d1ffb77da1f54c
    export PYTORCH_ROCM_ARCH="gfx1100"
    export VLLM_TARGET_DEVICE="rocm"
    export VLLM_USE_TRITON_FLASH_ATTN=0
    pip install  --no-build-isolation --verbose .

    pip install orpheus-speech==0.1.0 --no-deps

    cd $installation_path/Orpheus-TTS
    sed -i 's/demo.queue().launch(share=False, ssr_mode=False)/demo.queue().launch(share=False, ssr_mode=False, server_name="0.0.0.0")/' "app.py"
}

# IMS-Toucan
install_ims_toucan(){
    install "https://github.com/DigitalPhonetics/IMS-Toucan.git" "bbda44ed1314eedba2d739b69660cb93b14eebd3" "python3 run_simple_GUI_demo.py"
    # self.iface.launch()
    sed -i 's/self.iface.launch()/self.iface.launch(share=False, server_name="0.0.0.0")/' "run_simple_GUI_demo.py"
}


# TripoSG
install_triposg(){
    install "https://github.com/VAST-AI-Research/TripoSG" "88cfe7101001ad6eefdb6c459c7034f1ceb70d72" "python app.py"
    tee --append app.py << EOF
import gradio as gr
import subprocess
import os
import glob
import trimesh
import shutil

def run_triposg(image_input, output_format):
    """Runs the TripoSR model with the given image input and converts to selected format."""
    try:
        # Create a temporary directory for output files
        output_dir = "temp_output"
        os.makedirs(output_dir, exist_ok=True)
        
        # Create public directory for serving files
        public_dir = "public"
        os.makedirs(public_dir, exist_ok=True)

        # Construct the command
        command = [
            "python",
            "-m",
            "scripts.inference_triposg",
            "--image-input",
            image_input,
            "--output-dir",
            output_dir,
        ]

        # Execute the command and capture the output
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, stderr = process.communicate()

        # Check for errors
        if process.returncode != 0:
            return f"Error: {stderr.decode()}"

        # Find the GLB file in the output directory
        glb_files = [f for f in os.listdir(output_dir) if f.endswith(".glb")]
        if not glb_files:
            return "No .glb file generated."

        glb_file_path = os.path.join(output_dir, glb_files[0])
        base_name = os.path.splitext(glb_files[0])[0]
        
        # Load the mesh
        mesh = trimesh.load(glb_file_path)
        
        # Convert to the selected format
        if output_format == "glb":
            output_file = os.path.join(public_dir, f"{base_name}.glb")
            shutil.copy(glb_file_path, output_file)
        elif output_format == "stl":
            output_file = os.path.join(public_dir, f"{base_name}.stl")
            mesh.export(output_file)
        elif output_format == "obj":
            output_file = os.path.join(public_dir, f"{base_name}.obj")
            mesh.export(output_file)
        else:
            return "Invalid output format selected."
        
        # Return the path for display
        return output_file

    except Exception as e:
        return f"An error occurred: {str(e)}"

# Get example images
example_dir = "assets/example_data/"
example_images = glob.glob(os.path.join(example_dir, "*.png"))

# Create a custom Gradio interface with 3D model display
with gr.Blocks(title="TripoSR for ROCm") as iface:
    gr.Markdown("# TripoSR Inference for ROCm")
    gr.Markdown("Upload an image and generate a 3D model using TripoSR (Without textures). Choose your preferred output format.")
    gr.Markdown("https://github.com/VAST-AI-Research/TripoSG<br>https://github.com/Mateusz-Dera/ROCm-AI-Installer")    
    
    with gr.Row():
        with gr.Column(scale=1):
            input_image = gr.Image(type="filepath", label="Input Image")
            output_format = gr.Radio(
                choices=["glb", "stl", "obj"], 
                value="glb", 
                label="Output Format",
                info="Select the format for your 3D model"
            )
            submit_btn = gr.Button("Generate 3D Model")

        with gr.Column(scale=1):
            model_output = gr.Model3D(label="3D Model Output")
    
    # Example images
    gr.Examples(
        examples=example_images,
        inputs=input_image
    )
    
    # Set up the event handling for generating the model
    submit_btn.click(
        fn=run_triposg, 
        inputs=[input_image, output_format], 
        outputs=model_output
    )

if __name__ == "__main__":
    iface.launch(share=False, server_name="0.0.0.0", allowed_paths=["public"])
EOF
}

# Login to HuggingFace
huggingface() {
    read -sp "Enter your Hugging Face access token: " HF_TOKEN
        
    if [ -z "$HF_TOKEN" ]; then
        echo -e "\nError: No token provided. Exiting."
        exit 1
    fi
        
    # Login to Hugging Face
    echo -e "\nLogging into Hugging Face..."
    huggingface-cli login --token "$HF_TOKEN"

    # Check login status
    if [ $? -eq 0 ]; then
        echo "Successfully logged into Hugging Face!"
    else
        echo "Login failed. Please check your token and try again."
        exit 1
    fi
}

# Install fastfetch
install_fastfetch(){
    # Install fastfetch
    if ! command -v fastfetch &> /dev/null; then
        sudo apt update
        sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch
        sudo apt update
        sudo apt -y install fastfetch
    fi

    if command -v gsettings &> /dev/null; then
        gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:b1dcc9dd-5262-4d8d-a863-c897e6d979b9/ default-size-columns 100
    fi

    # Add fastfetch to shell

    # Detect shell configuration file
    detect_shell_config() {
        if [ -n "$SHELL" ]; then
            case "$SHELL" in
                */zsh)
                    echo "$HOME/.zshrc"
                    ;;
                */bash)
                    echo "$HOME/.bashrc"
                    ;;
                */fish)
                    echo "$HOME/.config/fish/config.fish"
                    ;;
                *)
                    echo ""
                    ;;
            esac
        else
            echo ""
        fi
    }

    fastfetch_LINE="echo && fastfetch && echo"
    CONFIG_FILE=$(detect_shell_config)

    if [ -z "$CONFIG_FILE" ]; then
        echo "Could not detect shell configuration file"
        exit 1
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Creating $CONFIG_FILE"
        touch "$CONFIG_FILE"
    fi

    if ! grep -Fxq "$fastfetch_LINE" "$CONFIG_FILE"; then
        echo "$fastfetch_LINE" >> "$CONFIG_FILE"
        echo "Fastfetch line added to $CONFIG_FILE"
    else
        echo "fastfetch line already exists in $CONFIG_FILE"
    fi

    if [ -d "$HOME/.config/fastfetch" ]; then
        echo "Fastfetch config already exists"
    else
        mkdir -p "$HOME/.config/fastfetch"
        echo "Fastfetch config created"
    fi

    if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
        rm "$HOME/.config/fastfetch/config.jsonc"
    fi

    # Create the base config with placeholders for dynamic GPU VRAM modules
    tee "$HOME/.config/fastfetch/config.jsonc" << 'EOF'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "type": "none",
    "padding": {
    "top": 2
    },
  },
  "modules": [
    "title",
    "break",
    "os",
    "localip",
    "host",
    "kernel",
    "uptime",
    "packages",
    "shell",
    "break",
    "disk",
    "break",
    {
      "type": "cpu",
      "key": "CPU",
      "showPeCoreCount": true,
      "temp": true,
      "format": "{name} ({core-types}) {freq-max}"
    },
    {
      "type": "memory",
      "key": "RAM",
      "format": "{used} / {total})"
    },
    {
      "type": "swap",
      "key": "SWAP",
      "format": "{used} / {total}"
    },
    "gpu",
    __GPU_VRAM_MODULES__
  ]
}
EOF

    if [ -f "/usr/bin/get-gpu-vram" ]; then
        sudo rm "/usr/bin/get-gpu-vram"
    fi

    sudo tee "/usr/bin/get-gpu-vram" << 'EOF'
#!/bin/bash

# Function to count AMD GPUs
count_amd_gpus() {
    lspci | grep -i "VGA" | grep -i "AMD" | wc -l
}

# Function to count NVIDIA GPUs
count_nvidia_gpus() {
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi --query-gpu=count --format=csv,noheader
    else
        echo 0
    fi
}

# Check for required tools
has_rocm_smi=false
has_nvidia_smi=false

if command -v rocm-smi &> /dev/null; then
    has_rocm_smi=true
fi

if command -v nvidia-smi &> /dev/null; then
    has_nvidia_smi=true
fi

# Count GPUs
amd_count=$(count_amd_gpus)
nvidia_count=$(count_nvidia_gpus)

# echo "Found $amd_count AMD GPU(s) and $nvidia_count NVIDIA GPU(s)"

# Check if any GPUs are found
if [ "$amd_count" -le 0 ] && [ "$nvidia_count" -le 0 ]; then
    exit 0
fi

# Process AMD GPUs if found
if [ "$amd_count" -gt 0 ]; then
    if $has_rocm_smi; then
        # echo "=== AMD GPU Memory Usage ==="
        # Loop through each AMD GPU index
        for ((gpu=0; gpu<amd_count; gpu++)); do
            used_mem_bytes=$(rocm-smi --showmeminfo vram -d $gpu | grep 'Used Memory' | awk '{print $NF}')
            total_mem_bytes=$(rocm-smi --showmeminfo vram -d $gpu | grep 'Total Memory' | awk '{print $NF}')
            used_mem_mb=$(echo "$used_mem_bytes / 1048576" | bc)
            total_mem_mb=$(echo "$total_mem_bytes / 1048576" | bc)
            echo "$used_mem_mb/$total_mem_mb MB"
        done
    else
        echo "rocm-smi not found. Skipping AMD GPU memory info."
    fi
fi

# Process NVIDIA GPUs if found
if [ "$nvidia_count" -gt 0 ]; then
    if $has_nvidia_smi; then
        # echo "=== NVIDIA GPU Memory Usage ==="
        # Get memory usage for all NVIDIA GPUs
        nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader,nounits | while read -r line; do
            index=$(echo "$line" | awk -F ', ' '{print $1}')
            used=$(echo "$line" | awk -F ', ' '{print $2}')
            total=$(echo "$line" | awk -F ', ' '{print $3}')
            echo "$used/$total MB"
        done
    else
        echo "nvidia-smi not found. Skipping NVIDIA GPU memory info."
    fi
fi
EOF

    sudo chmod +x /usr/bin/get-gpu-vram

    if [ -f "/usr/bin/dynamic-gpu-vram" ]; then
        sudo rm "/usr/bin/dynamic-gpu-vram"
    fi

    sudo tee "/usr/bin/dynamic-gpu-vram" << 'EOF'
#!/bin/bash

# Run the get-gpu-vram command and capture output
output=$(get-gpu-vram)

# Exit if no output
if [ -z "$output" ]; then
    echo ""
    exit 0
fi

# Initialize JSON modules array
modules=""
i=1

# Process each line of output
while IFS= read -r line; do
    # Create a JSON module for this GPU
    if [ -n "$modules" ]; then
        modules="${modules},"
    fi
    modules="${modules}{\"type\": \"command\", \"text\": \"echo '$line'\", \"key\": \"GPU ${i} VRAM\"}"
    ((i++))
done <<< "$output"

# Output the JSON
echo "$modules"
EOF

    sudo chmod +x /usr/bin/dynamic-gpu-vram

    # Now, update the config.jsonc with the dynamic GPU VRAM modules
    # First, get the dynamic modules
    gpu_modules=$(dynamic-gpu-vram)
    
    # Replace the placeholder with the actual modules or empty if no GPUs found
    if [ -n "$gpu_modules" ]; then
        sed -i "s|__GPU_VRAM_MODULES__|$gpu_modules,|" "$HOME/.config/fastfetch/config.jsonc"
    else
        sed -i "s|__GPU_VRAM_MODULES__||" "$HOME/.config/fastfetch/config.jsonc"
    fi

    echo "New Fastfetch config created with dynamic GPU VRAM modules"
}