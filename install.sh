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
version="5.1"

# Default installation path
default_installation_path="$HOME/AI"
# Global variable for installation path
installation_path="$default_installation_path"

if ! command -v whiptail &> /dev/null; then
    sudo apt update
    sudo apt -y install whiptail
fi

## MENUS
export NEWT_COLORS='
root=,black
textbox=white,black
border=brightred,black
window=white,black
title=brightred,black
button=black,white
compactbutton=brightred,black
listbox=white,black
actlistbox=black,white
actsellistbox=black,brightred
'

# Function to display the main menu
show_menu() {
    whiptail --title "ROCm-AI-Installer $version" --menu "Choose an option:" 17 100 10 \
    0 "Installation path ($installation_path)" \
    1 "Install ROCm and required packages" \
    2 "Text generation" \
    3 "Image generation" \
    4 "Video generation" \
    5 "Music generation" \
    6 "Voice generation" \
    7 "3D models generation" \
    8 Tools \
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
    whiptail --title "SillyTavern" --menu "Choose an option:" 15 100 3 \
    0 "Backup" \
    1 "Install" \
    2 "Restore" \
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
    whiptail --title "Image generation" --menu "Choose an option:" 15 100 4 \
    0 "Stable Diffusion web UI" \
    1 "ANIMAGINE XL 3.1" \
    2 "ComfyUI + Addons" \
    3 "Install Artist" \
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

comfyui() {
    whiptail --title "ComfyUI + Addons" --menu "Choose an option:" 15 100 3 \
    0 "Backup" \
    1 "Install" \
    2 "Restore" \
    2>&1 > /dev/tty
}

comfyui_backup() {
    whiptail --title "ComfyUI" --menu "Choose an option:" 15 100 1 \
    0 "Backup models" \
    2>&1 > /dev/tty
}

comfyui_restore() {
    whiptail --title "ComfyUI" --menu "Choose an option:" 15 100 1 \
    0 "Restore models" \
    2>&1 > /dev/tty
}


video_generation() {
    whiptail --title "Video generation" --menu "Choose an option:" 15 100 1 \
    0 "Install Cinemo" \
    2>&1 > /dev/tty
}

music_generation() {
    whiptail --title "Music generation" --menu "Choose an option:" 15 100 1 \
    0 "Install AudioCraft" \
    2>&1 > /dev/tty
}

voice_generation() {
    whiptail --title "Voice generation" --menu "Choose an option:" 15 100 2 \
    0 "Install WhisperSpeech web UI" \
    1 "Install MeloTTS" \
    2>&1 > /dev/tty
}

d3_generation() {
    whiptail --title "3D generation" --menu "Choose an option:" 15 100 1 \
    0 "Install TripoSR" \
    2>&1 > /dev/tty
}

tools() {
    whiptail --title "Tools" --menu "Choose an option:" 15 100 1 \
    0 "Install ExLlamaV2" \
    2>&1 > /dev/tty
}
## INSTALLATIONS

# Remove old
remove_old() {
    sudo apt purge -y rocm*
    sudo apt purge -y hip*
    sudo apt purge -y nvidia*

    if [ -f /etc/apt/keyrings/rocm.gpg ]; then
        sudo rm /etc/apt/keyrings/rocm.gpg
    fi

    if [ -f /etc/apt/sources.list.d/amdgpu.list ]; then
        sudo rm /etc/apt/sources.list.d/amdgpu.list
    fi

    if [ -f /etc/apt/sources.list.d/rocm.list ]; then
        sudo rm /etc/apt/sources.list.d/rocm.list
    fi

    if [ -f /etc/apt/preferences.d/rocm-pin-600 ]; then
        sudo rm /etc/apt/preferences.d/rocm-pin-600
    fi

    sudo apt autoremove -y
}

# Repositories
repo(){
    # Update
    sudo apt update -y && sudo apt upgrade -y
    
    # Wget
    sudo apt install -y wget

    # AMDGPU
    sudo apt-add-repository -y -s -s
    sudo apt install -y "linux-headers-$(uname -r)" \
	"linux-modules-extra-$(uname -r)"
    sudo mkdir --parents --mode=0755 /etc/apt/keyrings
    wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
    gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null
    echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/6.2/ubuntu noble main' \
    | sudo tee /etc/apt/sources.list.d/amdgpu.list
    sudo apt update -y
    sudo apt install -y amdgpu-dkms

    # ROCm
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/6.2 noble main" \
    | sudo tee --append /etc/apt/sources.list.d/rocm.list
    echo -e 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600' \
    | sudo tee /etc/apt/preferences.d/rocm-pin-600
    sudo apt update -y
    sudo apt install -y rocm-dev rocm-libs rocm-hip-sdk rocm-libs

    # Python
    sudo add-apt-repository ppa:deadsnakes/ppa -y
    sudo apt update -y 
}

profile(){
    # Check if there's a line starting with PATH=
    if grep -q '^PATH=' ~/.profile; then
        # If the line exists, add new paths at the beginning if they're not already there
        if ! grep -q '/opt/rocm/bin' ~/.profile || ! grep -q '/opt/rocm/opencl/bin' ~/.profile; then
            sed -i '/^PATH=/ s|PATH=|PATH=/opt/rocm/bin:/opt/rocm/opencl/bin:|' ~/.profile
            echo "Added new paths ~/.profile"
        else
            echo "Paths already exist in ~/.profile"
        fi
    else
        # If the line doesn't exist, add a new line with these paths at the beginning
        echo 'PATH=/opt/rocm/bin:/opt/rocm/opencl/bin:$PATH' >> ~/.profile
        echo "Added a new PATH line to ~/.profile"
    fi
}

# Function to install ROCm and basic packages
install_rocm() {
    sudo apt update -y
    remove_old

    repo

    sudo tee --append /etc/ld.so.conf.d/rocm.conf <<EOF
/opt/rocm/lib
/opt/rocm/lib64
EOF
    sudo ldconfig

    profile

    sudo apt install -y git git-lfs
    sudo apt install -y libstdc++-12-dev
    sudo apt install -y libtcmalloc-minimal4
    sudo apt install -y git git-lfs
    sudo apt install -y python3.12 python3.12-venv python3.12-dev python3.12-tk
    sudo apt install -y python3.11 python3.11-venv python3.11-dev python3.11-tk
    sudo apt install -y libgl1
    sudo apt install -y ffmpeg
    sudo apt install -y libmecab-dev
    sudo apt install -y rustc

    sudo snap install node --classic
}

# KoboldCPP
install_koboldcpp() {
    if ! command -v python3.12 &> /dev/null; then
        echo "Install Python 3.12 first"
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
    git checkout d15e1fd60bfe53d0a159dc8bb47504d682c53d59
    python3.12 -m venv .venv --prompt Kobold
    source .venv/bin/activate
    
    tee --append custom_requirements.txt <<EOF
--extra-index-url https://download.pytorch.org/whl/rocm6.1
certifi==2024.7.4
charset-normalizer==3.3.2
customtkinter==5.2.2
darkdetect==0.8.0
filelock==3.15.4
fsspec==2024.6.1
gguf==0.9.1
huggingface-hub==0.24.5
idna==3.7
numpy==2.0.1
packaging==24.1
protobuf==5.27.3
psutil==6.0.0
PyYAML==6.0.2
regex==2024.7.24
requests==2.32.3
safetensors==0.4.4
sentencepiece==0.2.0
tokenizers==0.19.1
tqdm==4.66.5
transformers==4.44.0
typing_extensions==4.12.2
urllib3==2.2.2
EOF
    pip install -r custom_requirements.txt
    
    make LLAMA_HIPBLAS=1 -j4
        
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
    git checkout 5522584992c632d75d2389e9342793fd1dcc391d
    python3.11 -m venv .venv --prompt TextGen
    source .venv/bin/activate
    
    pip install --upgrade pip
    
    tee --append custom_requirements.txt <<EOF
--extra-index-url https://download.pytorch.org/whl/rocm6.1
absl-py==2.1.0
accelerate==0.33.0
aiofiles==23.2.1
aiohappyeyeballs==2.3.5
aiohttp==3.10.1
aiosignal==1.3.1
alembic==1.13.2
annotated-types==0.7.0
anyio==4.4.0
asgiref==3.8.1
asttokens==2.4.1
attrs==24.2.0
backoff==2.2.1
bcrypt==4.2.0
beautifulsoup4==4.12.2
bitblas==0.0.1.dev13
blinker==1.8.2
blis==0.7.11
build==1.2.1
cachetools==5.4.0
catalogue==2.0.10
certifi==2022.12.7
cffi==1.17.0
chardet==5.2.0
charset-normalizer==2.1.1
chroma-hnswlib==0.7.3
chromadb==0.4.24
click==8.1.7
cloudpathlib==0.18.1
cloudpickle==3.0.0
cmake==3.25.0
colorama==0.4.6
coloredlogs==15.0.1
colorlog==6.8.2
confection==0.1.5
contourpy==1.2.1
cpplint==1.6.1
cramjam==2.8.3
cycler==0.12.1
cymem==2.0.8
Cython==3.0.11
DataProperty==1.0.1
datasets==2.20.0
decorator==5.1.1
Deprecated==1.2.14
dill==0.3.8
diskcache==5.6.3
docker-pycreds==0.4.0
docopt==0.6.2
docutils==0.21.2
dtlib==0.0.0.dev2
einops==0.8.0
evaluate==0.4.2
execnet==2.1.1
executing==2.0.1
fastapi==0.112.0
fastparquet==2024.5.0
ffmpy==0.4.0
filelock==3.13.1
Flask==3.0.3
flask-cloudflared==0.0.14
flatbuffers==24.3.25
fonttools==4.53.1
frozenlist==1.4.1
fsspec==2024.2.0
gitdb==4.0.11
GitPython==3.1.43
google-auth==2.33.0
googleapis-common-protos==1.63.2
gradio==4.40.0
gradio_client==1.2.0
graphviz==0.20.3
greenlet==3.0.3
grpcio==1.65.4
h11==0.14.0
hqq==0.1.8
httpcore==1.0.5
httptools==0.6.1
httpx==0.27.0
huggingface-hub==0.24.5
humanfriendly==10.0
icecream==2.1.3
idna==3.4
importlib_metadata==8.0.0
importlib_resources==6.4.0
iniconfig==2.0.0
itsdangerous==2.2.0
Jinja2==3.1.4
joblib==1.4.2
jsonlines==4.0.0
kiwisolver==1.4.5
kubernetes==30.1.0
langcodes==3.4.0
language_data==1.2.0
lit==15.0.7
llama_cpp_python==0.2.87
llvmlite==0.43.0
lm_eval==0.4.3
lxml==5.2.2
Mako==1.3.5
marisa-trie==1.2.0
Markdown==3.6
markdown-it-py==3.0.0
MarkupSafe==2.1.5
matplotlib==3.9.1.post1
mbstrdecoder==1.1.3
mdurl==0.1.2
ml-dtypes==0.4.0
mmh3==4.1.0
monotonic==1.6
more-itertools==10.4.0
mpmath==1.3.0
multidict==6.0.5
multiprocess==0.70.16
murmurhash==1.0.10
networkx==3.2.1
ninja==1.11.1.1
nltk==3.8.1
num2words==0.5.13
numba==0.60.0
numexpr==2.10.1
numpy==1.26.3
oauthlib==3.2.2
onnxruntime==1.18.1
opentelemetry-api==1.26.0
opentelemetry-exporter-otlp-proto-common==1.26.0
opentelemetry-exporter-otlp-proto-grpc==1.26.0
opentelemetry-instrumentation==0.47b0
opentelemetry-instrumentation-asgi==0.47b0
opentelemetry-instrumentation-fastapi==0.47b0
opentelemetry-proto==1.26.0
opentelemetry-sdk==1.26.0
opentelemetry-semantic-conventions==0.47b0
opentelemetry-util-http==0.47b0
optuna==3.6.1
orjson==3.10.6
overrides==7.7.0
packaging==22.0
pandas==2.0.3
pathvalidate==3.2.0
peft==0.12.0
pillow==10.2.0
platformdirs==4.2.2
pluggy==1.5.0
portalocker==2.10.1
posthog==2.4.2
preshed==3.0.9
protobuf==4.25.4
psutil==6.0.0
pulsar-client==3.5.0
pyarrow==17.0.0
pyarrow-hotfix==0.6
pyasn1==0.6.0
pyasn1_modules==0.4.0
pybind11==2.13.1
pycparser==2.22
pydantic==2.8.2
pydantic_core==2.20.1
pydub==0.25.1
Pygments==2.18.0
pyparsing==3.1.2
PyPika==0.48.9
pyproject_hooks==1.1.0
pytablewriter==1.2.0
pytest==8.3.2
pytest-xdist==3.6.1
pytextrank==3.3.0
python-dateutil==2.9.0.post0
python-dotenv==1.0.1
python-multipart==0.0.9
pytorch-triton-rocm==3.0.0
pytz==2024.1
PyYAML==6.0.2
rapidfuzz==3.9.6
regex==2024.7.24
requests==2.32.3
requests-oauthlib==2.0.0
rich==13.7.1
rouge-score==0.1.2
rsa==4.9
ruff==0.5.6
sacrebleu==2.4.2
safetensors==0.4.4
scikit-learn==1.5.1
scipy==1.14.0
semantic-version==2.10.0
sentence-transformers==2.2.2
sentencepiece==0.2.0
sentry-sdk==2.12.0
setuptools==72.1.0
setproctitle==1.3.3
shellingham==1.5.4
six==1.16.0
smart-open==7.0.4
smmap==5.0.1
sniffio==1.3.1
soupsieve==2.5
spacy==3.7.5
spacy-legacy==3.0.12
spacy-loggers==1.0.5
SpeechRecognition==3.10.4
SQLAlchemy==2.0.32
sqlitedict==2.1.0
srsly==2.4.8
sse-starlette==2.1.3
starlette==0.37.2
sympy==1.12
tabledata==1.3.3
tabulate==0.9.0
tcolorpy==0.1.6
tenacity==9.0.0
tensorboard==2.17.0
tensorboard-data-server==0.7.2
termcolor==2.4.0
thefuzz==0.22.1
thinc==8.2.5
threadpoolctl==3.5.0
tiktoken==0.7.0
tokenizers==0.19.1
tomlkit==0.12.0
torch==2.4.0+rocm6.1
torchaudio==2.4.0+rocm6.1
torchvision==0.19.0+rocm6.1
tornado==6.4.1
tqdm==4.66.5
tqdm-multiprocess==0.0.11
triton==3.0.0
typepy==1.3.2
typer==0.12.3
typing_extensions==4.12.2
tzdata==2024.1
urllib3==2.2.2
uvicorn==0.30.5
uvloop==0.19.0
wandb==0.17.6
wasabi==1.1.3
watchfiles==0.23.0
weasel==0.4.1
websocket-client==1.8.0
websockets==12.0
Werkzeug==3.0.3
wheel==0.44.0
word2number==1.1
wrapt==1.16.0
xxhash==3.4.1
yarl==1.9.4
zipp==3.19.2
zstandard==0.23.0
EOF

    pip install -r custom_requirements.txt

    pip install https://download.pytorch.org/whl/cpu/torchtext-0.18.0%2Bcpu-cp311-cp311-linux_x86_64.whl#sha256=c760e672265cd6f3e4a7c8d4a78afe9e9617deacda926a743479ee0418d4207d

    pip install git+https://github.com/ROCm/bitsandbytes.git@c336a2644c6590e16a1d64cc695a06523bb9824e
    
    pip install git+https://github.com/ROCm/flash-attention@b28f18350af92a68bec057875fd486f728c9f084 --no-build-isolation --extra-index-url https://download.pytorch.org/whl/rocm6.1


    pip install https://github.com/casper-hansen/AutoAWQ/releases/download/v0.2.5/autoawq-0.2.5+rocm561-cp311-cp311-linux_x86_64.whl#sha256=7beb816dcfb1e669aa75ceee94dbfef13da32b34a462dcaa4cb34d58c7997aa1
    pip installhttps://github.com/casper-hansen/AutoAWQ_kernels/releases/download/v0.0.6/autoawq_kernels-0.0.6+rocm561-cp311-cp311-linux_x86_64.whl#sha256=b453d520398692efdf106df5197b372106001756ffcfc013acc9cf1bf5efe35c

    pip install transformers==4.44.2 --extra-index-url https://download.pytorch.org/whl/rocm6.1

    cd $installation_path/text-generation-webui
    git clone https://github.com/turboderp/exllamav2 repositories/exllamav2
    cd repositories/exllamav2
    git checkout 40e37f494488d930bb196b6e01d9c5c8a64456e8
    pip install . --extra-index-url https://download.pytorch.org/whl/rocm6.1

    export GGML_HIPBLAS=on
    CMAKE_ARGS="-DGGML_HIPBLAS=on" pip install llama-cpp-python==0.2.87

    cd $installation_path/text-generation-webui/modules
    sed -i '37,40d' llama_cpp_python_hijack.py

    cd $installation_path/text-generation-webui
    tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
source $installation_path/text-generation-webui/.venv/bin/activate
TORCH_BLAS_PREFER_HIPBLASLT=0 python server.py --api --listen --loader=exllamav2 --extensions sd_api_pictures send_pictures gallery
EOF
chmod u+x run.sh
}

# ANIMAGINE XL 3.1
install_animagine_xl() {
    if ! command -v python3.12 &> /dev/null; then
        echo "Install Python 3.12 first"
        exit 1
    fi

    mkdir -p $installation_path
    cd $installation_path
    rm -rf animagine-xl-3.1
    git clone https://huggingface.co/spaces/cagliostrolab/animagine-xl-3.1
    git checkout 914bc5dc90bc05f8782f6fe10ab6cae0607f5566
    cd animagine-xl-3.1
    python3.12 -m venv .venv --prompt ANIMAGINE
    source .venv/bin/activate

    tee --append custom_requirements.txt <<EOF
--extra-index-url https://download.pytorch.org/whl/rocm6.1
accelerate==0.27.2
aiofiles==23.2.1
altair==5.3.0
annotated-types==0.6.0
antlr4-python3-runtime==4.9.3
anyio==4.3.0
attrs==23.2.0
certifi==2024.2.2
charset-normalizer==3.3.2
click==8.1.7
contourpy==1.2.1
cycler==0.12.1
diffusers==0.26.3
dnspython==2.6.1
email_validator==2.1.1
exceptiongroup==1.2.1
fastapi==0.111.0
fastapi-cli==0.0.2
ffmpy==0.3.2
filelock==3.14.0
fonttools==4.51.0
fsspec==2024.3.1
gradio==4.20.0
gradio_client==0.11.0
h11==0.14.0
httpcore==1.0.5
httptools==0.6.1
httpx==0.27.0
huggingface-hub==0.23.0
idna==3.7
importlib_metadata==7.1.0
importlib_resources==6.4.0
invisible-watermark==0.2.0
Jinja2==3.1.4
jsonschema==4.22.0
jsonschema-specifications==2023.12.1
kiwisolver==1.4.5
markdown-it-py==3.0.0
MarkupSafe==2.1.5
matplotlib==3.8.4
mdurl==0.1.2
mpmath==1.3.0
networkx==3.3
numpy==1.26.4
omegaconf==2.3.0
opencv-python==4.9.0.80
orjson==3.10.3
packaging==24.0
pandas==2.2.2
pillow==10.2.0
psutil==5.9.8
pydantic==2.7.1
pydantic_core==2.18.2
pydub==0.25.1
Pygments==2.18.0
pyparsing==3.1.2
python-dateutil==2.9.0.post0
python-dotenv==1.0.1
python-multipart==0.0.9
pytorch-triton-rocm
pytz==2024.1
PyWavelets==1.6.0
PyYAML==6.0.1
referencing==0.35.1
regex==2024.4.28
requests==2.31.0
rich==13.7.1
rpds-py==0.18.1
ruff==0.4.3
safetensors==0.4.3
semantic-version==2.10.0
shellingham==1.5.4
six==1.16.0
sniffio==1.3.1
spaces==0.24.0
starlette==0.37.2
sympy==1.12
timm==0.9.10
tokenizers==0.15.2
tomlkit==0.12.0
toolz==0.12.1
torch
torchvision
tqdm==4.66.4
transformers==4.38.1
typer==0.12.3
typing_extensions==4.11.0
tzdata==2024.1
ujson==5.9.0
urllib3==2.2.1
uvicorn==0.29.0
uvloop==0.19.0
watchfiles==0.21.0
websockets==11.0.3
zipp==3.18.1
EOF

    pip install -r custom_requirements.txt

    sed -i 's/demo.queue(max_size=20).launch(debug=IS_COLAB, share=IS_COLAB)/demo.queue(max_size=20).launch(debug=IS_COLAB, share=False, server_name="0.0.0.0")/' app.py

    tee --append run.sh <<EOF
export HSA_OVERRIDE_GFX_VERSION=11.0.0
source $installation_path/animagine-xl-3.1/.venv/bin/activate
python3 ./app.py
EOF
    chmod +x run.sh
}

# Artist
install_artist() {
    if ! command -v python3.12 &> /dev/null; then
        echo "Install Python 3.12 first"
        exit 1
    fi

    mkdir -p $installation_path
    cd $installation_path
    rm -rf Artist
    git clone https://github.com/songrise/Artist.git 
    cd Artist
    git checkout dcc252adb81e7e57e1763758cf57b8c865dbe1bb
    python3.12 -m venv .venv --prompt Artist
    source .venv/bin/activate

    tee --append custom_requirements.txt <<EOF
--extra-index-url https://download.pytorch.org/whl/rocm6.1
aiofiles==23.2.1
annotated-types==0.7.0
antlr4-python3-runtime==4.9.3
anyio==4.4.0
certifi==2024.7.4
charset-normalizer==3.3.2
click==8.1.7
clip==0.2.0
contourpy==1.2.1
cycler==0.12.1
diffusers==0.26.3
einops==0.8.0
fastapi==0.112.0
ffmpy==0.4.0
filelock==3.15.4
fonttools==4.53.1
fsspec==2024.6.1
gradio==4.41.0
gradio_client==1.3.0
h11==0.14.0
httpcore==1.0.5
httpx==0.27.0
huggingface-hub==0.24.5
idna==3.7
importlib_metadata==8.2.0
importlib_resources==6.4.0
Jinja2==3.1.4
kiwisolver==1.4.5
markdown-it-py==3.0.0
MarkupSafe==2.1.5
matplotlib==3.9.1.post1
mdurl==0.1.2
mpmath==1.3.0
networkx==3.3
numpy==2.0.1
omegaconf==2.3.0
orjson==3.10.6
packaging==24.1
pandas==2.2.2
pillow==10.4.0
pydantic==2.8.2
pydantic_core==2.20.1
pydub==0.25.1
Pygments==2.18.0
pyparsing==3.1.2
python-dateutil==2.9.0.post0
python-multipart==0.0.9
pytorch-triton-rocm==3.0.0
pytz==2024.1
PyYAML==6.0.2
regex==2024.7.24
requests==2.32.3
rich==13.7.1
ruff==0.5.6
safetensors==0.4.4
semantic-version==2.10.0
setuptools==72.1.0
shellingham==1.5.4
six==1.16.0
sniffio==1.3.1
starlette==0.37.2
sympy==1.13.1
tokenizers==0.19.1
tomlkit==0.12.0
torch==2.4.0+rocm6.1
torchvision==0.19.0+rocm6.1
tqdm==4.66.5
typer==0.12.3
typing_extensions==4.12.2
tzdata==2024.1
urllib3==2.2.2
uvicorn==0.30.5
websockets==12.0
zipp==3.19.2
EOF

    pip install -r custom_requirements.txt

    pip install git+https://github.com/huggingface/transformers.git@4fdc7020b227ab606a9b68470a798824232c17ca --extra-index-url https://download.pytorch.org/whl/rocm6.1

    sed -i 's/app.launch()/app.launch(share=False, server_name="0.0.0.0")/' injection_main.py

    tee --append run.sh <<EOF
export HSA_OVERRIDE_GFX_VERSION=11.0.0
source $installation_path/Artist/.venv/bin/activate
python injection_main.py --mode app
EOF
    chmod +x run.sh
}

# Cinemo
install_cinemo() {
    if ! command -v python3.12 &> /dev/null; then
        echo "Install Python 3.12 first"
        exit 1
    fi

    mkdir -p $installation_path
    cd $installation_path
    rm -rf Cinemo
    git clone https://huggingface.co/spaces/maxin-cn/Cinemo
    git checkout 2bf400b88528c0ff3aedeaac064ca98b42acf2ca
    cd Cinemo
    python3.12 -m venv .venv --prompt Cinemo
    source .venv/bin/activate

    tee --append custom_requirements.txt <<EOF
--extra-index-url https://download.pytorch.org/whl/rocm6.1
absl-py==2.1.0
accelerate==0.33.0
aiofiles==23.2.1
annotated-types==0.7.0
antlr4-python3-runtime==4.9.3
anyio==4.4.0
av==12.3.0
beautifulsoup4==4.12.3
certifi==2024.7.4
charset-normalizer==3.3.2
click==8.1.7
contourpy==1.2.1
cycler==0.12.1
decord==0.6.0
diffusers==0.24.0
einops==0.8.0
fastapi==0.112.0
ffmpy==0.4.0
filelock==3.13.1
fonttools==4.53.1
fsspec==2024.2.0
ftfy==6.2.0
gradio==4.40.0
gradio_client==1.2.0
grpcio==1.65.4
h11==0.14.0
httpcore==1.0.5
httpx==0.27.0
huggingface-hub==0.24.5
idna==3.7
imageio==2.34.2
imageio-ffmpeg==0.5.1
importlib_metadata==8.2.0
importlib_resources==6.4.0
Jinja2==3.1.3
kiwisolver==1.4.5
lazy_loader==0.4
Markdown==3.6
markdown-it-py==3.0.0
MarkupSafe==2.1.5
matplotlib==3.9.1
mdurl==0.1.2
mpmath==1.3.0
networkx==3.2.1
numpy==1.26.3
omegaconf==2.3.0
orjson==3.10.6
packaging==24.1
pandas==2.2.2
pillow==10.2.0
protobuf==4.25.4
psutil==5.9.8
pydantic==2.8.2
pydantic_core==2.20.1
pydub==0.25.1
Pygments==2.18.0
pyparsing==3.1.2
python-dateutil==2.9.0.post0
python-multipart==0.0.9
pytorch-triton-rocm==3.0.0
pytz==2024.1
PyYAML==6.0.1
regex==2024.7.24
requests==2.32.3
rich==13.7.1
ruff==0.5.6
safetensors==0.4.3
scikit-image==0.24.0
scipy==1.14.0
semantic-version==2.10.0
sentencepiece==0.2.0
setuptools==70.0.0
shellingham==1.5.4
six==1.16.0
sniffio==1.3.1
soupsieve==2.5
spaces==0.29.2
starlette==0.37.2
sympy==1.12
tensorboard==2.17.0
tensorboard-data-server==0.7.2
tifffile==2024.7.24
timm==1.0.8
tokenizers==0.19.1
tomlkit==0.12.0
torch==2.4.0+rocm6.1
torch-dct==0.1.6
torchaudio==2.4.0+rocm6.1
torchvision==0.19.0+rocm6.1
tqdm==4.66.5
transformers==4.43.3
typer==0.12.3
typing_extensions==4.9.0
tzdata==2024.1
urllib3==2.2.2
uvicorn==0.30.5
wcwidth==0.2.13
websockets==12.0
Werkzeug==3.0.3
zipp==3.19.2
EOF

    pip install -r custom_requirements.txt

    sed -i 's/demo.launch(debug=False, share=True)/demo.launch(debug=False, share=False, server_name="0.0.0.0")/' demo.py

    tee --append run.sh <<EOF
export HSA_OVERRIDE_GFX_VERSION=11.0.0
source $installation_path/Cinemo/.venv/bin/activate
python3 ./demo.py
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
    git checkout 5b8681ea9793f98c8f7bbb7a802d2193306cbec1

    mv ./start.sh ./run.sh

    # Default config
    cd ./default
    sed -i 's/listen: false/listen: true/' config.yaml
    sed -i 's/whitelistMode: true/whitelistMode: false/' config.yaml
    sed -i 's/basicAuthMode: false/basicAuthMode: true/' config.yaml
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
    git checkout 82a973c04367123ae98bd9abdf80d9eda9b910e2
            
    tee --append webui-user.sh <<EOF
export HSA_OVERRIDE_GFX_VERSION=11.0.0
python_cmd="python3.11"
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export TORCH_COMMAND="pip install --pre torch==2.4.0+rocm6.1  torchvision==0.19.0+rocm6.1 --extra-index-url https://download.pytorch.org/whl/rocm6.1"
export COMMANDLINE_ARGS="--api --listen"
#export CUDA_VISIBLE_DEVICES="1"
EOF
    mv ./webui.sh ./run.sh
    chmod +x run.sh
}

# ComfyUI
install_comfyui() {
    if ! command -v python3.12 &> /dev/null; then
        echo "Install Python 3.12 first"
        exit 1
    fi

    mkdir -p $installation_path
    cd $installation_path
    rm -rf ComfyUI
    git clone https://github.com/comfyanonymous/ComfyUI.git
    cd ComfyUI
    git checkout b643eae08b7f0c8eb69b77bd61e31009bfb325b9
    
    python3.12 -m venv .venv --prompt ComfyUI
    source .venv/bin/activate

    tee --append custom_requirements.txt <<EOF
--extra-index-url https://download.pytorch.org/whl/rocm6.1
aiohttp==3.9.5
aiosignal==1.3.1
attrs==23.2.0
aura-sr==0.0.4
certifi==2024.7.4
cffi==1.16.0
charset-normalizer==3.3.2
contourpy==1.2.1
cv==1.0.0
cycler==0.12.1
einops==0.8.0
filelock==3.13.1
fonttools==4.53.1
frozenlist==1.4.1
fsspec==2024.2.0
huggingface-hub==0.23.4
idna==3.7
Jinja2==3.1.3
kiwisolver==1.4.5
kornia==0.7.3
kornia_rs==0.1.4
MarkupSafe==2.1.5
matplotlib==3.9.1
mpmath==1.3.0
multidict==6.0.5
networkx==3.2.1
numpy==1.26.3
opencv-python==4.10.0.84
packaging==24.1
pillow==10.2.0
psutil==6.0.0
pycparser==2.22
pyparsing==3.1.2
python-dateutil==2.9.0.post0
pytorch-triton-rocm==3.0.0
PyYAML==6.0.1
regex==2024.5.15
requests==2.32.3
safetensors==0.4.3
scipy==1.14.0
sentencepiece==0.2.0
setuptools==70.0.0
six==1.16.0
soundfile==0.12.1
spandrel==0.3.4
sympy==1.12
tokenizers==0.15.2
torch==2.4.0+rocm6.1
torchaudio==2.4.0+rocm6.1
torchsde==0.2.6
torchvision==0.19.0+rocm6.1
tqdm==4.66.4
trampoline==0.1.2
transformers==4.36.0
typing_extensions==4.9.0
urllib3==2.2.2
yarl==1.9.4
EOF

    pip install -r custom_requirements.txt

    git clone https://github.com/biegert/ComfyUI-CLIPSeg.git
    cd ComfyUI-CLIPSeg
    git checkout 7f38951269888407de45fb934958c30c27704fdb
    mv ./custom_nodes/clipseg.py $installation_path/ComfyUI/custom_nodes
    cd $installation_path/ComfyUI
    rm -rf ComfyUI-CLIPSeg

    # Aura
    cd $installation_path/ComfyUI
    git clone --no-checkout https://huggingface.co/fal/AuraFlow-v0.3
    cd AuraFlow-v0.3
    git sparse-checkout init --cone
    git sparse-checkout set aura_flow_0.3.safetensors
    git checkout 2cd8588f04c886002be4571697d84654a50e3af3
    mv ./aura_flow_0.3.safetensors $installation_path/ComfyUI/models/checkpoints
    rm -rf $installation_path/ComfyUI/AuraFlow-v0.3

    cd $installation_path/ComfyUI/custom_nodes
    git clone https://github.com/alexisrolland/ComfyUI-AuraSR
    cd ComfyUI-AuraSR
    git checkout f839d729c201d805ad0c1a8b0978d6da8105d1cd

    # Flux
    cd $installation_path/ComfyUI
    git clone https://huggingface.co/Comfy-Org/flux1-schnell
    cd flux1-schnell
    git checkout f2808ab17fe9ff81dcf89ed0301cf644c281be0a
    mv ./flux1-schnell-fp8.safetensors $installation_path/ComfyUI/models/checkpoints
    cd .. && rm -rf flux-fp8

    cd $installation_path/ComfyUI

    tee --append run.sh <<EOF
export HSA_OVERRIDE_GFX_VERSION=11.0.0
source $installation_path/ComfyUI/.venv/bin/activate
python3 ./main.py --listen
EOF
    chmod +x run.sh
}

# AudioCraft
install_audiocraft() {
    if ! command -v python3.12 &> /dev/null; then
        echo "Install Python 3.12 first"
        exit 1
    fi

    mkdir -p $installation_path
    cd $installation_path
    rm -rf audiocraft
    git clone https://github.com/facebookresearch/audiocraft.git
    cd audiocraft
    git checkout adf0b04a4452f171970028fcf80f101dd5e26e19
    python3.12 -m venv .venv --prompt AudioCraft
    source .venv/bin/activate
            
    tee --append custom_requirements.txt <<EOF
--extra-index-url https://download.pytorch.org/whl/rocm6.1
aiofiles==23.2.1
altair==5.3.0
annotated-types==0.6.0
antlr4-python3-runtime==4.9.3
anyio==4.3.0
attrs==23.2.0
audioread==3.0.1
av==12.0.0
blis==0.7.11
catalogue==2.0.10
certifi==2024.2.2
cffi==1.16.0
charset-normalizer==3.3.2
click==8.1.7
cloudpathlib==0.16.0
cloudpickle==3.0.0
colorama==0.4.6
colorlog==6.8.2
confection==0.1.4
contourpy==1.2.1
cycler==0.12.1
cymem==2.0.8
decorator==5.1.1
demucs==4.0.1
docopt==0.6.2
dora_search==0.1.12
einops==0.8.0
encodec==0.1.1
exceptiongroup==1.2.1
fastapi==0.110.3
ffmpy==0.3.2
filelock==3.14.0
flashy==0.0.2
fonttools==4.51.0
fsspec==2024.3.1
gradio==4.26.0
gradio_client==0.15.1
h11==0.14.0
httpcore==1.0.5
httpx==0.27.0
huggingface-hub==0.23.0
hydra-colorlog==1.2.0
hydra-core==1.3.2
idna==3.7
importlib_resources==6.4.0
Jinja2==3.1.4
joblib==1.4.2
jsonschema==4.22.0
jsonschema-specifications==2023.12.1
julius==0.2.7
kiwisolver==1.4.5
lameenc==1.7.0
langcodes==3.4.0
language_data==1.2.0
lazy_loader==0.4
librosa==0.10.2
lightning-utilities==0.11.2
llvmlite==0.42.0
marisa-trie==1.1.1
markdown-it-py==3.0.0
MarkupSafe==2.1.5
matplotlib==3.8.4
mdurl==0.1.2
mpmath==1.3.0
msgpack==1.0.8
murmurhash==1.0.10
networkx==3.3
num2words==0.5.13
numba==0.59.1
numpy==1.26.4
omegaconf==2.3.0
openunmix==1.3.0
orjson==3.10.3
packaging==24.0
pandas==2.2.2
pillow==10.3.0
platformdirs==4.2.1
pooch==1.8.1
preshed==3.0.9
pretty-errors==1.2.25
protobuf==5.26.1
pycparser==2.22
pydantic==2.7.1
pydantic_core==2.18.2
pydub==0.25.1
Pygments==2.18.0
pyparsing==3.1.2
python-dateutil==2.9.0.post0
python-multipart==0.0.9
pytorch-triton-rocm==3.0.0
pytz==2024.1
PyYAML==6.0.1
referencing==0.35.1
regex==2024.4.28
requests==2.31.0
retrying==1.3.4
rich==13.7.1
rpds-py==0.18.1
ruff==0.4.3
safetensors==0.4.3
scikit-learn==1.4.2
scipy==1.13.0
semantic-version==2.10.0
sentencepiece==0.2.0
shellingham==1.5.4
six==1.16.0
smart-open==6.4.0
sniffio==1.3.1
soundfile==0.12.1
soxr==0.3.7
spacy==3.7.4
spacy-legacy==3.0.12
spacy-loggers==1.0.5
srsly==2.4.8
starlette==0.37.2
submitit==1.5.1
sympy==1.12
thinc==8.2.3
threadpoolctl==3.5.0
tokenizers==0.19.1
tomlkit==0.12.0
toolz==0.12.1
torch==2.4.0+rocm6.1
torchaudio==2.4.0+rocm6.1
torchmetrics==1.4.0
torchvision==0.19.0+rocm6.1
tqdm==4.66.4
transformers==4.40.2
treetable==0.2.5
typer==0.9.4
typing_extensions==4.11.0
tzdata==2024.1
urllib3==2.2.1
uvicorn==0.29.0
wasabi==1.1.2
weasel==0.3.4
websockets==11.0.3
xformers==0.0.27.post2
EOF

    pip install -r custom_requirements.txt

    tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export CUDA_VISIBLE_DEVICES=0
source $installation_path/audiocraft/.venv/bin/activate
python -m demos.musicgen_app --listen 0.0.0.0
EOF
    chmod +x run.sh
}

install_whisperspeech_web_ui(){
    if ! command -v python3.12 &> /dev/null; then
        echo "Install Python 3.12 first"
        exit 1
    fi

    mkdir -p $installation_path
    cd $installation_path
    rm -rf whisperspeech-webui
    git clone https://github.com/Mateusz-Dera/whisperspeech-webui.git
    cd whisperspeech-webui
    git checkout c295d6b5503465067ea4fe24b2b20214fa827d94
    python3.12 -m venv .venv --prompt WhisperSpeech
    source .venv/bin/activate

    pip install -r requirements_rocm_6.1.txt
    pip install git+https://github.com/ROCmSoftwarePlatform/flash-attention.git@2554f490101742ccdc56620a938f847f61754be6

    tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export CUDA_VISIBLE_DEVICES=0
source $installation_path/whisperspeech-webui/.venv/bin/activate
python3 webui.py
EOF
    chmod u+x run.sh
}

install_melotts(){
    if ! command -v python3.12 &> /dev/null; then
        echo "Install Python 3.12 first"
        exit 1
    fi

    mkdir -p $installation_path
    cd $installation_path
    rm -rf MeloTTS
    git clone https://github.com/myshell-ai/MeloTTS
    cd MeloTTS
    git checkout 5b538481e24e0d578955be32a95d88fcbde26dc8
    python3.12 -m venv .venv --prompt MeloTTS
    source .venv/bin/activate

    rm requirements.txt

    tee --append requirements.txt <<EOF
absl-py==2.1.0
aiofiles==23.2.1
altair==5.3.0
annotated-types==0.7.0
anyascii==0.3.2
anyio==4.4.0
attrs==23.2.0
audioread==3.0.1
Babel==2.15.0
boto3==1.34.131
botocore==1.34.131
cached_path==1.6.3
cachetools==5.3.3
certifi==2024.6.2
cffi==1.16.0
charset-normalizer==3.3.2
click==8.1.7
cn2an==0.5.22
contourpy==1.2.1
cycler==0.12.1
dateparser==1.1.8
decorator==5.1.1
Deprecated==1.2.14
Distance==0.1.3
dnspython==2.6.1
docopt==0.6.2
email_validator==2.2.0
eng_to_ipa==0.0.2
fastapi==0.111.0
fastapi-cli==0.0.4
ffmpy==0.3.2
filelock==3.13.4
fonttools==4.53.0
fsspec==2024.6.0
fugashi==1.3.0
g2p-en==2.1.0
g2pkk==0.1.2
google-api-core==2.19.0
google-auth==2.30.0
google-cloud-core==2.4.1
google-cloud-storage==2.17.0
google-crc32c==1.5.0
google-resumable-media==2.7.1
googleapis-common-protos==1.63.1
gradio==4.36.1
gradio_client==1.0.1
grpcio==1.64.1
gruut==2.2.3
gruut-ipa==0.13.0
gruut_lang_de==2.0.0
gruut_lang_en==2.0.0
gruut_lang_es==2.0.0
gruut_lang_fr==2.0.2
h11==0.14.0
httpcore==1.0.5
httptools==0.6.1
httpx==0.27.0
huggingface-hub==0.23.4
idna==3.7
importlib_resources==6.4.0
inflect==7.0.0
jaconv==0.3.4
jamo==0.4.1
jieba==0.42.1
Jinja2==3.1.4
jmespath==1.0.1
joblib==1.4.2
jsonlines==1.2.0
jsonschema==4.22.0
jsonschema-specifications==2023.12.1
kiwisolver==1.4.5
langid==1.1.6
librosa==0.9.1
llvmlite==0.43.0
loguru==0.7.2
Markdown==3.6
markdown-it-py==3.0.0
MarkupSafe==2.1.5
matplotlib==3.9.0
mdurl==0.1.2
mecab-python3==1.0.5
mpmath==1.3.0
networkx==2.8.8
nltk==3.8.1
num2words==0.5.12
numba==0.60.0
numpy==1.26.4
orjson==3.10.5
packaging==24.1
pandas==2.2.2
pillow==10.3.0
plac==1.4.3
platformdirs==4.2.2
pooch==1.8.2
proces==0.1.7
proto-plus==1.24.0
protobuf==4.25.3
pyasn1==0.6.0
pyasn1_modules==0.4.0
pycparser==2.22
pydantic==2.7.4
pydantic_core==2.18.4
pydub==0.25.1
Pygments==2.18.0
pykakasi==2.2.1
pyparsing==3.1.2
pypinyin==0.50.0
python-crfsuite==0.9.10
python-dateutil==2.9.0.post0
python-dotenv==1.0.1
python-multipart==0.0.9
pytorch-triton-rocm==3.0.0
pytz==2024.1
PyYAML==6.0.1
referencing==0.35.1
regex==2024.5.15
requests==2.32.3
resampy==0.4.3
rich==13.7.1
rpds-py==0.18.1
rsa==4.9
ruff==0.4.10
s3transfer==0.10.1
safetensors==0.4.3
scikit-learn==1.5.0
scipy==1.13.1
semantic-version==2.10.0
setuptools==70.1.0
shellingham==1.5.4
six==1.16.0
sniffio==1.3.1
soundfile==0.12.1
starlette==0.37.2
sympy==1.12.1
tensorboard==2.16.2
tensorboard-data-server==0.7.2
threadpoolctl==3.5.0
tokenizers==0.19.1
tomlkit==0.12.0
toolz==0.12.1
torch==2.4.0+rocm6.1
torchaudio==2.4.0+rocm6.1
torchvision==0.19.0+rocm6.1
tqdm==4.66.4
transformers==4.41.2
txtsplit==1.0.0
typer==0.12.3
typing_extensions==4.12.2
tzdata==2024.1
tzlocal==5.2
ujson==5.10.0
Unidecode==1.3.7
unidic==1.1.0
unidic-lite==1.0.8
urllib3==2.2.2
uvicorn==0.30.1
uvloop==0.19.0
wasabi==0.10.1
watchfiles==0.22.0
websockets==11.0.3
Werkzeug==3.0.3
wrapt==1.16.0
EOF

    pip install --upgrade pip
    pip install -r requirements.txt --extra-index-url https://download.pytorch.org/whl/rocm6.1
    pip install -e . --extra-index-url https://download.pytorch.org/whl/rocm6.1
    python -m unidic download

    tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export CUDA_VISIBLE_DEVICES=0
source $installation_path/MeloTTS/.venv/bin/activate
python melo/app.py -h 0.0.0.0
EOF
    chmod u+x run.sh
}

install_triposr(){
    if ! command -v python3.12 &> /dev/null; then
        echo "Install Python 3.12 first"
        exit 1
    fi

    mkdir -p $installation_path
    cd $installation_path
    rm -rf TripoSR
    git clone https://github.com/VAST-AI-Research/TripoSR
    cd TripoSR
    git checkout d26e33181947bbbc4c6fc0f5734e1ec6c080956e
    python3.12 -m venv .venv --prompt TripoSR
    source .venv/bin/activate

    pip install -U wheel

    tee --append custom_requirements.txt <<EOF
--extra-index-url https://download.pytorch.org/whl/rocm6.1
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
pytorch-triton-rocm==3.0.0
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
setuptools==72.1.0
shellingham==1.5.4
six==1.16.0
sniffio==1.3.1
starlette==0.36.3
sympy==1.12
tifffile==2024.2.12
tokenizers==0.14.1
tomlkit==0.12.0
toolz==0.12.1
torch==2.4.0+rocm6.1
torchaudio==2.4.0+rocm6.1
torchvision==0.19.0+rocm6.1
tqdm==4.66.2
transformers==4.35.0
trimesh==4.0.5
typer==0.9.0
typing_extensions==4.8.0
tzdata==2024.1
urllib3==2.2.1
uvicorn==0.27.1
websockets==11.0.3
wheel==0.43.0
EOF

    pip install -r custom_requirements.txt
    
    pip install git+https://github.com/tatsy/torchmcubes.git@3aef8afa5f21b113afc4f4ea148baee850cbd472

    tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export CUDA_VISIBLE_DEVICES=0
source $installation_path/TripoSR/.venv/bin/activate
python3 gradio_app.py --listen
EOF
    chmod u+x run.sh
}

install_exllamav2(){
    if ! command -v python3.12 &> /dev/null; then
        echo "Install Python 3.12 first"
        exit 1
    fi

    mkdir -p $installation_path
    cd $installation_path
    rm -rf exllamav2
    git clone https://github.com/turboderp/exllamav2
    cd exllamav2
    git checkout 40e37f494488d930bb196b6e01d9c5c8a64456e8
    python3.12 -m venv .venv --prompt ExLlamaV2
    source .venv/bin/activate

    tee --append custom_requirements.txt <<EOF
--extra-index-url https://download.pytorch.org/whl/rocm6.1
certifi==2024.6.2
charset-normalizer==3.3.2
cramjam==2.8.3
fastparquet==2024.5.0
filelock==3.15.4
fsspec==2024.6.1
huggingface-hub==0.23.4
idna==3.7
Jinja2==3.1.4
markdown-it-py==3.0.0
MarkupSafe==2.1.5
mdurl==0.1.2
mpmath==1.3.0
networkx==3.3
ninja==1.11.1.1
numpy==1.26.4
packaging==24.1
pandas==2.2.2
pillow==10.2.0
Pygments==2.18.0
python-dateutil==2.9.0.post0
pytorch-triton-rocm==3.0.0
pytz==2024.1
PyYAML==6.0.1
regex==2024.5.15
requests==2.32.3
rich==13.7.1
safetensors==0.4.3
sentencepiece==0.2.0
setuptools==70.1.1
six==1.16.0
sympy==1.12.1
tokenizers==0.19.1
torch==2.4.0+rocm6.1
torchaudio==2.4.0+rocm6.1
torchvision==0.19.0+rocm6.1
tqdm==4.66.4
typing_extensions==4.12.2
tzdata==2024.1
urllib3==2.2.2
websockets==12.0
wheel==0.43.0
EOF

pip install -r custom_requirements.txt
pip install . --extra-index-url https://download.pytorch.org/whl/rocm6.1
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
                                                backup_and_restore_file $installation_path/SillyTavern/data/default-user $installation_path/Backups/SillyTavern/data/default-user settings.json
                                                ;;
                                            2)
                                                # Backup characters
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/characters $installation_path/Backups/SillyTavern/data/default-user/characters
                                                ;;
                                            3)
                                                # Backup groups
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/groups $installation_path/Backups/SillyTavern/data/default-user/groups
                                                ;;
                                            4)
                                                # Backup worlds
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/worlds $installation_path/Backups/SillyTavern/data/default-user/worlds
                                                ;;
                                            5)
                                                # Backup chats
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/chats $installation_path/Backups/SillyTavern/data/default-user/chats
                                                ;;
                                            6)
                                                # Backup group chats
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/group\ chats $installation_path/Backups/SillyTavern/data/default-user/group\ chats
                                                ;;
                                            7)
                                                # Backup user avatars images
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/User\ Avatars $installation_path/Backups/SillyTavern/data/default-user/User\ Avatars
                                                ;;
                                            8)
                                                # Backup backgrounds images
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/backgrounds $installation_path/Backups/SillyTavern/data/default-user/backgrounds
                                                ;;
                                            9)
                                                # Backup themes
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/themes $installation_path/Backups/SillyTavern/data/default-user/themes
                                                ;;
                                            10)
                                                # Backup presets
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/TextGen\ Settings $installation_path/Backups/SillyTavern/data/default-user/TextGen\ Settings
                                                ;;
                                            11)
                                                # Backup context
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/context $installation_path/Backups/SillyTavern/data/default-user/context
                                                ;;
                                            12)
                                                # Backup instruct
                                                backup_and_restore $installation_path/SillyTavern/data/default-user/instruct $installation_path/Backups/SillyTavern/data/default-user/instruct
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
                                                backup_and_restore_file $installation_path/Backups/SillyTavern/data/default-user $installation_path/SillyTavern/data/default-user settings.json
                                                ;;
                                            2)
                                                # Restore characters
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/characters $installation_path/SillyTavern/data/default-user/characters
                                                ;;
                                            3)
                                                # Restore groups
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/groups $installation_path/SillyTavern/data/default-user/groups
                                                ;;
                                            4)
                                                # Restore worlds
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/worlds $installation_path/SillyTavern/data/default-user/worlds
                                                ;;
                                            5)
                                                # Restore chats
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/chats $installation_path/SillyTavern/data/default-user/chats
                                                ;;
                                            6)
                                                # Restore group chats
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/group\ chats $installation_path/SillyTavern/data/default-user/group\ chats
                                                ;;
                                            7)
                                                # Restore user avatars images
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/User\ Avatars $installation_path/SillyTavern/data/default-user/User\ Avatars
                                                ;;
                                            8)
                                                # Restore backgrounds images
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/backgrounds $installation_path/SillyTavern/data/default-user/backgrounds
                                                ;;
                                            9)
                                                # Restore themes
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/themes $installation_path/SillyTavern/data/default-user/themes
                                                ;;
                                            10)
                                                # Restore presets
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/TextGen\ Settings $installation_path/SillyTavern/data/default-user/TextGen\ Settings
                                                ;;
                                            11)
                                                # Restore context
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/context $installation_path/SillyTavern/data/default-user/context
                                                ;;
                                            12)
                                                # Restore instruct
                                                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/instruct $installation_path/SillyTavern/data/default-user/instruct
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
                    2)
                        # ComfyUI
                        second=true
                        while $second; do
                            choice=$(comfyui)
                            case $choice in
                                0)
                                    # Backup
                                    next=true
                                    while $next; do
                                        choice=$(comfyui_backup)
                                        case $choice in
                                            0)
                                                # Backup models
                                                backup_and_restore $installation_path/ComfyUI/models $installation_path/Backups/ComfyUI/models
                                                ;;
                                            *)
                                                next=false
                                                ;;
                                        esac
                                    done
                                    ;;
                                1)
                                    # Install
                                    install_comfyui
                                    ;;
                                2)
                                    # Restore
                                    next=true
                                    while $next; do
                                        choice=$(comfyui_restore)
                                        case $choice in
                                            0)
                                                # Restore models
                                                backup_and_restore $installation_path/Backups/ComfyUI/models $installation_path/ComfyUI/models
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
                    3)
                        # Artist
                        install_artist
                        ;;
                    *)
                        first=false
                        ;;
                esac
            done
            ;;
         4)
            # Video generation
            first=true
            while $first; do
            
                choice=$(video_generation)

                case $choice in
                    0)
                        # Cinemo
                        install_cinemo
                        ;;
                    *)
                        first=false
                        ;;
                esac
            done
            ;;
        5)
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
        6)
            # Voice generation
            first=true
            while $first; do
            
                choice=$(voice_generation)

                case $choice in
                    0)
                        # WhisperSpeech web UI
                        install_whisperspeech_web_ui
                        ;;
                    1)
                        # MeloTTS
                        install_melotts
                        ;;
                    *)
                        first=false
                        ;;
                esac
            done
            ;;
        7)
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
        8)
            # Tools
            first=true
            while $first; do
            
                choice=$(tools)

                case $choice in
                    0)
                        # ExLlamaV2
                        install_exllamav2
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
