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
    git checkout 7661781d001e0900121c000a0aaf21b3f94337d6
    export PYTORCH_ROCM_ARCH=$GFX
    export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"
    python3 setup.py install
    cd ..
}

# KoboldCPP
install_koboldcpp() {
    install "https://github.com/YellowRoseCx/koboldcpp-rocm.git" "7ae1d4621b81628cf4d290ec5283492c0b475e6a" "python koboldcpp.py"
    make LLAMA_HIPBLAS=1 -j4
}

# Text generation web UI
install_text_generation_web_ui() {
    install "https://github.com/oobabooga/text-generation-webui.git" "b7d59829448870a0acd6aaef48917703c70cb3fa" 'python server.py --api --listen --extensions sd_api_pictures send_pictures gallery'

    # Additional requirements
    pip install git+https://github.com/ROCm/bitsandbytes.git@48a551fd80995c3733ea65bb475d67cd40a6df31 --extra-index-url https://download.pytorch.org/whl/rocm6.3
    install_flash_attention
    pip install https://github.com/turboderp-org/exllamav2/releases/download/v0.3.1/exllamav2-0.3.1+rocm6.3.torch2.7.0-cp312-cp312-linux_x86_64.whl
    pip install https://github.com/oobabooga/llama-cpp-binaries/releases/download/v0.24.0/llama_cpp_binaries-0.24.0+vulkan-py3-none-linux_x86_64.whl
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
    git checkout 31e7c653977cb11cb634d31339b6484a44bc6299

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
    git checkout 17a1f0d2d407040ee242e18dd79be8bb212cfcef
    
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
    install "https://github.com/songrise/Artist.git" "d244220702d4e7800b68f148d84cf95dd88ec8f0" "python injection_main.py --mode app"
    sed -i 's/app.launch()/app.launch(share=False, server_name="0.0.0.0")/' injection_main.py
    mv ./example_config.yaml ./config.yaml
}

# Cinemo
install_cinemo() {
    install "https://huggingface.co/spaces/maxin-cn/Cinemo" "9a3fcb44aced3210e8b5e4cf164a8ad3ce3e07fd" "python demo.py"
    sed -i 's/demo.launch(debug=False, share=True)/demo.launch(debug=False, share=False, server_name="0.0.0.0")/' demo.py
}

# Ovis-U1
install_ovis() {
    install "https://huggingface.co/spaces/AIDC-AI/Ovis-U1-3B" "cbc005ddff7376a20bc98a89136d088e0f7e1623" "python3 app.py"
    sed -i 's/demo.launch(share=True, ssr_mode=False)/demo.launch(share=False, ssr_mode=False, server_name="0.0.0.0")/' "app.py"
    sed -i "/subprocess\.run('pip install flash-attn==2\.6\.3 --no-build-isolation', env={'FLASH_ATTENTION_SKIP_CUDA_BUILD': \"TRUE\"}, shell=True)/d" app.py
    install_flash_attention
}

# ComfyUI
install_comfyui() {
    install "https://github.com/comfyanonymous/ComfyUI.git" "5612670ee48ce500aab98e362b3372ab06d1d659" "python3 ./main.py --listen --use-split-cross-attention"

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
                git checkout 546db08ec4deadc2fec4451c50493cffff20dfcd
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
        git checkout b3ec875a68d94b758914fd48d30571d953bb7a54
        
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
        install_flash_attention
}

# WhisperSpeech web UI
install_whisperspeech_web_ui(){
    uv_install "https://github.com/Mateusz-Dera/whisperspeech-webui.git" "dcccc05b91209085f04265aa2120691161c16da6" "uv run --extra rocm webui.py --listen"
}

