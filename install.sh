#!/bin/bash

# ROCM-AI-Installer
# Copyright © 2023 Mateusz Dera

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

# arch="x86_64"
export HSA_OVERRIDE_GFX_VERSION=11.0.0

# Default installation path
default_installation_path="$HOME/AI"
# Global variable for installation path
installation_path="$default_installation_path"

sudo apt-get update
sudo apt-get upgrade -y

sudo add-apt-repository -y -s deb http://security.ubuntu.com/ubuntu jammy main universe

sudo mkdir --parents --mode=0755 /etc/apt/keyrings
sudo rm /etc/apt/keyrings/rocm.gpg
sudo rm /etc/apt/sources.list.d/rocm.list
wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
    gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/5.7.2 jammy main" \
    | sudo tee --append /etc/apt/sources.list.d/rocm.list
echo -e 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600' \
    | sudo tee /etc/apt/preferences.d/rocm-pin-600 
sudo rm /etc/apt/sources.list.d/amdgpu.list
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/latest/ubuntu jammy main' \
    | sudo tee /etc/apt/sources.list.d/amdgpu.list
sudo apt update -y 

sudo apt-add-repository -y -s -s
sudo apt install -y "linux-headers-$(uname -r)" \
	"linux-modules-extra-$(uname -r)"

sudo apt-get install -y whiptail wget curl git git-lfs ffmpeg libstdc++-12-dev libtcmalloc-minimal4 python3 python3-venv python3-dev pip imagemagick libgl1 libglib2.0-0 amdgpu-dkms rocm-dev rocm-libs rocm-hip-sdk rocm-dkms rocm-libs

sudo rm /etc/ld.so.conf.d/rocm.conf
sudo tee --append /etc/ld.so.conf.d/rocm.conf <<EOF
/opt/rocm/lib
/opt/rocm/lib64
EOF
sudo ldconfig

# Function to display the main menu
show_menu() {
    whiptail --title "Menu Example" --menu "Choose an option:" 15 100 4 \
    0 "Set Installation Path ($installation_path)" \
    1 "stable-diffusion-webui" \
    2 "text-generation-webui" \
    3 "SillyTavern" \
    2>&1 > /dev/tty
}

# Function to display the SillyTavern submenu
show_sillytavern_submenu() {
    whiptail --title "SillyTavern Submenu" --menu "Choose an option for SillyTavern:" 15 150 2 \
    1 "SillyTavern" \
    2 "SillyTavern + Extras + chromadb + XTTS-v2" \
    2>&1 > /dev/tty
}

# Function to set the installation path
set_installation_path() {
    # Prompt for installation path, using the default if the user leaves it blank
    new_installation_path=$(whiptail --inputbox "Enter the installation path (default: $default_installation_path):" 10 150 "$installation_path" 3>&1 1>&2 2>&3)

    # If the user leaves it blank, use the default
    new_installation_path=${new_installation_path:-$default_installation_path}

    # Remove trailing "/" if it exists
    new_installation_path=$(echo "$new_installation_path" | sed 's#/$##')

    # Update the installation path variable
    installation_path="$new_installation_path"
}

# Main loop
while true; do
    choice=$(show_menu)

    case $choice in
        0)
            # Set Installation Path
            set_installation_path
            ;;
        1)
            # Action for Option 1
            if ! command -v python3.11 &> /dev/null; then
                echo "Install Python 3.11 first"
                exit 1
            fi
            mkdir -p $installation_path
            cd $installation_path
            rm -Rf stable-diffusion-webui
            git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
            cd stable-diffusion-webui
            git checkout 4afaaf8a020c1df457bcf7250cb1c7f609699fa7
            python3.11 -m venv .venv --prompt StableDiffusion
            source .venv/bin/activate
            # pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/rocm5.7
            tee --append custom_requirements.txt <<EOF
