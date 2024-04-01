#!/bin/bash

# ROCM-AI-Installer
# Copyright © 2023-2024 Mateusz Dera

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

export HSA_OVERRIDE_GFX_VERSION=11.0.0

# Version
version="3.2.1"

# Default installation path
default_installation_path="$HOME/AI"
# Global variable for installation path
installation_path="$default_installation_path"

if ! command -v whiptail &> /dev/null; then
    sudo apt-get update
    sudo apt-get -y install whiptail
fi

## MENUS

# Function to display the main menu
show_menu() {
    whiptail --title "ROCm-AI-Installer $version" --menu "Choose an option:" 15 100 8 \
    0 "Installation path ($installation_path)" \
    1 "Install ROCm and required packages" \
    2 "Text generation" \
    3 "Image generation" \
    4 "Music generation" \
    5 "Voice generation" \
    6 "3D models generation" \
    2>&1 > /dev/tty
}

# Installation path
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

# Text generation
text_generation() {
    whiptail --title "Text generation" --menu "Choose an option:" 15 100 3 \
    0 "KoboldCPP" \
    1 "Text generation web UI" \
    2 "SillyTavern" \
    2>&1 > /dev/tty
}

# Text generation web UI
text_generation_web_ui() {
    whiptail --title "Text generation web UI" --menu "Choose an option:" 15 100 3 \
    0 "Backup" \
    1 "Install" \
    2 "Restore" \
    2>&1 > /dev/tty
}

text_generation_web_ui_backup() {
    whiptail --title "Text generation web UI" --menu "Choose an option:" 15 100 4 \
    0 "Backup models" \
    1 "Backup characters" \
    2 "Backup presets" \
    3 "Backup instruction-templates" \
    2>&1 > /dev/tty
}

text_generation_web_ui_restore() {
    whiptail --title "Text generation web UI" --menu "Choose an option:" 15 100 4 \
    0 "Restore models" \
    1 "Restore characters" \
    2 "Restore presets" \
    3 "Restore instruction-templates" \
    2>&1 > /dev/tty
}

# SillyTavern
sillytavern() {
    whiptail --title "SillyTavern" --menu "Choose an option:" 15 100 4 \
    0 "Backup" \
    1 "Install" \
    2 "Install extras (Smart Context + Silero TTS)" \
    3 "Restore" \
    2>&1 > /dev/tty
}

sillytavern_backup() {
    whiptail --title "SillyTavern" --menu "Choose an option:" 15 100 8 \
    0 "Backup config.yaml" \
    1 "Backup settings.json" \
    2 "Backup characters" \
    3 "Backup groups" \
    4 "Backup worlds" \
    5 "Backup chats" \
    6 "Backup group chats" \
    7 "Backup user avatars images" \
    8 "Backup backgrounds images" \
    9 "Backup themes" \
    10 "Backup presets" \
    11 "Backup context" \
    12 "Backup instruct" \
    2>&1 > /dev/tty
}

sillytavern_restore() {
    whiptail --title "SillyTavern" --menu "Choose an option:" 15 100 8 \
    0 "Restore config.yaml" \
    1 "Restore settings.json" \
    2 "Restore characters" \
    3 "Restore groups" \
    4 "Restore worlds" \
    5 "Restore chats" \
    6 "Restore group chats" \
    7 "Restore user avatars images" \
    8 "Restore backgrounds images" \
    9 "Restore themes" \
    10 "Restore presets" \
    11 "Restore context" \
    12 "Restore instruct" \
    2>&1 > /dev/tty
}

image_generation() {
    whiptail --title "Image generation" --menu "Choose an option:" 15 100 2 \
    0 "Stable Diffusion web UI" \
    1 "Install ANIMAGINE XL 3.1" \
    2>&1 > /dev/tty
}

stable_diffusion_web_ui() {
    whiptail --title "Stable Diffusion web UI" --menu "Choose an option:" 15 100 3 \
    0 "Backup" \
    1 "Install" \
    2 "Restore" \
    2>&1 > /dev/tty
}

stable_diffusion_web_ui_backup() {
    whiptail --title "Stable Diffusion web UI" --menu "Choose an option:" 15 100 1 \
    0 "Backup models" \
    2>&1 > /dev/tty
}

stable_diffusion_web_ui_restore() {
    whiptail --title "Stable Diffusion web UI" --menu "Choose an option:" 15 100 1 \
    0 "Restore models" \
    2>&1 > /dev/tty
}

animagine_xl() {
    whiptail --title "ANIMAGINE XL 3.1" --menu "Choose an option:" 15 100 3 \
    0 "Backup" \
    1 "Install" \
    2 "Restore" \
    2>&1 > /dev/tty
}

animagine_xl_backup() {
    whiptail --title "ANIMAGINE XL 3.1" --menu "Choose an option:" 15 100 1 \
    0 "Backup config.py" \
    2>&1 > /dev/tty
}

animagine_xl_restore() {
    whiptail --title "ANIMAGINE XL 3.1" --menu "Choose an option:" 15 100 1 \
    0 "Restore config.py" \
    2>&1 > /dev/tty
}

music_generation() {
    whiptail --title "Music generation" --menu "Choose an option:" 15 100 1 \
    0 "Install AudioCraft" \
    2>&1 > /dev/tty
}

voice_generation() {
    whiptail --title "Voice generation" --menu "Choose an option:" 15 100 1 \
    0 "Install WhisperSpeech web UI" \
    2>&1 > /dev/tty
}

d3_generation() {
    whiptail --title "3D generation" --menu "Choose an option:" 15 100 1 \
    0 "Install TripoSR" \
    2>&1 > /dev/tty
}
## INSTALLATIONS