# F5-TTS
install_f5_tts(){
    install "https://github.com/SWivid/F5-TTS.git" "a275798a2fba6accbb4730cc5530bdaabd3a5efd" "f5-tts_infer-gradio --host 0.0.0.0"
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
    install "https://huggingface.co/spaces/MohamedRashad/Orpheus-TTS" "e45257580188c1f3232781a9ec98089303c2be22" "python3 app.py"

    install_flash_attention

    cp -r /opt/rocm/share/amd_smi ./
    cd ./amd_smi
    pip install -e . --extra-index-url https://download.pytorch.org/whl/rocm6.3

    git clone https://github.com/vllm-project/vllm.git
    cd ./vllm
    git checkout ed6e9075d31e32c8548b480a47d1ffb77da1f54c
    export PYTORCH_ROCM_ARCH=$GFX
    export VLLM_TARGET_DEVICE="rocm"
    export VLLM_USE_TRITON_FLASH_ATTN=0
    pip install  --no-build-isolation --verbose .

    pip install orpheus-speech==0.1.0 --no-deps

    cd $installation_path/Orpheus-TTS
    sed -i 's/demo.queue().launch(share=False, ssr_mode=False)/demo.queue().launch(share=False, ssr_mode=False, server_name="0.0.0.0")/' "app.py"
}

# IMS-Toucan
install_ims_toucan(){
    install "https://github.com/DigitalPhonetics/IMS-Toucan.git" "dab8fe99199e707f869a219e836b69e53f13c528" "python3 run_simple_GUI_demo.py"
    # self.iface.launch()
    sed -i 's/self.iface.launch()/self.iface.launch(share=False, server_name="0.0.0.0")/' "run_simple_GUI_demo.py"
}

# Chatterbox
install_chatterbox(){
    install "https://huggingface.co/spaces/ResembleAI/Chatterbox" "eb90621fa748f341a5b768aed0c0c12fc561894b" "python app.py"
        sed -i 's/demo.launch(mcp_server=True)/demo.launch(server_name="0.0.0.0")/' "app.py"
}

# HierSpeech++
install_hierspeech(){
    install "http://huggingface.co/spaces/LeeSangHoon/HierSpeech_TTS" "365f5cfe0da9e7b3589ca6650c35d38df6d979f5" "python app.py"
    sed -i 's/demo_play.launch()/demo_play.launch(server_name="0.0.0.0")/' "app.py"
}

