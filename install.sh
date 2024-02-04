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

# Default installation path
default_installation_path="$HOME/AI"
# Global variable for installation path
installation_path="$default_installation_path"

if ! command -v whiptail &> /dev/null; then
    sudo apt-get update
    sudo apt-get -y install whiptail
fi

# Function to display the main menu
show_menu() {
    whiptail --title "Menu Example" --menu "Choose an option:" 15 100 6 \
    0 "Set installation path ($installation_path)" \
    1 "Install ROCm + basic packages" \
    2 "Stable Diffusion web UI" \
    3 "Text generation web UI" \
    4 "SillyTavern + Extras + Silero TTS" \
    5 "TTS Generation WebUI" \
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
            # Install ROCm
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
            echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/6.0 jammy main" \
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

            sudo apt-get install -y python3.10 python3.10-venv python3.10-dev python3.11 python3.11-venv python3.11-dev git git-lfs ffmpeg libstdc++-12-dev libtcmalloc-minimal4 python3 python3-venv python3-dev imagemagick libgl1 libglib2.0-0 amdgpu-dkms rocm-dev rocm-libs rocm-hip-sdk rocm-dkms rocm-libs libeigen3-dev

            sudo rm /etc/ld.so.conf.d/rocm.conf
            sudo tee --append /etc/ld.so.conf.d/rocm.conf <<EOF
/opt/rocm/lib
/opt/rocm/lib64
EOF
            sudo ldconfig
            ;;
        2)
            # Action for Option 2
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
            python3.11 -m venv .venv --prompt StableDiffusion
            source .venv/bin/activate
            
            tee --append webui-user.sh <<EOF
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export TORCH_COMMAND="pip install --pre torch==2.3.0.dev20240118+rocm6.0  torchvision==0.18.0.dev20240118+rocm5.7 --index-url https://download.pytorch.org/whl/nightly"
export COMMANDLINE_ARGS="--api"
#export CUDA_VISIBLE_DEVICES="1"
EOF
            mv ./webui.sh ./run.sh
            chmod +x run.sh
            ;;
        3)
            # Action for Option 3
            if ! command -v python3.11 &> /dev/null; then
                echo "Install Python 3.11 first"
                exit 1
            fi

            mkdir -p $installation_path
            cd $installation_path
            rm -rf text-generation-webui
            git clone https://github.com/oobabooga/text-generation-webui.git
            cd text-generation-webui
            git checkout 837bd888e4cf239094d9b1cabcc342266fee11c0
            python3.11 -m venv .venv --prompt TextGen
            source .venv/bin/activate

            tee --append custom_requirements.txt <<EOF