# Function to install ROCm and basic packages
install_rocm() {
    sudo apt-get update
    sudo apt-get -y upgrade
    sudo apt purge -y rocm*
    sudo apt purge -y hip*
    sudo apt purge -y nvidia*

    sudo apt-get install -y wget

    sudo mkdir --parents --mode=0755 /etc/apt/keyrings
    sudo rm /etc/apt/keyrings/rocm.gpg

    sudo rm /etc/apt/sources.list.d/rocm.list
    wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
    gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/6.0.2 jammy main" \
        | sudo tee --append /etc/apt/sources.list.d/rocm.list

    sudo rm /etc/apt/preferences.d/rocm-pin-600
    echo -e 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600' \
        | sudo tee /etc/apt/preferences.d/rocm-pin-600 

    sudo rm /etc/apt/sources.list.d/amdgpu.list
    echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/latest/ubuntu jammy main' \
        | sudo tee /etc/apt/sources.list.d/amdgpu.list

    sudo apt update -y 
    sudo apt-add-repository -y -s -s
    sudo apt install -y "linux-headers-$(uname -r)" \
        "linux-modules-extra-$(uname -r)"

    sudo apt-get install -y python3 python3-venv python3-dev python3-tk python3.10 python3.10-venv python3.10-dev python3.11 python3.11-venv python3.11-dev \
        rsync git git-lfs ffmpeg libstdc++-12-dev libtcmalloc-minimal4 imagemagick libgl1 libglib2.0-0 amdgpu-dkms \
        rocm-dev rocm-libs rocm-hip-sdk rocm-dkms rocm-libs libeigen3-dev \
        snapd build-essential libgtk-3-dev

    sudo snap install node --classic

    sudo rm /etc/ld.so.conf.d/rocm.conf
    sudo tee --append /etc/ld.so.conf.d/rocm.conf <<EOF
/opt/rocm/lib
/opt/rocm/lib64
EOF
    sudo ldconfig
}

# KoboldCPP
install_koboldcpp() {
    if ! command -v python3.11 &> /dev/null; then
        echo "Install Python 3.11 first"
        exit 1
    fi

    mkdir -p $installation_path
    cd $installation_path
    if [ -d "koboldcpp-rocm" ]
    then
        rm -rf koboldcpp-rocm
    fi
    git clone https://github.com/YellowRoseCx/koboldcpp-rocm.git
    cd koboldcpp-rocm
    git checkout ba3f5e37a55a60b0e696c45f22f82ac2ef37af34
    python3.11 -m venv .venv --prompt Kobold
    source .venv/bin/activate
    make LLAMA_HIPBLAS=1 -j4
    tee --append custom_requirements.txt <<EOF
certifi==2024.2.2
charset-normalizer==3.3.2
customtkinter==5.2.2
darkdetect==0.8.0
filelock==3.13.1
fsspec==2024.2.0
gguf==0.6.0
huggingface-hub==0.21.4
idna==3.6
numpy==1.24.4
packaging==24.0
protobuf==4.25.3
PyYAML==6.0.1
regex==2023.12.25
requests==2.31.0
safetensors==0.4.2
sentencepiece==0.1.98
tokenizers==0.15.2
tqdm==4.66.2
transformers==4.38.2
typing_extensions==4.10.0
urllib3==2.2.1
EOF
    pip install -r custom_requirements.txt
        
    tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export CUDA_VISIBLE_DEVICES=0
source $installation_path/koboldcpp-rocm/.venv/bin/activate
python koboldcpp.py
EOF
    chmod +x run.sh
}