# TripoSG
install_triposg(){
    install "https://github.com/VAST-AI-Research/TripoSG" "88cfe7101001ad6eefdb6c459c7034f1ceb70d72" "python app.py"
    pip install torch_cluster==1.6.3 --no-build-isolation --extra-index-url https://download.pytorch.org/whl/rocm6.3
    tee --append app.py << EOF
import gradio as gr
import subprocess
import os
import glob
import trimesh
import shutil
import threading
import time
from queue import Queue

def run_triposg(image_input, output_format, progress=gr.Progress()):
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

        progress(0.1, desc="Starting TripoSR inference...")

        # Execute the command with real-time output
        process = subprocess.Popen(
            command, 
            stdout=subprocess.PIPE, 
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=1
        )

        # Monitor process output in real-time
        output_lines = []
        while True:
            output = process.stdout.readline()
            if output == '' and process.poll() is not None:
                break
            if output:
                output_lines.append(output.strip())
                print(output.strip())  # Print to console for debugging
                
                # Update progress based on output keywords
                if "Loading model" in output:
                    progress(0.2, desc="Loading TripoSR model...")
                elif "Processing image" in output:
                    progress(0.4, desc="Processing input image...")
                elif "Generating mesh" in output:
                    progress(0.6, desc="Generating 3D mesh...")
                elif "Saving" in output:
                    progress(0.8, desc="Saving 3D model...")

        # Wait for process to complete
        return_code = process.poll()
        
        # Check for errors
        if return_code != 0:
            error_msg = '\n'.join(output_lines[-10:])  # Show last 10 lines
            return f"Error (code {return_code}): {error_msg}"

        progress(0.9, desc="Converting output format...")

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
        
        progress(1.0, desc="3D model generation complete!")
        
        # Return the path for display
        return output_file

    except Exception as e:
        return f"An error occurred: {str(e)}"

def run_triposg_with_status(image_input, output_format):
    """Wrapper function that provides status updates during processing."""
    if not image_input:
        return None, "Please upload an image first."
    
    # Create a status message
    status_msg = "🔄 Processing... This may take a few minutes."
    
    # Run the actual processing
    result = run_triposg(image_input, output_format)
    
    if isinstance(result, str) and result.startswith("Error"):
        return None, result
    elif isinstance(result, str) and result.startswith("No .glb"):
        return None, result
    else:
        return result, "✅ 3D model generated successfully!"

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
            submit_btn = gr.Button("Generate 3D Model", variant="primary")
            
            # Add status display
            status_text = gr.Textbox(
                label="Status", 
                interactive=False,
                placeholder="Ready to generate 3D model..."
            )

        with gr.Column(scale=1):
            model_output = gr.Model3D(label="3D Model Output")
    
    # Example images
    if example_images:
        gr.Examples(
            examples=example_images,
            inputs=input_image
        )
    
    # Set up the event handling for generating the model
    submit_btn.click(
        fn=run_triposg_with_status, 
        inputs=[input_image, output_format], 
        outputs=[model_output, status_text],
        show_progress=True
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
                    sed '/fastfetch/d' "$HOME/.zshrc" > "$HOME/.zshrc.tmp" && mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
                    ;;
                */bash)
                    echo "$HOME/.bashrc"
                    sed '/fastfetch/d' "$HOME/.bashrc" > "$HOME/.bashrc.tmp" && mv "$HOME/.bashrc.tmp" "$HOME/.bashrc"
                    ;;
                */fish)
                    echo "$HOME/.config/fish/config.fish"
                    sed '/fastfetch/d' "$HOME/.config/fish/config.fish" > "$HOME/.config/fish/config.fish.tmp" && mv "$HOME/.config/fish/config.fish.tmp" "$HOME/.config/fish/config.fish"
                    ;;
                *)
                    echo ""
                    ;;
            esac
        else
            echo ""
        fi
    }

    fastfetch_LINE="alias fastfetch='dynamic-fastfetch'"
    CONFIG_FILE=$(detect_shell_config)

    if [ -z "$CONFIG_FILE" ]; then
        echo "Could not detect shell configuration file"
        exit 1
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Creating $CONFIG_FILE"
        touch "$CONFIG_FILE"
    fi

    if [ -f "/usr/bin/dynamic-fastfetch" ]; then
        sudo rm "/usr/bin/dynamic-fastfetch"
    fi

    sudo tee "/usr/bin/dynamic-fastfetch" << 'EOF'
#!/bin/bash
# Dynamic fastfetch wrapper that ensures VRAM information is always up-to-date

# Generate temporary config file with current GPU VRAM info
TMP_CONFIG="$HOME/.config/fastfetch/tmp_config.jsonc"
BASE_CONFIG="$HOME/.config/fastfetch/base_config.jsonc"

# Copy base config to temp
cp "$BASE_CONFIG" "$TMP_CONFIG"

# Get dynamic GPU modules
gpu_modules=$(dynamic-gpu-vram)

# Insert GPU modules into temp config
if [ -n "$gpu_modules" ]; then
    # Replace placeholder with actual modules
    sed -i "s|__GPU_VRAM_MODULES__|$gpu_modules,|" "$TMP_CONFIG"
else
    # Remove placeholder if no GPU data
    sed -i "s|__GPU_VRAM_MODULES__||" "$TMP_CONFIG"
fi

# Run fastfetch with the temporary config
echo
/usr/bin/fastfetch --config "$TMP_CONFIG"
echo

# Clean up temp file
rm "$TMP_CONFIG"
EOF

    sudo chmod +x /usr/bin/dynamic-fastfetch

    echo "dynamic-fastfetch" >> "$CONFIG_FILE"

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
    tee "$HOME/.config/fastfetch/base_config.jsonc" << 'EOF'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "type": "none",
    "padding": {
    "top": 0
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
    "break",
    __GPU_VRAM_MODULES__
  ]
}
EOF

    if [ -f "/usr/bin/get-gpu-vram" ]; then
        sudo rm "/usr/bin/get-gpu-vram"
    fi

    sudo tee "/usr/bin/get-gpu-vram" << 'EOF'
#!/bin/bash