absl-py==2.1.0
accelerate==0.25.0
aiofiles==23.2.1
aiohttp==3.9.1
aiosignal==1.3.1
altair==5.2.0
annotated-types==0.6.0
anyio==4.2.0
appdirs==1.4.4
attrs==23.2.0
auto-gptq @ https://github.com/jllllll/AutoGPTQ/releases/download/v0.6.0/auto_gptq-0.6.0+rocm5.6-cp311-cp311-linux_x86_64.whl
cachetools==5.3.2
certifi==2022.12.7
chardet==5.2.0
charset-normalizer==2.1.1
click==8.1.7
cmake==3.28.1
colorama==0.4.6
coloredlogs==15.0.1
contourpy==1.2.0
cramjam==2.8.1
cycler==0.12.1
DataProperty==1.0.1
datasets==2.16.1
dill==0.3.7
diskcache==5.6.3
distro==1.9.0
docker-pycreds==0.4.0
einops==0.7.0
fastapi==0.109.0
fastparquet==2023.10.1
ffmpy==0.3.1
filelock==3.9.0
fonttools==4.47.2
frozenlist==1.4.1
fsspec==2023.10.0
gekko==1.0.6
gitdb==4.0.11
GitPython==3.1.41
google-auth==2.27.0
google-auth-oauthlib==1.2.0
gptq-for-llama @ https://github.com/jllllll/GPTQ-for-LLaMa-CUDA/releases/download/0.1.1/gptq_for_llama-0.1.1+rocm5.6-cp311-cp311-linux_x86_64.whl
gradio==3.50.2
gradio_client==0.6.1
grpcio==1.60.0
h11==0.14.0
hqq==0.1.2
httpcore==1.0.2
httpx==0.26.0
huggingface-hub==0.20.3
humanfriendly==10.0
idna==3.4
importlib-resources==6.1.1
Jinja2==3.1.2
joblib==1.3.2
jsonlines==4.0.0
jsonschema==4.21.1
jsonschema-specifications==2023.12.1
kiwisolver==1.4.5
lit==15.0.7
llama_cpp_python @ https://github.com/oobabooga/llama-cpp-wheels/releases/download/cpu/llama_cpp_python-0.2.31+cpuavx2-cp311-cp311-manylinux_2_31_x86_64.whl
llama_cpp_python_cuda @ https://github.com/oobabooga/llama-cpp-wheels/releases/download/rocm/llama_cpp_python_cuda-0.2.31+rocm5.6.1-cp311-cp311-manylinux_2_31_x86_64.whl
lm-eval==0.3.0
Markdown==3.5.2
markdown-it-py==3.0.0
MarkupSafe==2.1.3
matplotlib==3.8.2
mbstrdecoder==1.1.3
mdurl==0.1.2
mpmath==1.2.1
multidict==6.0.4
multiprocess==0.70.15
networkx==3.0rc1
ninja==1.11.1.1
nltk==3.8.1
numexpr==2.9.0
numpy==1.24.4
oauthlib==3.2.2
openai==1.10.0
optimum==1.16.2
orjson==3.9.12
packaging==22.0
pandas==2.2.0
pathvalidate==3.2.0
peft==0.7.1
pillow==10.2.0
portalocker==2.8.2
protobuf==4.23.4
psutil==5.9.8
pyarrow==15.0.0
pyarrow-hotfix==0.6
pyasn1==0.5.1
pyasn1-modules==0.3.0
pybind11==2.11.1
pycountry==23.12.11
pydantic==2.5.3
pydantic_core==2.14.6
pydub==0.25.1
Pygments==2.17.2
pyparsing==3.1.1
pytablewriter==1.2.0
python-dateutil==2.8.2
python-multipart==0.0.6
pytorch-triton==3.0.0+901819d2b6
pytorch-triton-rocm==2.2.0+dafe145982
pytz==2023.3.post1
PyYAML==6.0.1
referencing==0.32.1
regex==2023.12.25
requests==2.28.1
requests-oauthlib==1.3.1
rich==13.7.0
rouge==1.0.1
rouge-score==0.1.2
rpds-py
rsa==4.9
sacrebleu==1.5.0
safetensors==0.4.1
scikit-learn==1.4.0
scipy==1.12.0
semantic-version==2.10.0
sentencepiece==0.1.99
sentry-sdk==1.39.2
setproctitle==1.3.3
six==1.16.0
smmap==5.0.1
sniffio==1.3.0
SpeechRecognition==3.10.1
sqlitedict==2.1.0
sse-starlette==2.0.0
starlette==0.35.1
sympy==1.11.1
tabledata==1.3.3
tcolorpy==0.1.4
tensorboard==2.15.1
tensorboard-data-server==0.7.2
termcolor==2.4.0
threadpoolctl==3.2.0
tiktoken==0.5.2
timm==0.9.12
tokenizers==0.15.1
toolz==0.12.1
torch==2.3.0.dev20240118+rocm6.0
torchaudio==2.2.0.dev20240118+rocm5.7
torchdata==0.7.1.dev20240117+cpu
torchtext==0.17.0.dev20240118+cpu
torchvision==0.18.0.dev20240118+rocm5.7
tqdm==4.64.1
tqdm-multiprocess==0.0.11
transformers==4.37.1
triton==2.1.0
typepy==1.3.2
typing_extensions==4.8.0
tzdata==2023.4
urllib3==1.26.13
uvicorn==0.27.0
wandb==0.16.2
websockets==11.0.3
Werkzeug==3.0.1
xxhash==3.4.1
yarl==1.9.4
zstandard==0.22.0
EOF
            cd $installation_path/text-generation-webui
            pip install --pre -r custom_requirements.txt --extra-index-url https://download.pytorch.org/whl/nightly

            # cd $installation_path/text-generation-webui
            git clone https://github.com/arlo-phoenix/bitsandbytes-rocm-5.6.git
            cd bitsandbytes-rocm-5.6
            git checkout 62353b0200b8557026c176e74ac48b84b953a854            
            make hip ROCM_TARGET=gfx1100 ROCM_HOME=/opt/rocm-6.0.0/
            pip install . --extra-index-url https://download.pytorch.org/whl/nightly

            cd $installation_path/text-generation-webui
            git clone https://github.com/ROCmSoftwarePlatform/flash-attention.git
            cd flash-attention
            git checkout 68aac13d3b3296d13062ab3ff40fe58d5e7b3023
            pip install .

            cd $installation_path/text-generation-webui
            git clone https://github.com/turboderp/exllamav2 repositories/exllamav2
            cd repositories/exllamav2
            git checkout 8be8867548d3dc88e4e6f489cc31d3177c94bd8b
            pip install . --index-url https://download.pytorch.org/whl/nightly

            cd $installation_path/text-generation-webui
            tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export CUDA_VISIBLE_DEVICES=0