# Text generation web UI
install_text_generation_web_ui() {
    if ! command -v python3.11 &> /dev/null; then
        echo "Install Python 3.11 first"
        exit 1
    fi

    mkdir -p $installation_path
    cd $installation_path
    rm -rf text-generation-webui
    git clone https://github.com/oobabooga/text-generation-webui.git
    cd text-generation-webui
    git checkout aa0da07af012e251b4b70a1391b0acd360f796bd
    python3.11 -m venv .venv --prompt TextGen
    source .venv/bin/activate

    tee --append custom_requirements.txt <<EOF
--extra-index-url https://download.pytorch.org/whl/nightly/rocm6.0
absl-py==2.1.0
accelerate==0.27.2
aiofiles==23.2.1
aiohttp==3.9.3
aiosignal==1.3.1
alembic==1.13.1
altair==5.2.0
annotated-types==0.6.0
anyio==4.3.0
appdirs==1.4.4
asttokens==2.4.1
attrs==23.2.0
auto-gptq @ https://github.com/jllllll/AutoGPTQ/releases/download/v0.6.0/auto_gptq-0.6.0+rocm5.6-cp311-cp311-linux_x86_64.whl
backoff==2.2.1
beautifulsoup4==4.12.2
blinker==1.7.0
blis==0.7.11
catalogue==2.0.10
certifi==2022.12.7
chardet==5.2.0
charset-normalizer==2.1.1
chromadb==0.3.18
click==8.1.7
clickhouse-connect==0.7.2
cloudpathlib==0.16.0
cmake==3.25.0
colorama==0.4.6
coloredlogs==15.0.1
colorlog==6.8.2
confection==0.1.4
contourpy==1.2.0
cramjam==2.8.2
cycler==0.12.1
cymem==2.0.8
DataProperty==1.0.1
datasets==2.18.0
dill==0.3.8
diskcache==5.6.3
distro==1.9.0
docker-pycreds==0.4.0
docopt==0.6.2
duckdb==0.10.0
einops==0.7.0
executing==2.0.1
exllamav2 @ https://github.com/oobabooga/exllamav2/releases/download/v0.0.15/exllamav2-0.0.15+rocm5.6-cp311-cp311-linux_x86_64.whl
fastapi==0.110.0
fastparquet==2024.2.0
ffmpy==0.3.2
filelock==3.13.1
Flask==3.0.2
flask-cloudflared==0.0.14
fonttools==4.49.0
frozenlist==1.4.1
fsspec==2024.2.0
gekko==1.0.7
gitdb==4.0.11
GitPython==3.1.42
gptq-for-llama @ https://github.com/jllllll/GPTQ-for-LLaMa-CUDA/releases/download/0.1.1/gptq_for_llama-0.1.1+rocm5.6-cp311-cp311-linux_x86_64.whl
gradio==3.50.2
gradio_client==0.6.1
graphviz==0.20.1
greenlet==3.0.3
grpcio==1.62.1
h11==0.14.0
hnswlib==0.8.0
hqq==0.1.5
httpcore==1.0.4
httptools==0.6.1
httpx==0.27.0
huggingface-hub==0.21.4
humanfriendly==10.0
icecream==2.1.3
idna==3.4
importlib_resources==6.1.3
iniconfig==2.0.0
itsdangerous==2.1.2
Jinja2==3.1.2
joblib==1.3.2
jsonlines==4.0.0
jsonschema==4.21.1
jsonschema-specifications==2023.12.1
kiwisolver==1.4.5
langcodes==3.3.0
lion-pytorch==0.1.2
lit==15.0.7
llama_cpp_python @ https://github.com/oobabooga/llama-cpp-python-cuBLAS-wheels/releases/download/cpu/llama_cpp_python-0.2.55+cpuavx2-cp311-cp311-manylinux_2_31_x86_64.whl
llama_cpp_python_cuda @ https://github.com/oobabooga/llama-cpp-python-cuBLAS-wheels/releases/download/rocm/llama_cpp_python_cuda-0.2.55+rocm5.6.1-cp311-cp311-manylinux_2_31_x86_64.whl
lm-eval==0.3.0
lxml==5.1.0
lz4==4.3.3
Mako==1.3.2
Markdown==3.5.2
markdown-it-py==3.0.0
MarkupSafe==2.1.3
matplotlib==3.8.3
mbstrdecoder==1.1.3
mdurl==0.1.2
monotonic==1.6
mpmath==1.2.1
multidict==6.0.5
multiprocess==0.70.16
murmurhash==1.0.10
networkx==3.2.1
ninja==1.11.1.1
nltk==3.8.1
num2words==0.5.13
numexpr==2.9.0
numpy==1.26.4
openai==1.13.3
optimum==1.17.1
optuna==3.5.0
orjson==3.9.15
packaging==22.0
pandas==2.0.3
pathvalidate==3.2.0
peft==0.8.2
pillow==10.2.0
pluggy==1.4.0
portalocker==2.8.2
posthog==2.4.2
preshed==3.0.9
protobuf==4.25.3
psutil==5.9.8
pyarrow==15.0.1
pyarrow-hotfix==0.6
pybind11==2.11.1
pycountry==23.12.11
pydantic==1.10.1
pydantic_core==2.16.3
pydub==0.25.1
Pygments==2.17.2
pyparsing==3.1.2
pytablewriter==1.2.0
pytest==8.1.1
pytextrank==3.3.0
python-dateutil==2.9.0.post0
python-dotenv==1.0.1
python-multipart==0.0.9
pytorch-triton==3.0.0+a9bc1a3647
pytorch-triton-rocm==3.0.0+0a22a91d04
pytz==2024.1
PyYAML==6.0.1
referencing==0.33.0
regex==2023.12.25
requests==2.28.1
rich==13.7.1
rouge==1.0.1
rouge-score==0.1.2
rpds-py==0.18.0
sacrebleu==1.5.0
safetensors==0.4.2
scikit-learn==1.4.1.post1
scipy==1.12.0
semantic-version==2.10.0
sentence-transformers==2.2.2
sentencepiece==0.2.0
sentry-sdk==1.41.0
setproctitle==1.3.3
six==1.16.0
smart-open==6.4.0
smmap==5.0.1
sniffio==1.3.1
soupsieve==2.5
spacy==3.7.4
spacy-legacy==3.0.12
spacy-loggers==1.0.5
SpeechRecognition==3.10.0
SQLAlchemy==2.0.28
sqlitedict==2.1.0
srsly==2.4.8
sse-starlette==1.6.5
starlette==0.36.3
sympy==1.12
tabledata==1.3.3
tcolorpy==0.1.4
tensorboard==2.16.2
tensorboard-data-server==0.7.2
termcolor==2.4.0
thinc==8.2.3
threadpoolctl==3.3.0
tiktoken==0.6.0
timm==0.9.16
tokenizers==0.15.2
toolz==0.12.1
torch==2.3.0.dev20240311+rocm6.0
torchaudio==2.2.0.dev20240311+rocm6.0
torchtext==0.6.0
torchvision==0.18.0.dev20240311+rocm6.0
tqdm==4.66.2
tqdm-multiprocess==0.0.11
transformers==4.38.2
triton==2.2.0
typepy==1.3.2
typer==0.9.0
typing_extensions==4.10.0
tzdata==2024.1
urllib3==1.26.13
uvicorn==0.28.0
uvloop==0.19.0
wandb==0.16.4
wasabi==1.1.2
watchfiles==0.21.0
weasel==0.3.4
websockets==11.0.3
Werkzeug==3.0.1
xxhash==3.4.1
yarl==1.9.4
zstandard==0.22.0
EOF
    pip install -r custom_requirements.txt

    git clone https://github.com/arlo-phoenix/bitsandbytes-rocm-5.6.git
    cd bitsandbytes-rocm-5.6
    git checkout 62353b0200b8557026c176e74ac48b84b953a854
    make hip ROCM_TARGET=gfx1100 ROCM_HOME=/opt/rocm-6.0.2/
    pip install . --extra-index-url https://download.pytorch.org/whl/nightly/rocm6.0

    pip install git+https://github.com/ROCmSoftwarePlatform/flash-attention.git@2554f490101742ccdc56620a938f847f61754be6

    git clone https://github.com/turboderp/exllamav2 $installation_path/text-generation-webui/repositories/exllamav2
    cd $installation_path/text-generation-webui/repositories/exllamav2
    git checkout b92cc4f35782db3394e9d7eb3d4d38a44fefa376
    pip install .  --extra-index-url https://download.pytorch.org/whl/nightly/rocm6.0

    cd $installation_path/text-generation-webui

    tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export CUDA_VISIBLE_DEVICES=0
source $installation_path/text-generation-webui/.venv/bin/activate
python server.py --api --listen --loader=exllamav2 --extensions sd_api_pictures send_pictures gallery
EOF
    chmod u+x run.sh
}

