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
    install "https://github.com/oobabooga/text-generation-webui.git" "ace8afb825c80925ed21ab26dbf66b538ab06285" "export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"\n python server.py --api --listen --extensions sd_api_pictures send_pictures gallery"

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
                download "fal/AuraSR-v2" "ff452185a7c8b51206dd62c21c292e7baad5c3a3" "model.safetensors"
                download "fal/AuraSR" "87da2f52b29b6351391f71c74de581c393fc19f5" "model.safetensors"
                
                pip install aura-sr==0.0.4
                ;;
            '"3"')
                # AuraFlow
                cd $installation_path/ComfyUI/models/checkpoints
                download "fal/AuraFlow-v0.3" "2cd8588f04c886002be4571697d84654a50e3af3" "aura_flow_0.3.safetensors"
                ;;
            '"4"')
                gguf=1
                # Flux
                cd $installation_path/ComfyUI/models/unet
                download "city96/FLUX.1-schnell-gguf" "f495746ed9c5efcf4661f53ef05401dceadc17d2" "flux1-schnell-Q8_0.gguf"
                ;;
            '"5"')
                gguf=1
                # AnimePro FLUX
                cd $installation_path/ComfyUI/models/unet
                #wget "https://civitai.com/api/download/models/1053818?type=Model&format=GGUF&size=full&fp=bf16" -O "animepro-flux-Q5_0.gguf"
                download "advokat/AnimePro-FLUX" "be1cbbe8280e6d038836df868c79cdf7687ad39d" "animepro-Q5_K_M.gguf"
                ;;
            '"6"')
                gguf=1
                # AnimePro FLUX
                cd $installation_path/ComfyUI/models/unet
                download "hum-ma/Flex.1-alpha-GGUF" "2ccb9cb781dfbafdf707e21b915c654c4fa6a07d" "Flex.1-alpha-Q8_0.gguf"
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
        git checkout 3d673c5c098ecaa6e6027f834659ba8de534ca32
        pip install gguf==0.10.0
        cd $installation_path/ComfyUI/models/text_encoders
        download "city96/t5-v1_1-xxl-encoder-bf16" "1b9c856aadb864af93c1dcdc226c2774fa67bc86" "model.safetensors"
        mv ./model.safetensors ./t5-v1_1-xxl-encoder-bf16.safetensors
        download "openai/clip-vit-large-patch14" "32bd64288804d66eefd0ccbe215aa642df71cc41" "model.safetensors"
        mv ./model.safetensors ./clip-vit-large-patch14.safetensors
        cd $installation_path/ComfyUI/models/vae
        download "black-forest-labs/FLUX.1-schnell" "741f7c3ce8b383c54771c7003378a50191e9efe9" "diffusion_pytorch_model.safetensors" "vae"
    fi
}

# ACE-Step
install_audiocraft() {
    install "https://github.com/ace-step/ACE-Step" "9bf891fb2880383cc845309c3a2dd9a46e1942d6" "python app.py --server_name 0.0.0.0"
}

# WhisperSpeech web UI
install_whisperspeech_web_ui(){
    install "https://github.com/Mateusz-Dera/whisperspeech-webui.git" "d4628117816293d8a068cb1dd653359540f0aa15" "python3 webui.py --listen"
    pip install -r requirements_rocm_6.3.txt
}

# F5-TTS
install_f5_tts(){
    install "https://github.com/SWivid/F5-TTS.git" "d457c3e2450ee83a8a27b6f41808716c7763311b" "f5-tts_infer-gradio --host 0.0.0.0"
    git submodule update --init --recursive
    pip install -e . --extra-index-url https://download.pytorch.org/whl/rocm6.2.4
    pip install git+https://github.com/ROCm/bitsandbytes.git@e4fe8b5b281670512dfda3fc01731bacb9b509dd --extra-index-url https://download.pytorch.org/whl/rocm6.2.4
    pip install git+https://github.com/ROCm/flash-attention@b28f18350af92a68bec057875fd486f728c9f084 --no-build-isolation --extra-index-url https://download.pytorch.org/whl/rocm6.2.4
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

# StableTTS
install_stabletts(){
    install "https://github.com/lpscr/StableTTS.git" "71dfa4138c511df8e0aedf444df98c6baa44cad4" "python3 webui.py"
    cd $installation_path/StableTTS
    cd ./checkpoints
    download "KdaiP/StableTTS1.1" "ce2a21a5fad05fc46573b084320e721da72caf95" "checkpoint_0.pt" "StableTTS"
    cd $installation_path/StableTTS
    cd ./vocoders/pretrained
    download "KdaiP/StableTTS1.1" "ce2a21a5fad05fc46573b084320e721da72caf95" "firefly-gan-base-generator.ckpt" "vocoders"
    download "KdaiP/StableTTS1.1" "ce2a21a5fad05fc46573b084320e721da72caf95" "vocos.pt" "vocoders"
    cd $installation_path/StableTTS
    mkdir ./temps
    sed -i 's/demo.launch(debug=True, show_api=True)/demo.launch(debug=True,server_name="0.0.0.0")/' "webui.py"
}

# Dia
install_dia(){
    install "https://github.com/tralamazza/dia.git" "50c336c73b2358a98fb35f682951bbce8e96ef60" "MIOPEN_FIND_MODE=FAST uv run --extra rocm app.py"
    pip install uv==0.6.16
    sed -i 's/demo.launch(share=args.share)/demo.launch(share=args.share,server_name="0.0.0.0")/' "app.py"
}

# TripoSR
install_triposr(){
    install "https://github.com/VAST-AI-Research/TripoSR" "d26e33181947bbbc4c6fc0f5734e1ec6c080956e" "python3 gradio_app.py --listen"
    pip install git+https://github.com/tatsy/torchmcubes.git@3381600ddc3d2e4d74222f8495866be5fafbace4 --extra-index-url https://download.pytorch.org/whl/rocm6.2.4
}

# TripoSG
install_triposg(){
    install "https://github.com/VAST-AI-Research/TripoSG" "b52f852283d2e61b74653f00dbffe01c258320e4" "python app.py"
    pip install torch-cluster --no-build-isolation --extra-index-url https://download.pytorch.org/whl/rocm6.2.4
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

    tee --append "$HOME/.config/fastfetch/config.jsonc" << 'EOF'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "modules": [
    "title",
    "separator",
    "os",
    "host",
    "kernel",
    "uptime",
    "packages",
    "shell",
    "de",
    "cpu",
    "memory",
    "swap",
    "gpu",
    {
        "type": "command",
        "text": "echo $(( $(rocm-smi --showmeminfo vram | grep 'Used Memory' | awk '{print $NF}') / 1048576 )) 'MiB /' $(( $(rocm-smi --showmeminfo vram | grep 'Total Memory' | awk '{print $NF}') / 1048576 )) 'MiB'",
        "key": "GPU Memory"
    },
    "disk",
    "localip",
    "battery",
    "poweradapter",
    "break",
    "colors"
  ]
}
EOF

echo "New Fastfetch config created"
}