source $installation_path/text-generation-webui/.venv/bin/activate
python server.py --api --listen --loader=exllamav2 --extensions sd_api_pictures send_pictures gallery
EOF
            chmod u+x run.sh
            ;;
        4)
            # Basic
            if ! command -v python3.11 &> /dev/null; then
                echo "Install Python 3.11 first"
                exit 1
            fi
            sudo apt-get update
            sudo apt-get -y install snapd build-essential libgtk-3-dev
            sudo snap install node --classic
            mkdir -p $installation_path
            cd $installation_path
            rm -Rf SillyTavern
            git clone https://github.com/SillyTavern/SillyTavern.git
            cd SillyTavern
            git checkout e3ccaf70a10b862113f9bad8ae039fc7ce6570df
            mv ./start.sh ./run.sh

            # Default config
            cd ./default
            sed -i 's/listen: false/listen: true/' config.yaml
            sed -i 's/whitelistMode: true/whitelistMode: false/' config.yaml
            sed -i 's/basicAuthMode: false/basicAuthMode: true/' config.yaml

            # Extras
            cd $installation_path

            rm -Rf SillyTavern-extras
            git clone https://github.com/SillyTavern/SillyTavern-extras.git
            cd SillyTavern-extras
            git checkout 9fae328a3908bfa871573e4aa41f668e2c441460
            
            python3.11 -m venv .venv --prompt SillyTavern-extras
            source .venv/bin/activate

            tee --append custom_requirements.txt <<EOF