# ANIMAGINE XL 3.1
install_animagine_xl() {
    if ! command -v python3.11 &> /dev/null; then
        echo "Install Python 3.11 first"
        exit 1
    fi

    mkdir -p $installation_path
    cd $installation_path
    rm -rf animagine-xl-3.1
    git clone https://huggingface.co/spaces/cagliostrolab/animagine-xl-3.1
    git checkout ab4e48864356682afe0b2b6f32bf7de8a0d6c79e
    cd animagine-xl-3.1
    python3.11 -m venv .venv --prompt ANIMAGINE
    source .venv/bin/activate

    tee --append custom_requirements.txt <<EOF
--extra-index-url https://download.pytorch.org/whl/rocm5.7
accelerate==0.27.2
aiofiles==23.2.1
altair==5.2.0
annotated-types==0.6.0
antlr4-python3-runtime==4.9.3
anyio==4.3.0
attrs==23.2.0
certifi==2024.2.2
charset-normalizer==3.3.2
click==8.1.7
colorama==0.4.6
contourpy==1.2.0
cycler==0.12.1
diffusers==0.26.3
fastapi==0.110.0
ffmpy==0.3.2
filelock==3.13.3
fonttools==4.50.0
fsspec==2024.3.1
gradio==4.20.0
gradio_client==0.11.0
h11==0.14.0
httpcore==1.0.4
httpx==0.27.0
huggingface-hub==0.22.1
idna==3.6
importlib_metadata==7.1.0
importlib_resources==6.4.0
invisible-watermark==0.2.0
Jinja2==3.1.3
jsonschema==4.21.1
jsonschema-specifications==2023.12.1
kiwisolver==1.4.5
markdown-it-py==3.0.0
MarkupSafe==2.1.5
matplotlib==3.8.3
mdurl==0.1.2
mpmath==1.3.0
networkx==3.2.1
numpy==1.26.4
omegaconf==2.3.0
opencv-python==4.9.0.80
orjson==3.9.15
packaging==24.0
pandas==2.2.1
pillow==10.2.0
psutil==5.9.8
pydantic==2.6.4
pydantic_core==2.16.3
pydub==0.25.1
Pygments==2.17.2
pyparsing==3.1.2
python-dateutil==2.9.0.post0
python-multipart==0.0.9
pytorch-triton==0.0.1
pytorch-triton-rocm==2.2.0
pytz==2024.1
PyWavelets==1.5.0
PyYAML==6.0.1
referencing==0.34.0
regex==2023.12.25
requests==2.31.0
rich==13.7.1
rpds-py==0.18.0
ruff==0.3.4
safetensors==0.4.2
semantic-version==2.10.0
shellingham==1.5.4
six==1.16.0
sniffio==1.3.1
spaces==0.24.0
starlette==0.36.3
sympy==1.12
timm==0.9.10
tokenizers==0.15.2
tomlkit==0.12.0
toolz==0.12.1
torch==2.2.0+rocm5.7
torchaudio==2.2.0+rocm5.7
torchdata==0.7.1
torchtext==0.17.0+cpu
torchvision==0.17.0+rocm5.7
tqdm==4.66.2
transformers==4.38.1
triton==2.2.0
typer==0.10.0
typing_extensions==4.10.0
tzdata==2024.1
urllib3==2.2.1
uvicorn==0.29.0
websockets==11.0.3
zipp==3.18.1
EOF

    pip install -r custom_requirements.txt

    tee --append run.sh <<EOF
export HSA_OVERRIDE_GFX_VERSION=11.0.0
source $installation_path/animagine-xl-3.1/.venv/bin/activate
python3 ./app.py
EOF
    chmod +x run.sh
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
    git checkout f121d1da564c6402750683d36b02365631cf04ac

    mv ./start.sh ./run.sh

    # Default config
    cd ./default
    sed -i 's/listen: false/listen: true/' config.yaml
    sed -i 's/whitelistMode: true/whitelistMode: false/' config.yaml
    sed -i 's/basicAuthMode: false/basicAuthMode: true/' config.yaml
}

install_sillytavern_extras(){
    if ! command -v python3.11 &> /dev/null; then
        echo "Install Python 3.11 first"
        exit 1
    fi

    cd $installation_path

    rm -Rf SillyTavern-extras
    git clone https://github.com/SillyTavern/SillyTavern-extras.git
    cd SillyTavern-extras
    git checkout 5b35e91e01f3d29c0147829f702fa79210948cd1

    python3.11 -m venv .venv --prompt SillyTavern-extras
    source .venv/bin/activate

    tee --append custom_requirements.txt <<EOF
--extra-index-url https://download.pytorch.org/whl/rocm5.6
accelerate==0.28.0
aiohttp==3.9.3
aiosignal==1.3.1
annotated-types==0.6.0
anyio==4.3.0
asgiref==3.7.2
attrs==23.2.0
backoff==2.2.1
bcrypt==4.1.2
blinker==1.7.0
Brotli==1.1.0
build==1.1.1
cachetools==5.3.3
certifi==2024.2.2
cffi==1.16.0
charset-normalizer==3.3.2
chroma-hnswlib==0.7.3
chromadb==0.4.24
click==8.1.7
cmake==3.28.3
colorama==0.4.6
coloredlogs==15.0.1
contourpy==1.2.0
cycler==0.12.1
Deprecated==1.2.14
diffusers==0.27.0
edge-tts==6.1.10
fastapi==0.110.0
filelock==3.13.1
Flask==3.0.2
flask-cloudflared==0.0.14
Flask-Compress==1.14
Flask-Cors==4.0.0
flatbuffers==24.3.7
fonttools==4.50.0
frozenlist==1.4.1
fsspec==2024.3.0
google-auth==2.28.2
googleapis-common-protos==1.63.0
grpcio==1.62.1
h11==0.14.0
httptools==0.6.1
huggingface-hub==0.21.4
humanfriendly==10.0
idna==3.6
importlib-metadata==6.11.0
importlib_resources==6.3.1
itsdangerous==2.1.2
Jinja2==3.1.3
joblib==1.3.2
kiwisolver==1.4.5
kubernetes==29.0.0
lit==18.1.1
llvmlite==0.42.0
loguru==0.7.2
Markdown==3.6
MarkupSafe==2.1.5
matplotlib==3.8.3
mmh3==4.1.0
monotonic==1.6
more-itertools==10.2.0
mpmath==1.3.0
multidict==6.0.5
networkx==3.2.1
numba==0.59.0
numpy==1.26.4
oauthlib==3.2.2
onnxruntime==1.17.1
openai-whisper==20231117
opentelemetry-api==1.23.0
opentelemetry-exporter-otlp-proto-common==1.23.0
opentelemetry-exporter-otlp-proto-grpc==1.23.0
opentelemetry-instrumentation==0.44b0
opentelemetry-instrumentation-asgi==0.44b0
opentelemetry-instrumentation-fastapi==0.44b0
opentelemetry-proto==1.23.0
opentelemetry-sdk==1.23.0
opentelemetry-semantic-conventions==0.44b0
opentelemetry-util-http==0.44b0
orjson==3.9.15
outcome==1.3.0.post0
overrides==7.7.0
packaging==24.0
Pillow==9.5.0
posthog==3.5.0
protobuf==4.25.3
psutil==5.9.8
pulsar-client==3.4.0
pyasn1==0.5.1
pyasn1-modules==0.3.0
pycparser==2.21
pydantic==2.6.4
pydantic_core==2.16.3
pydub==0.25.1
pyparsing==3.1.2
PyPika==0.48.9
pyproject_hooks==1.0.0
PySocks==1.7.1
python-dateutil==2.9.0.post0
python-dotenv==1.0.1
pytorch-triton-rocm==2.1.0
PyYAML==6.0.1
regex==2023.12.25
requests==2.31.0
requests-oauthlib==1.4.0
rsa==4.9
safetensors==0.4.2
scikit-learn==1.4.1.post1
scipy==1.12.0
selenium==4.18.1
sentence-transformers==2.5.1
silero-api-server==0.3.1
six==1.16.0
sniffio==1.3.1
sortedcontainers==2.4.0
sounddevice==0.4.6
soundfile==0.12.1
srt==3.5.3
starlette==0.36.3
sympy==1.12
tenacity==8.2.3
threadpoolctl==3.3.0
tiktoken==0.6.0
tokenizers==0.15.2
torch==2.1.0+rocm5.6
torchaudio==2.1.0+rocm5.6
torchvision==0.16.0+rocm5.6
tqdm==4.66.2
transformers==4.38.2
trio==0.25.0
trio-websocket==0.11.1
triton==2.2.0
typer==0.9.0
typing_extensions==4.10.0
urllib3==2.2.1
uvicorn==0.28.0
uvloop==0.19.0
vosk==0.3.45
watchfiles==0.21.0
websocket-client==1.7.0
websockets==12.0
webuiapi==0.9.9
Werkzeug==3.0.1
wrapt==1.16.0
wsproto==1.2.0
wxPython==4.2.1
yarl==1.9.4
zipp==3.18.1
EOF

    pip install --pre -r custom_requirements.txt

    cd $installation_path/SillyTavern-extras
    tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export CUDA_VISIBLE_DEVICES=0
source $installation_path/SillyTavern-extras/.venv/bin/activate
python $installation_path/SillyTavern-extras/server.py --cuda --listen --enable-modules=chromadb,silero-tts
EOF
    chmod +x run.sh
}