absl-py==2.0.0
accelerate==0.21.0
addict==2.4.0
aenum==3.1.15
aiofiles==23.2.1
aiohttp==3.9.1
aiosignal==1.3.1
altair==5.2.0
annotated-types==0.6.0
antlr4-python3-runtime==4.9.3
anyio==3.7.1
attrs==23.1.0
basicsr==1.4.2
beautifulsoup4==4.12.2
blendmodes==2022
boltons==23.1.1
cachetools==5.3.2
certifi==2022.12.7
charset-normalizer==2.1.1
clean-fid==0.1.35
click==8.1.7
contourpy==1.2.0
cycler==0.12.1
deprecation==2.1.0
einops==0.4.1
facexlib==0.3.0
fastapi==0.94.0
ffmpy==0.3.1
filelock==3.9.0
filterpy==1.4.5
fonttools==4.46.0
frozenlist==1.4.0
fsspec==2023.4.0
ftfy==6.1.3
future==0.18.3
gdown==4.7.1
gfpgan==1.3.8
gitdb==4.0.11
GitPython==3.1.32
google-auth==2.24.0
google-auth-oauthlib==1.1.0
gradio==3.41.2
gradio_client==0.5.0
grpcio==1.59.3
h11==0.12.0
httpcore==0.15.0
httpx==0.24.1
huggingface-hub==0.17.3
idna==3.4
imageio==2.33.0
importlib-metadata==7.0.0
importlib-resources==6.1.1
inflection==0.5.1
Jinja2==3.1.2
jsonmerge==1.8.0
jsonschema==4.20.0
jsonschema-specifications==2023.11.2
kiwisolver==1.4.5
kornia==0.6.7
lark==1.1.2
lazy_loader==0.3
lightning-utilities==0.10.0
llvmlite==0.41.1
lmdb==1.4.1
lpips==0.1.4
Markdown==3.5.1
MarkupSafe==2.1.3
matplotlib==3.8.2
mpmath==1.2.1
multidict==6.0.4
networkx==3.2.1
numba==0.58.1
numpy==1.23.5
oauthlib==3.2.2
omegaconf==2.2.3
open-clip-torch==2.20.0
opencv-python==4.8.1.78
orjson==3.9.10
packaging==23.2
pandas==2.1.3
piexif==1.1.3
Pillow==9.5.0
platformdirs==4.0.0
protobuf==3.20.3
psutil==5.9.5
pyasn1==0.5.1
pyasn1-modules==0.3.0
pydantic==1.10.13
pydantic_core==2.14.5
pydub==0.25.1
pyparsing==3.1.1
PySocks==1.7.1
python-dateutil==2.8.2
python-multipart==0.0.6
pytorch-lightning==1.9.4
pytorch-triton-rocm==2.1.0+dafe145982
pytz==2023.3.post1
PyWavelets==1.5.0
PyYAML==6.0.1
realesrgan==0.3.0
referencing==0.31.1
regex==2023.10.3
requests==2.28.1
requests-oauthlib==1.3.1
resize-right==0.0.2
rpds-py==0.13.2
rsa==4.9
safetensors==0.3.2
scikit-image==0.21.0
scipy==1.11.4
semantic-version==2.10.0
sentencepiece==0.1.99
six==1.16.0
smmap==5.0.1
sniffio==1.3.0
soupsieve==2.5
starlette==0.26.1
sympy==1.11.1
tb-nightly==2.16.0a20231203
tensorboard-data-server==0.7.2
tf-keras-nightly==2.16.0.dev2023120310
tifffile==2023.9.26
timm==0.9.2
tokenizers==0.13.3
tomesd==0.1.3
tomli==2.0.1
toolz==0.12.0
torch==2.2.0.dev20231203+rocm5.7
torchaudio==2.2.0.dev20231203+rocm5.7
torchdiffeq==0.2.3
torchmetrics==1.2.1
torchsde==0.2.5
torchvision==0.17.0.dev20231203+rocm5.7
tqdm==4.66.1
trampoline==0.1.2
transformers==4.30.2
typing_extensions==4.8.0
tzdata==2023.3
urllib3==1.26.13
uvicorn==0.24.0.post1
wcwidth==0.2.12
websockets==11.0.3
Werkzeug==3.0.1
yapf==0.40.2
yarl==1.9.3
zipp==3.17.0
EOF
            pip install -r custom_requirements.txt --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7
            tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export TF_ENABLE_ONEDNN_OPTS=0