accelerate==0.26.1
aiohttp==3.9.1
aiosignal==1.3.1
annotated-types==0.6.0
anyio==4.2.0
asgiref==3.7.2
attrs==23.2.0
backoff==2.2.1
bcrypt==4.1.2
black==24.1a1
blinker==1.7.0
Brotli==1.1.0
build==1.0.3
cachetools==5.3.2
certifi==2023.7.22
cffi==1.16.0
charset-normalizer==3.3.2
chroma-hnswlib==0.7.3
chromadb==0.4.22
click==8.1.7
colorama==0.4.6
coloredlogs==15.0.1
contourpy==1.2.0
cycler==0.12.1
Deprecated==1.2.14
diffusers==0.25.0
edge-tts==6.1.9
fastapi==0.109.0
filelock==3.13.1
Flask==3.0.0
flask-cloudflared==0.0.14
Flask-Compress==1.14
Flask-Cors==4.0.0
flatbuffers==23.5.26
fonttools==4.47.2
frozenlist==1.4.1
fsspec==2023.12.2
google-auth==2.26.2
googleapis-common-protos==1.62.0
grpcio==1.60.0
h11==0.14.0
httptools==0.6.1
huggingface-hub==0.20.2
humanfriendly==10.0
idna==3.6
importlib-metadata==6.11.0
importlib-resources==6.1.1
itsdangerous==2.1.2
Jinja2==3.1.3
joblib==1.3.2
kiwisolver==1.4.5
kubernetes==29.0.0
llvmlite==0.42.0rc1
loguru==0.7.2
Markdown==3.5.2
MarkupSafe==2.1.3
matplotlib==3.8.2
mmh3==4.1.0
monotonic==1.6
more-itertools==10.2.0
mpmath==1.3.0
multidict==6.0.4
mypy-extensions==1.0.0
networkx==3.2.1
nltk==3.8.1
numba==0.59.0rc1
numpy==1.26.3
oauthlib==3.2.2
onnxruntime==1.16.3
openai-whisper==20231117
opentelemetry-api==1.22.0
opentelemetry-exporter-otlp-proto-common==1.22.0
opentelemetry-exporter-otlp-proto-grpc==1.22.0
opentelemetry-instrumentation==0.43b0
opentelemetry-instrumentation-asgi==0.43b0
opentelemetry-instrumentation-fastapi==0.43b0
opentelemetry-proto==1.22.0
opentelemetry-sdk==1.22.0
opentelemetry-semantic-conventions==0.43b0
opentelemetry-util-http==0.43b0
outcome==1.3.0.post0
overrides==7.4.0
packaging==23.2
pyasn1-modules==0.3.0
pycparser==2.21
pydantic==2.5.3
pydantic_core==2.14.6
pydub==0.25.1
pyparsing==3.1.1
PyPika==0.48.9
pyproject_hooks==1.0.0
PySocks==1.7.1
python-dateutil==2.8.2
python-dotenv==1.0.0
pytorch-triton-rocm==2.2.0+dafe145982
PyYAML==6.0.1
regex==2023.12.25
requests==2.31.0
requests-oauthlib==1.3.1
rsa==4.9
safetensors==0.4.1
scikit-learn==1.4.0rc1
SciPy==1.12.0rc2
selenium==4.16.0
sentence-transformers==2.2.2
sentencepiece==0.1.99
silero-api-server==0.3.1
six==1.16.0
sniffio==1.3.0
sortedcontainers==2.4.0
sounddevice==0.4.6
soundfile==0.12.1
srt==3.5.3
starlette==0.35.1
sympy==1.12
tenacity==8.2.3
threadpoolctl==3.2.0
tiktoken==0.5.2
tokenizers==0.15.0
torch==2.3.0.dev20240110+rocm5.7
torchaudio==2.2.0.dev20240110+rocm5.7
torchvision==0.18.0.dev20240110+rocm5.7
tqdm==4.66.1
transformers==4.36.2
trio==0.24.0
trio-websocket==0.11.1
triton==2.2.0
typer==0.9.0
typing_extensions==4.9.0
urllib3==2.1.0
uvicorn==0.25.0
uvloop==0.19.0
vosk==0.3.45
watchfiles==0.21.0
websocket-client==1.7.0
websockets==12.0
webuiapi==0.9.7
Werkzeug==3.0.1
wrapt==1.16.0
wsproto==1.2.0
wxPython==4.2.1
yarl==1.9.4
zipp==3.17.0
EOF

            pip install --pre -r custom_requirements.txt --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7

            cd $installation_path/SillyTavern-extras
            tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export CUDA_VISIBLE_DEVICES=0