# Function to get AMD GPU names and count
get_amd_gpus() {
    lspci -nn | grep -i "VGA" | grep -i "AMD" | sed 's/.*\[AMD\/ATI\] //; s/ \[.*\]//'
}

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

# Get GPU names
amd_names=()
if [ "$amd_count" -gt 0 ]; then
    while IFS= read -r line; do
        amd_names+=("$line")
    done < <(get_amd_gpus)
fi

nvidia_names=()
if [ "$nvidia_count" -gt 0 ] && $has_nvidia_smi; then
    while IFS= read -r line; do
        nvidia_names+=("$line")
    done < <(nvidia-smi --query-gpu=name --format=csv,noheader)
fi

# Check if any GPUs are found
if [ "$amd_count" -le 0 ] && [ "$nvidia_count" -le 0 ]; then
    exit 0
fi

# Process AMD GPUs if found
if [ "$amd_count" -gt 0 ]; then
    if $has_rocm_smi; then
        # Loop through each AMD GPU index
        for ((gpu=0; gpu<amd_count; gpu++)); do
            used_mem_bytes=$(rocm-smi --showmeminfo vram -d $gpu | grep 'Used Memory' | awk '{print $NF}')
            total_mem_bytes=$(rocm-smi --showmeminfo vram -d $gpu | grep 'Total Memory' | awk '{print $NF}')
            used_mem_mb=$(echo "$used_mem_bytes / 1048576" | bc)
            total_mem_mb=$(echo "$total_mem_bytes / 1048576" | bc)
            
            # Output format: GPU_NAME||VRAM_INFO
            # FIX: Use $gpu instead of 0 to get the correct GPU name
            gpu_name=$(rocm-smi --showproductname -d $gpu | grep 'Card Series' | awk -F: '{print $NF}' | xargs)
            echo "$gpu_name||$used_mem_mb/$total_mem_mb MB"
        done
    else
        # If no rocm-smi, just output the names
        for ((gpu=0; gpu<amd_count; gpu++)); do
            gpu_name="${amd_names[$gpu]:-AMD GPU $gpu}"
            echo "$gpu_name||Memory info unavailable"
        done
    fi
fi

# Process NVIDIA GPUs if found
if [ "$nvidia_count" -gt 0 ]; then
    if $has_nvidia_smi; then
        # Get memory usage for all NVIDIA GPUs
        nvidia_index=0
        nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader,nounits | while read -r line; do
            index=$(echo "$line" | awk -F ', ' '{print $1}')
            used=$(echo "$line" | awk -F ', ' '{print $2}')
            total=$(echo "$line" | awk -F ', ' '{print $3}')
            
            # Output format: GPU_NAME||VRAM_INFO
            gpu_name="${nvidia_names[$nvidia_index]:-NVIDIA GPU $index}"
            echo "$gpu_name||$used/$total MB"
            
            nvidia_index=$((nvidia_index + 1))
        done
    else
        # If no nvidia-smi, just output the model names if available
        for ((gpu=0; gpu<nvidia_count; gpu++)); do
            gpu_name="${nvidia_names[$gpu]:-NVIDIA GPU $gpu}"
            echo "$gpu_name||Memory info unavailable"
        done
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

# Process each line of output
while IFS= read -r line; do
    # Split by the || delimiter to get name and info
    gpu_name=$(echo "$line" | cut -d'|' -f1)
    vram_info=$(echo "$line" | cut -d'|' -f3-)  # Allows for cases where || might appear in the vram_info
    
    # Escape any quotes in the line
    escaped_vram_info=$(echo "$vram_info" | sed 's/"/\\"/g')
    escaped_gpu_name=$(echo "$gpu_name" | sed 's/"/\\"/g')
    
    # Create a JSON module for this GPU
    if [ -n "$modules" ]; then
        modules="${modules},"
    fi
    modules="${modules}{\"type\": \"command\", \"text\": \"echo '$escaped_vram_info'\", \"key\": \"$escaped_gpu_name\"}"
done <<< "$output"

# Output the JSON
echo "$modules"
EOF

    sudo chmod +x /usr/bin/dynamic-gpu-vram
}