export TORCH_COMMAND="pip install torch==2.2.0.dev20231203+rocm5.7 torchvision==0.17.0.dev20231203+rocm5.7 --index-url https://download.pytorch.org/whl/nightly/rocm5.7"
export COMMANDLINE_ARGS="--api"
#export CUDA_VISIBLE_DEVICES="1"
source $installation_path/stable-diffusion-webui/.venv/bin/activate
$installation_path/stable-diffusion-webui/webui.sh 
EOF
            chmod +x run.sh
            $installation_path/stable-diffusion-webui/run.sh
            sed -i 's/from torchvision.transforms.functional_tensor import rgb_to_grayscale/from torchvision.transforms.functional import rgb_to_grayscale/' .venv/lib/python3.11/site-packages/basicsr/data/degradations.py
            ;;
        2)
            # Action for Option 2
            cd /tmp
            curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
            bash Miniforge3-$(uname)-$(uname -m).sh -b -p "${HOME}/conda"
            source "${HOME}/conda/etc/profile.d/conda.sh"

            conda install -y cmake ninja

            # conda remove --name textgen --all -y
            conda create -n textgen python=3.11 -y
            conda activate textgen

            mkdir -p $installation_path

            cd $installation_path
            rm -rf text-generation-webui
            git clone https://github.com/oobabooga/text-generation-webui
            cd $installation_path/text-generation-webui

            cd $installation_path/text-generation-webui
            rm -rf flash-attention
            git clone https://github.com/ROCmSoftwarePlatform/flash-attention.git
            cd flash-attention
            pip install .

            echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="
            echo "Basic packages"
            echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-="

            pip install --pre cmake colorama filelock lit numpy Pillow Jinja2 \
                mpmath fsspec MarkupSafe certifi filelock networkx \
                sympy packaging requests \
                    --index-url https://download.pytorch.org/whl/nightly/rocm5.7
            pip install --pre torch==2.2.0.dev20231128   --index-url https://download.pytorch.org/whl/nightly/rocm5.7
            pip install torchdata==0.7.1
            pip install --pre torch==2.2.0.dev20231128 torchvision==0.17.0.dev20231128+rocm5.7 torchtext==0.17.0.dev20231128+cpu torchaudio triton pytorch-triton pytorch-triton-rocm    --index-url https://download.pytorch.org/whl/nightly/rocm5.7

            cd $installation_path/text-generation-webui
            git clone https://github.com/arlo-phoenix/bitsandbytes-rocm-5.6.git
            cd bitsandbytes-rocm-5.6/
            BUILD_CUDA_EXT=0 pip install -r requirements.txt --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7
            make hip ROCM_TARGET=gfx1100,gfx1030 ROCM_HOME=/opt/rocm-5.7.2/
            pip install . --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7
            pip install -U --index-url https://aiinfra.pkgs.visualstudio.com/PublicPackages/_packaging/Triton-Nightly/pypi/simple/ triton-nightly

            pip install -U --index-url https://aiinfra.pkgs.visualstudio.com/PublicPackages/_packaging/Triton-Nightly/pypi/simple/ triton-nightly

            cd $installation_path/text-generation-webui
            rm -rf text-generation-webui
            git clone https://github.com/oobabooga/text-generation-webui
            cd text-generation-webui

            sed -i "s@bitsandbytes==@bitsandbytes>=@g" requirements_amd.txt 
            pip install -r requirements_amd.txt

            git clone https://github.com/turboderp/exllama repositories/exllama
            git clone https://github.com/turboderp/exllamav2 repositories/exllamav2

            cd $installation_path/text-generation-webui/repositories/exllama
            pip install -r requirements.txt

            cd $installation_path/text-generation-webui/repositories/exllamav2
            pip install -r requirements.txt

            cd $installation_path/text-generation-webui

            tee --append run.sh <<EOF
#!/bin/bash
source "${HOME}/conda/etc/profile.d/conda.sh"
conda activate textgen 
python server.py --api --listen --loader=exllama  \
  --auto-devices --extensions sd_api_pictures send_pictures gallery 
conda deactivate
EOF
            chmod u+x run.sh
            ;;
        3)
            mkdir -p $installation_path
            cd $installation_path
            rm -Rf SillyTavern
            git clone https://github.com/SillyTavern/SillyTavern.git
            cd SillyTavern
            sudo snap install node --classic
            # Submenu for SillyTavern
            # submenu_choice=$(show_sillytavern_submenu)
            
            # case $submenu_choice in
            #     1)
            #         # Action for SillyTavern
            #         whiptail --msgbox "You selected SillyTavern" 10 120
            #         ;;
            #     2)
            #         # Action for SillyTavern + Extras + chromadb + XTTS-v2
            #         whiptail --msgbox "You selected SillyTavern + Extras + chromadb + XTTS-v2" 10 120
            #         ;;
            #     *)
            #         # Cancel
            #         ;;
            # esac
            ;;
        *)
            # Cancel or Exit
            whiptail --yesno "Do you really want to exit?" 10 30
            if [ $? -eq 0 ]; then
                exit 0
            fi
            ;;
    esac
done