source $installation_path/SillyTavern-extras/.venv/bin/activate
python $installation_path/SillyTavern-extras/server.py --cuda --listen --enable-modules=chromadb,silero-tts
EOF
            chmod +x run.sh
            ;;

        5)
            #Action for Option 5
            if ! command -v python3.10 &> /dev/null; then
                echo "Install Python 3.10 first"
                exit 1
            fi

            mkdir -p $installation_path
            cd $installation_path
            rm -rf tts-generation-webui
            git clone https://github.com/rsxdalv/tts-generation-webui.git
            cd tts-generation-webui
            git checkout d1aec3f7d2a5bf4a1c990abc7a5c16fcc266483b
            
            python3.10 -m venv .venv --prompt TTS
            source .venv/bin/activate
            
            tee --append custom_requirements.txt <<EOF
accelerate==0.26.1
aiofiles==23.2.1
altair==5.2.0
annotated-types==0.6.0
antlr4-python3-runtime==4.8
anyio==4.2.0
appdirs==1.4.4
atlastk==0.13.3
attrs==23.2.0
audioread==3.0.1
av==11.0.0
bark==0.1.5
beartype==0.17.0
bitarray==2.9.2
bleach==6.1.0
blis==0.7.11
boto3==1.34.30
botocore==1.34.30
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
Cython==3.0.8
decorator==5.1.1
deepspeed==0.8.3
demucs==4.0.1
docopt==0.6.2
dora_search==0.1.12
einops==0.7.0
einx==0.1.3
ema-pytorch==0.3.3
encodec==0.1.1
entrypoints==0.4
exceptiongroup==1.2.0
fastapi==0.109.0
fastjsonschema==2.19.1
ffmpeg==1.4
ffmpeg-python==0.2.0
ffmpy==0.3.1
filelock==3.13.1
flashy==0.0.2
fonttools==4.47.2
frozendict==2.4.0
fsspec==2023.12.2
funcy==2.0
future==0.18.3
gradio==3.48.0
gradio_client==0.6.1
h11==0.14.0
hjson==3.1.0
httpcore==1.0.2
httpx==0.26.0
huggingface-hub==0.20.3
hydra-colorlog==1.2.0
hydra-core==1.1.0
idna==3.6
importlib-resources==6.1.1
inflect==7.0.0
Jinja2==3.1.3
jmespath==1.0.1
joblib==1.3.2
jsonschema==4.21.1
jsonschema-specifications==2023.12.1
julius==0.2.7
jupyter_core==5.7.1
kiwisolver==1.4.5
lameenc==1.7.0
langcodes==3.3.0
lazy_loader==0.3
librosa==0.9.1
lightning-utilities==0.10.1
lion-pytorch==0.1.2
lit==17.0.6
llvmlite==0.41.1
local-attention==1.9.0
lxml==5.1.0
markdown-it-py==3.0.0
MarkupSafe==2.1.4
matplotlib==3.8.2
mdurl==0.1.2
mistune==3.0.2
mpmath==1.3.0
msgpack==1.0.7
murmurhash==1.0.10
nbconvert==5.3.1
nbformat==5.9.2
networkx==3.2.1
ninja==1.11.1.1
num2words==0.5.13
numba==0.58.1
numpy==1.26.3
omegaconf==2.1.2
openunmix==1.2.1
orjson==3.9.12
packaging==23.2
pandas==2.2.0
pandocfilters==1.5.1
pillow==10.2.0
platformdirs==4.1.0
pooch==1.8.0
portalocker==2.8.2
preshed==3.0.9
progressbar==2.5
protobuf==4.25.2
psutil==5.9.8
py-cpuinfo==9.0.0
pycparser==2.21
pydantic==1.9.1
pydantic_core==2.14.6
pydub==0.25.1
Pygments==2.17.2
pyparsing==3.1.1
python-dateutil==2.8.2
python-dotenv==1.0.0
python-multipart==0.0.6
pytorch-triton-rocm==2.1.0
pytz==2023.3.post1
PyYAML==6.0.1
referencing==0.32.1
regex==2023.12.25
requests==2.31.0
resampy==0.4.2
retrying==1.3.4
rich==13.7.0
rotary-embedding-torch==0.3.6
rpds-py==0.17.1
ruff==0.1.14
s3transfer==0.10.0
sacrebleu==2.4.0
safetensors==0.3.1
scikit-learn==1.4.0
scipy==1.12.0
semantic-version==2.10.0
sentencepiece==0.1.99
shellingham==1.5.4
six==1.16.0
smart-open==6.4.0
sniffio==1.3.0
sounddevice==0.4.6
soundfile==0.12.1
sox==1.4.1
soxr==0.3.7
spacy==3.7.2
spacy-legacy==3.0.12
spacy-loggers==1.0.5
srsly==2.4.8
starlette==0.35.1
submitit==1.5.1
suno-bark @ git+https://github.com/rsxdalv/bark@0d91823ead3d87c317f12d01d325fca9408c669e
sympy==1.12
tabulate==0.9.0
testpath==0.6.0
thinc==8.2.2
threadpoolctl==3.2.0
tokenizers==0.15.1
tomlkit==0.12.0
toolz==0.12.0
torch==2.1.0+rocm5.6
torchaudio==2.1.0+rocm5.6
torchmetrics==1.3.0.post0
tornado==4.2
tqdm==4.66.1
traitlets==5.14.1
transformers==4.36.1
treetable==0.2.5
typer==0.9.0
typing_extensions==4.9.0
tzdata==2023.4
Unidecode==1.3.8
urllib3==2.0.7
uvicorn==0.26.0
vector_quantize_pytorch==1.12.17
vocos==0.0.2
wasabi==1.1.2
weasel==0.3.4
webencodings==0.5.1
websockets==11.0.3
xformers==0.0.22.post7
EOF