# Stable Diffusion web UI
install_stable_diffusion_web_ui() {
    if ! command -v python3.11 &> /dev/null; then
        echo "Install Python 3.11 first"
        exit 1
    fi
    mkdir -p $installation_path
    cd $installation_path
    rm -Rf stable-diffusion-webui
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
    cd stable-diffusion-webui
    git checkout cf2772fab0af5573da775e7437e6acdca424f26e
            
    tee --append webui-user.sh <<EOF
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export TORCH_COMMAND="pip install --pre torch==2.3.0.dev20240306+rocm6.0  torchvision==0.18.0.dev20240306+rocm6.0 --index-url https://download.pytorch.org/whl/nightly"
export COMMANDLINE_ARGS="--api"
#export CUDA_VISIBLE_DEVICES="1"
EOF
    mv ./webui.sh ./run.sh
    chmod +x run.sh
}

# AudioCraft
install_audiocraft() {
    if ! command -v python3.10 &> /dev/null; then
        echo "Install Python 3.10 first"
        exit 1
    fi

    mkdir -p $installation_path
    cd $installation_path
    rm -rf audiocraft
    git clone https://github.com/facebookresearch/audiocraft.git
    cd audiocraft
    git checkout 69fea8b290ad1b4b40d28f92d1dfc0ab01dbab85
    python3.10 -m venv .venv --prompt AudioCraft
    source .venv/bin/activate
            
    tee --append custom_requirements.txt <<EOF
aiofiles==23.2.1
altair==5.2.0
annotated-types==0.6.0
antlr4-python3-runtime==4.9.3
anyio==4.2.0
attrs==23.2.0
audioread==3.0.1
av==11.0.0
blis==0.7.11
catalogue==2.0.10
certifi==2023.11.17
cffi==1.16.0
charset-normalizer==3.3.2
click==8.1.7
cloudpathlib==0.16.0
cloudpickle==3.0.0
cmake==3.28.1
colorama==0.4.6
colorlog==6.8.0
confection==0.1.4
contourpy==1.2.0
cycler==0.12.1
cymem==2.0.8
decorator==5.1.1
demucs==4.0.1
docopt==0.6.2
dora_search==0.1.12
einops==0.7.0
encodec==0.1.1
exceptiongroup==1.2.0
fastapi==0.109.0
ffmpy==0.3.1
filelock==3.13.1
flashy==0.0.2
fonttools==4.47.2
fsspec==2023.12.2
gradio==4.15.0
gradio_client==0.8.1
h11==0.14.0
httpcore==1.0.2
httpx==0.26.0
huggingface-hub==0.20.3
hydra-colorlog==1.2.0
hydra-core==1.3.2
idna==3.6
importlib-resources==6.1.1
Jinja2==3.1.3
joblib==1.3.2
jsonschema==4.21.1
jsonschema-specifications==2023.12.1
julius==0.2.7
kiwisolver==1.4.5
lameenc==1.7.0
langcodes==3.3.0
lazy_loader==0.3
librosa==0.10.1
lightning-utilities==0.10.1
lit==17.0.6
llvmlite==0.41.1
markdown-it-py==3.0.0
MarkupSafe==2.1.4
matplotlib==3.8.2
mdurl==0.1.2
mpmath==1.3.0
msgpack==1.0.7
murmurhash==1.0.10
networkx==3.2.1
num2words==0.5.13
numba==0.58.1
numpy==1.26.3
omegaconf==2.3.0
openunmix==1.2.1
orjson==3.9.12
packaging==23.2
pandas==2.2.0
pillow==10.2.0
platformdirs==4.1.0
pooch==1.8.0
preshed==3.0.9
protobuf==4.25.2
pycparser==2.21
pydantic==2.5.3
pydantic_core==2.14.6
pydub==0.25.1
Pygments==2.17.2
pyparsing==3.1.1
python-dateutil==2.8.2
python-multipart==0.0.6
pytorch-triton-rocm==2.1.0
pytz==2023.3.post1
PyYAML==6.0.1
referencing==0.32.1
regex==2023.12.25
requests==2.31.0
retrying==1.3.4
rich==13.7.0
rpds-py==0.17.1
ruff==0.1.14
safetensors==0.4.1
scikit-learn==1.4.0
scipy==1.12.0
semantic-version==2.10.0
sentencepiece==0.1.99
shellingham==1.5.4
six==1.16.0
smart-open==6.4.0
sniffio==1.3.0
soundfile==0.12.1
soxr==0.3.7
spacy==3.7.2
spacy-legacy==3.0.12
spacy-loggers==1.0.5
srsly==2.4.8
starlette==0.35.1
submitit==1.5.1
sympy==1.12
thinc==8.2.2
threadpoolctl==3.2.0
tokenizers==0.15.1
tomlkit==0.12.0
toolz==0.12.0
torch==2.1.0+rocm5.6
torchaudio==2.1.0+rocm5.6
torchmetrics==1.3.0.post0
tqdm==4.66.1
transformers==4.37.0
treetable==0.2.5
typer==0.9.0
typing_extensions==4.9.0
tzdata==2023.4
urllib3==2.1.0
uvicorn==0.26.0
wasabi==1.1.2
weasel==0.3.4
websockets==11.0.3
xformers==0.0.22.post7
EOF

    pip install -r custom_requirements.txt --extra-index-url https://download.pytorch.org/whl/rocm5.6
        
    tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export CUDA_VISIBLE_DEVICES=0
source $installation_path/audiocraft/.venv/bin/activate
python -m demos.musicgen_app
EOF
    chmod +x run.sh
}

install_whisperspeech_web_ui(){
    if ! command -v python3.11 &> /dev/null; then
        echo "Install Python 3.11 first"
        exit 1
    fi

    mkdir -p $installation_path
    cd $installation_path
    rm -rf whisperspeech-webui
    git clone https://github.com/Mateusz-Dera/whisperspeech-webui.git
    cd whisperspeech-webui
    git checkout d7c1f0542a49b8bfa1b2a2aeb5303e39bfe4b2ac
    python3.11 -m venv .venv --prompt WhisperSpeech
    source .venv/bin/activate

    pip install -r requirements_rocm.txt
    pip install git+https://github.com/ROCmSoftwarePlatform/flash-attention.git@ae7928c5aed53cf6e75cc792baa9126b2abfcf1a

    tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export CUDA_VISIBLE_DEVICES=0
source $installation_path/whisperspeech-webui/.venv/bin/activate
python3 webui.py
EOF
    chmod u+x run.sh
}

install_triposr(){
    if ! command -v python3.11 &> /dev/null; then
        echo "Install Python 3.11 first"
        exit 1
    fi

    mkdir -p $installation_path
    cd $installation_path
    rm -rf TripoSR
    git clone https://github.com/VAST-AI-Research/TripoSR
    cd TripoSR
    git checkout 00319be2f08ddd06a43edf05fbbd46b5ea1e9228
    python3.11 -m venv .venv --prompt TripoSR
    source .venv/bin/activate

    tee --append custom_requirements.txt <<EOF
--extra-index-url https://download.pytorch.org/whl/nightly/rocm6.0
aiofiles==23.2.1
altair==5.2.0
annotated-types==0.6.0
antlr4-python3-runtime==4.9.3
anyio==4.3.0
attrs==23.2.0
certifi==2024.2.2
charset-normalizer==3.3.2
click==8.1.7
colorama==0.4.6
coloredlogs==15.0.1
contourpy==1.2.0
cycler==0.12.1
einops==0.7.0
exceptiongroup==1.2.0
fastapi==0.110.0
ffmpy==0.3.2
filelock==3.13.1
flatbuffers==24.3.6
fonttools==4.49.0
fsspec==2024.2.0
gradio==4.8.0
gradio_client==0.7.1
h11==0.14.0
httpcore==1.0.4
httpx==0.27.0
huggingface-hub==0.17.3
humanfriendly==10.0
idna==3.6
imageio==2.34.0
imageio-ffmpeg==0.4.9
importlib_resources==6.1.3
Jinja2==3.1.3
jsonschema==4.21.1
jsonschema-specifications==2023.12.1
kiwisolver==1.4.5
lazy_loader==0.3
llvmlite==0.42.0
markdown-it-py==3.0.0
MarkupSafe==2.1.3
matplotlib==3.8.3
mdurl==0.1.2
mpmath==1.2.1
networkx==3.2.1
numba==0.59.0
numpy==1.26.4
omegaconf==2.3.0
onnxruntime==1.17.1
opencv-python-headless==4.9.0.80
orjson==3.9.15
packaging==23.2
pandas==2.2.1
Pillow==10.1.0
platformdirs==4.2.0
pooch==1.8.1
protobuf==4.25.3
psutil==5.9.8
pydantic==2.6.3
pydantic_core==2.16.3
pydub==0.25.1
Pygments==2.17.2
PyMatting==1.1.12
pyparsing==3.1.2
python-dateutil==2.9.0.post0
python-multipart==0.0.9
pytorch-triton-rocm==3.0.0+0a22a91d04
pytz==2024.1
PyYAML==6.0.1
referencing==0.33.0
regex==2023.12.25
rembg==2.0.55
requests==2.31.0
rich==13.7.1
rpds-py==0.18.0
safetensors==0.4.2
scikit-image==0.22.0
scipy==1.12.0
semantic-version==2.10.0
shellingham==1.5.4
six==1.16.0
sniffio==1.3.1
starlette==0.36.3
sympy==1.12
tifffile==2024.2.12
tokenizers==0.14.1
tomlkit==0.12.0
toolz==0.12.1
torch==2.3.0.dev20240311+rocm6.0
torchaudio==2.2.0.dev20240311+rocm6.0
torchvision==0.18.0.dev20240311+rocm6.0
tqdm==4.66.2
transformers==4.35.0
trimesh==4.0.5
typer==0.9.0
typing_extensions==4.8.0
tzdata==2024.1
urllib3==2.2.1
uvicorn==0.27.1
websockets==11.0.3
EOF

    pip install -r custom_requirements.txt
    pip install git+https://github.com/tatsy/torchmcubes.git@3aef8afa5f21b113afc4f4ea148baee850cbd472

    tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export CUDA_VISIBLE_DEVICES=0
source $installation_path/TripoSR/.venv/bin/activate
python3 gradio_app.py
EOF
    chmod u+x run.sh
}
## MAIN