#tortoise-tts @ git+https://github.com/rsxdalv/tortoise-tts@e4711433b12bcd1086840649e1830ad5c3fa1a76

            pip3 install --upgrade pip
            pip install -r custom_requirements.txt --extra-index-url https://download.pytorch.org/whl/rocm5.6
            
            git clone https://github.com/neonbjb/tortoise-tts.git
            cd tortoise-tts
            git checkout 3eee92a4c859ab69c9fc3595ad16dc1a8c756d2b
            rm requirements.txt
            tee --append requirements.txt <<EOF
tqdm
rotary_embedding_torch
transformers
tokenizers
inflect
progressbar
einops
unidecode
scipy
librosa==0.9.1
ffmpeg
numpy
numba
torchaudio
threadpoolctl
llvmlite
appdirs
nbconvert==5.3.1
tornado==4.2
pydantic==1.9.1
deepspeed==0.8.3
py-cpuinfo
hjson
psutil
sounddevice
EOF
            pip install -r requirements.txt

            cd $installation_path/tts-generation-webui
            git clone https://github.com/facebookresearch/fairseq.git
            cd fairseq 
            git checkout 3f0f20f2d12403629224347664b3e75c13b2c8e0
            sed -i 's/"hydra-core>=1.0.7,<1.1",/"hydra-core==1.1",/' setup.py
            sed -i 's/"omegaconf<2.1",/"omegaconf",/' setup.py
            pip install .

            cd $installation_path/tts-generation-webui

            pip install audiolm-pytorch==1.1.4
            pip install git+https://github.com/rsxdalv/bark-voice-cloning-HuBERT-quantizer@816467b243748e003b6905a84c07e7f16ac2803c

tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export CUDA_VISIBLE_DEVICES=0
source $installation_path/tts-generation-webui/.venv/bin/activate
python3 server.py
EOF
            chmod +x run.sh
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