backup_and_restore() {
    # Check if folder exists
    if ! [ -e "$1" ]; then
        echo "Folder or file '$1' does not exist." && exit 1 
    fi

    if ! [ -d "$2" ]; then
        # Create backup folder
        mkdir -p "$2" || (echo "Failed to create folder '$2'." && exit 1)
    else
        rm -rf "$2" || (echo "Failed to remove old folder '$2'." && exit 1)
    fi

    # Copy the contents $1 to $2
    rsync -av --progress --delete "$1/" "$2" || (echo "Failed to copy contents of '$1' to '$2'." && exit 1)
}

backup_and_restore_file() {
    # Check if file exists
    if ! [ -e "$1/$3" ]; then
        echo "File '$1/$3' does not exist." && exit 1 
    fi

    if ! [ -d "$2" ]; then
        # Create backup folder
        mkdir -p "$2" || (echo "Failed to create folder '$2'." && exit 1)
    fi

    # Copy the contents $1 to $2
    cp -f "$1/$3" "$2/$3" || (echo "Failed to copy contents of '$1$3' to '$2'." && exit 1)
}

# Main loop
while true; do
    choice=$(show_menu)

    case $choice in
        0)
            # Set installation path
            set_installation_path
            ;;
        1)
            # Install ROCm and basic packages
            install_rocm
            ;;
        2)
            # Text generation
            first=true
            while $first; do
            
                choice=$(text_generation)

                case $choice in
                    0)
                        # KoboldCPP
                        install_koboldcpp
                        ;;
                    1)
                        # Text generation web UI
                        second=true
                        while $second; do
                            choice=$(text_generation_web_ui)

                            case $choice in
                                0)
                                    # Backup
                                    next=true
                                    while $next; do
                                        choice=$(text_generation_web_ui_backup)
                                        case $choice in
                                            0)
                                                # Backup models
                                                backup_and_restore $installation_path/text-generation-webui/models $installation_path/Backups/text-generation-webui/models
                                                ;;
                                            1)
                                                # Backup characters
                                                backup_and_restore $installation_path/text-generation-webui/characters $installation_path/Backups/text-generation-webui/characters
                                                ;;
                                            2)
                                                # Backup presets
                                                backup_and_restore $installation_path/text-generation-webui/presets $installation_path/Backups/text-generation-webui/presets
                                                ;;
                                            3)
                                                # Backup instruction-templates
                                                backup_and_restore $installation_path/text-generation-webui/instruction-templates $installation_path/Backups/text-generation-webui/instruction-templates
                                                ;;
                                            *)
                                                next=false
                                                ;;
                                        esac
                                    done
                                    ;;
                                1)
                                    # Install
                                    install_text_generation_web_ui
                                    ;;
                                2)
                                    # Restore
                                    next=true
                                    while $next; do
                                        choice=$(text_generation_web_ui_restore)

                                        case $choice in
                                            0)
                                                # Restore models
                                                backup_and_restore $installation_path/Backups/text-generation-webui/models $installation_path/text-generation-webui/models
                                                ;;
                                            1)
                                                # Restore characters
                                                backup_and_restore $installation_path/Backups/text-generation-webui/characters $installation_path/text-generation-webui/characters
                                                ;;
                                            2)
                                                # Restore presets
                                                backup_and_restore $installation_path/Backups/text-generation-webui/presets $installation_path/text-generation-webui/presets
                                                ;;
                                            3)
                                                # Restore instruction-templates
                                                backup_and_restore $installation_path/Backups/text-generation-webui/instruction-templates $installation_path/text-generation-webui/instruction-templates
                                                ;;
                                            *)
                                                next=false
                                                ;;
                                        esac
                                    done
                                    ;;
                                *)
                                    second=false
                                    ;;
                            esac
                        done
                        ;;
                    2)
                        # SillyTavern
                        second=true
                        while $second; do
                            choice=$(sillytavern)

                            case $choice in
                                0)
                                    next=true
                                    while $next; do
                                        choice=$(sillytavern_backup)
                                        case $choice in
                                            0)
                                                # Backup config
                                                backup_and_restore_file $installation_path/SillyTavern $installation_path/Backups/SillyTavern config.yaml
                                                ;;
                                            1)
                                                # Backup settings
                                                backup_and_restore_file $installation_path/SillyTavern/public $installation_path/Backups/SillyTavern/public settings.json
                                                ;;
                                            2)
                                                # Backup characters
                                                backup_and_restore $installation_path/SillyTavern/public/characters $installation_path/Backups/SillyTavern/public/characters
                                                ;;
                                            3)
                                                # Backup groups
                                                backup_and_restore $installation_path/SillyTavern/public/groups $installation_path/Backups/SillyTavern/public/groups
                                                ;;
                                            4)
                                                # Backup worlds
                                                backup_and_restore $installation_path/SillyTavern/public/worlds $installation_path/Backups/SillyTavern/public/worlds
                                                ;;
                                            5)
                                                # Backup chats
                                                backup_and_restore $installation_path/SillyTavern/public/chats $installation_path/Backups/SillyTavern/public/chats
                                                ;;
                                            6)
                                                # Backup group chats
                                                backup_and_restore $installation_path/SillyTavern/public/group\ chats $installation_path/Backups/SillyTavern/public/group\ chats
                                                ;;
                                            7)
                                                # Backup user avatars images
                                                backup_and_restore $installation_path/SillyTavern/public/User\ Avatars $installation_path/Backups/SillyTavern/public/User\ Avatars
                                                ;;
                                            8)
                                                # Backup backgrounds images
                                                backup_and_restore $installation_path/SillyTavern/public/backgrounds $installation_path/Backups/SillyTavern/public/backgrounds
                                                ;;
                                            9)
                                                # Backup themes
                                                backup_and_restore $installation_path/SillyTavern/public/themes $installation_path/Backups/SillyTavern/public/themes
                                                ;;
                                            10)
                                                # Backup presets
                                                backup_and_restore $installation_path/SillyTavern/public/TextGen\ Settings $installation_path/Backups/SillyTavern/public/TextGen\ Settings
                                                ;;
                                            11)
                                                # Backup context
                                                backup_and_restore $installation_path/SillyTavern/public/context $installation_path/Backups/SillyTavern/public/context
                                                ;;
                                            12)
                                                # Backup instruct
                                                backup_and_restore $installation_path/SillyTavern/public/instruct $installation_path/Backups/SillyTavern/public/instruct
                                                ;;
                                            *)
                                                next=false
                                                ;;
                                        esac
                                    done
                                    ;;
                                1)
                                    # Install
                                    install_sillytavern
                                    ;;
                                2)
                                    # Install extras (Smart Context + Silero TTS)
                                    install_sillytavern_extras
                                    ;;
                                3)  
                                    # Restore
                                    next=true
                                    while $next; do
                                        choice=$(sillytavern_restore)
                                        case $choice in
                                            0)
                                                # Restoreconfig
                                                backup_and_restore_file $installation_path/Backups/SillyTavern $installation_path/SillyTavern config.yaml
                                                ;;
                                            1)
                                                # Restore settings
                                                backup_and_restore_file $installation_path/Backups/SillyTavern/public $installation_path/SillyTavern/public settings.json
                                                ;;
                                            2)
                                                # Restore characters
                                                backup_and_restore $installation_path/Backups/SillyTavern/public/characters $installation_path/SillyTavern/public/characters
                                                ;;
                                            3)
                                                # Restore groups
                                                backup_and_restore $installation_path/Backups/SillyTavern/public/groups $installation_path/SillyTavern/public/groups
                                                ;;
                                            4)
                                                # Restore worlds
                                                backup_and_restore $installation_path/Backups/SillyTavern/public/worlds $installation_path/SillyTavern/public/worlds
                                                ;;
                                            5)
                                                # Restore chats
                                                backup_and_restore $installation_path/Backups/SillyTavern/public/chats $installation_path/SillyTavern/public/chats
                                                ;;
                                            6)
                                                # Restore group chats
                                                backup_and_restore $installation_path/Backups/SillyTavern/public/group\ chats $installation_path/SillyTavern/public/group\ chats
                                                ;;
                                            7)
                                                # Restore user avatars images
                                                backup_and_restore $installation_path/Backups/SillyTavern/public/User\ Avatars $installation_path/SillyTavern/public/User\ Avatars
                                                ;;
                                            8)
                                                # Restore backgrounds images
                                                backup_and_restore $installation_path/Backups/SillyTavern/public/backgrounds $installation_path/SillyTavern/public/backgrounds
                                                ;;
                                            9)
                                                # Restore themes
                                                backup_and_restore $installation_path/Backups/SillyTavern/public/themes $installation_path/SillyTavern/public/themes
                                                ;;
                                            10)
                                                # Restore presets
                                                backup_and_restore $installation_path/Backups/SillyTavern/public/TextGen\ Settings $installation_path/SillyTavern/public/TextGen\ Settings
                                                ;;
                                            11)
                                                # Restore context
                                                backup_and_restore $installation_path/Backups/SillyTavern/public/context $installation_path/SillyTavern/public/context
                                                ;;
                                            12)
                                                # Restore instruct
                                                backup_and_restore $installation_path/Backups/SillyTavern/public/instruct $installation_path/SillyTavern/public/instruct
                                                ;;
                                            *)
                                                next=false
                                                ;;
                                        esac
                                    done
                                    ;;
                                *)
                                    second=false
                                ;;
                            esac
                        done
                        ;;
                    *)
                        first=false
                        ;;
                esac
            done
            ;;
        3)
            # Image generation
            first=true
            while $first; do
                choice=$(image_generation)
                case $choice in
                    0)
                        # Stable Diffusion web UI
                        second=true
                        while $second; do
                            choice=$(stable_diffusion_web_ui)
                            case $choice in
                                0)
                                    # Backup
                                    next=true
                                    while $next; do
                                        choice=$(stable_diffusion_web_ui_backup)
                                        case $choice in
                                            0)
                                                # Backup models
                                                backup_and_restore $installation_path/stable-diffusion-webui/models $installation_path/Backups/stable-diffusion-webui/models
                                                ;;
                                            *)
                                                next=false
                                                ;;
                                        esac
                                    done
                                    ;;
                                1)
                                    # Install
                                    install_stable_diffusion_web_ui
                                    ;;
                                2)
                                    # Restore
                                    next=true
                                    while $next; do
                                        choice=$(stable_diffusion_web_ui_restore)
                                        case $choice in
                                            0)
                                                # Restore models
                                                backup_and_restore $installation_path/Backups/stable-diffusion-webui/models $installation_path/stable-diffusion-webui/models
                                                ;;
                                            *)
                                                next=false
                                                ;;
                                        esac
                                    done
                                    ;;
                                *)
                                    second=false
                                    ;;
                            esac
                        done
                        ;;
                    1) 
                        # ANIMAGINE XL 3.1
                        second=true
                        while $second; do
                            choice=$(animagine_xl)
                            case $choice in
                                0)
                                    # Backup
                                    next=true
                                    while $next; do
                                        choice=$(animagine_xl_backup)
                                        case $choice in
                                            0)
                                                # Backup config.py
                                                backup_and_restore_file $installation_path/animagine-xl-3.1 $installation_path/Backups/animagine-xl-3.1 config.py
                                                ;;
                                            *)
                                                next=false
                                                ;;
                                        esac
                                    done
                                    ;;
                                1)
                                    # Install
                                    install_animagine_xl
                                    ;;
                                2)
                                    # Restore
                                    next=true
                                    while $next; do
                                        choice=$(animagine_xl_restore)
                                        case $choice in
                                            0)
                                                # Restore config.py
                                                backup_and_restore_file $installation_path/Backups/animagine-xl-3.1 $installation_path/animagine-xl-3.1 config.py
                                                ;;
                                            *)
                                                next=false
                                                ;;
                                        esac
                                    done
                                    ;;
                                *)
                                    second=false
                                    ;;
                            esac
                        done
                        ;;
                    *)
                        first=false
                        ;;
                esac
            done
            ;;
        4)
            # Music generation
            first=true
            while $first; do
            
                choice=$(music_generation)

                case $choice in
                    0)
                        # AudioCraft
                        install_audiocraft
                        ;;
                    *)
                        first=false
                        ;;
                esac
            done
            ;;
        5)
            # Voice generation
            first=true
            while $first; do
            
                choice=$(voice_generation)

                case $choice in
                    0)
                        # WhisperSpeech web UI
                        install_whisperspeech_web_ui
                        ;;
                    *)
                        first=false
                        ;;
                esac
            done
            ;;
        6)
            # 3D generation
            first=true
            while $first; do
            
                choice=$(d3_generation)

                case $choice in
                    0)
                        # TripoSR
                        install_triposr
                        ;;
                    *)
                        first=false
                        ;;
                esac
            done
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