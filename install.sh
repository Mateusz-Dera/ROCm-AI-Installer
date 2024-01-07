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
    whiptail --title "Menu Example" --menu "Choose an option:" 15 100 5 \
    0 "Set installation path ($installation_path)" \
    1 "Install ROCm" \
    2 "stable-diffusion-webui" \
    3 "text-generation-webui" \
    4 "SillyTavern" \
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
            sudo mkdir --parents --mode=0755 /etc/apt/keyrings
            sudo rm /etc/apt/keyrings/rocm.gpg

            sudo rm /etc/apt/sources.list.d/rocm.list
            wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
                gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null
            echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/5.7.3 jammy main" \
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

            sudo apt-get install -y python3.11 python3.11-venv python3.11-dev wget git git-lfs ffmpeg libstdc++-12-dev libtcmalloc-minimal4 python3 python3-venv python3-dev imagemagick libgl1 libglib2.0-0 amdgpu-dkms rocm-dev rocm-libs rocm-hip-sdk rocm-dkms rocm-libs

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
export TORCH_COMMAND="pip install --pre torch==2.3.0.dev20231223 torchvision==0.18.0.dev20231223+rocm5.7 --index-url https://download.pytorch.org/whl/nightly/rocm5.7"
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
            git checkout 3fd707380868ad6a2ba57aaed4c96799c2441d99
            python3.11 -m venv .venv --prompt TextGen
            source .venv/bin/activate

            tee --append custom_requirements.txt <<EOF
absl-py==2.0.0
accelerate==0.25.0
aiofiles==23.2.1
aiohttp==3.9.1
aiosignal==1.3.1
alembic==1.13.1
altair==5.2.0
annotated-types==0.6.0
anyio==4.2.0
appdirs==1.4.4
asttokens==2.4.1
attrs==23.1.0
auto-gptq @ https://github.com/jllllll/AutoGPTQ/releases/download/v0.6.0/auto_gptq-0.6.0+rocm5.6-cp311-cp311-linux_x86_64.whl
backoff==2.2.1
beautifulsoup4==4.12.2
blis==0.7.11
cachetools==5.3.2
catalogue==2.0.10
certifi==2022.12.7
chardet==5.2.0
charset-normalizer==2.1.1
chromadb==0.3.18
click==8.1.7
clickhouse-connect==0.6.23
cloudpathlib==0.16.0
cmake==3.28.1
colorama==0.4.6
coloredlogs==15.0.1
colorlog==6.8.0
confection==0.1.4
contourpy==1.2.0
cramjam==2.7.0
cycler==0.12.1
cymem==2.0.8
DataProperty==1.0.1
datasets==2.16.0
dill==0.3.7
diskcache==5.6.3
distro==1.9.0
docker-pycreds==0.4.0
docopt==0.6.2
duckdb==0.9.2
einops==0.7.0
executing==2.0.1
exllama @ https://github.com/jllllll/exllama/releases/download/0.0.18/exllama-0.0.18+rocm5.6-cp311-cp311-linux_x86_64.whl
exllamav2==0.0.11
fastapi==0.108.0
fastparquet==2023.10.1
ffmpy==0.3.1
filelock==3.9.0
fonttools==4.47.0
frozenlist==1.4.1
fsspec==2023.10.0
gekko==1.0.6
gitdb==4.0.11
GitPython==3.1.40
google-auth==2.25.2
google-auth-oauthlib==1.2.0
gptq-for-llama @ https://github.com/jllllll/GPTQ-for-LLaMa-CUDA/releases/download/0.1.1/gptq_for_llama-0.1.1+rocm5.6-cp311-cp311-linux_x86_64.whl
gradio==3.50.2
gradio_client==0.6.1
graphviz==0.20.1
greenlet==3.0.3
grpcio==1.60.0
h11==0.14.0
hnswlib==0.8.0
hqq==0.1.1.post1
httpcore==1.0.2
httptools==0.6.1
httpx==0.26.0
huggingface-hub==0.20.1
humanfriendly==10.0
icecream==2.1.3
idna==3.4
importlib-resources==6.1.1
iniconfig==2.0.0
Jinja2==3.1.2
joblib==1.3.2
jsonlines==4.0.0
jsonschema==4.20.0
jsonschema-specifications==2023.12.1
kiwisolver==1.4.5
langcodes==3.3.0
lion-pytorch==0.1.2
lit==15.0.7
llama_cpp_python @ https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/cpu/llama_cpp_python-0.2.25+cpuavx2-cp311-cp311-manylinux_2_31_x86_64.whl
llama_cpp_python_cuda @ https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/rocm/llama_cpp_python_cuda-0.2.25+rocm5.6.1-cp311-cp311-manylinux_2_31_x86_64.whl
lm-eval==0.3.0
lxml==5.0.0
lz4==4.3.2
Mako==1.3.0
Markdown==3.5.1
markdown-it-py==3.0.0
MarkupSafe==2.1.3
matplotlib==3.8.2
mbstrdecoder==1.1.3
mdurl==0.1.2
monotonic==1.6
mpmath==1.2.1
multidict==6.0.4
multiprocess==0.70.15
murmurhash==1.0.10
networkx==3.0rc1
ninja==1.11.1.1
nltk==3.8.1
num2words==0.5.13
numexpr==2.8.8
numpy==1.24.4
oauthlib==3.2.2
openai==1.6.1
optimum==1.16.1
optuna==3.5.0
orjson==3.9.10
packaging==22.0
pandas==2.0.3
pathvalidate==3.2.0
peft==0.7.1
Pillow==10.1.0
pluggy==1.3.0
portalocker==2.8.2
posthog==2.4.2
preshed==3.0.9
protobuf==4.23.4
psutil==5.9.7
pyarrow==14.0.2
pyarrow-hotfix==0.6
pyasn1==0.5.1
pyasn1-modules==0.3.0
pybind11==2.11.1
pycountry==23.12.11
pydantic==1.10.13
pydantic_core==2.14.6
pydub==0.25.1
Pygments==2.17.2
pyparsing==3.1.1
pytablewriter==1.2.0
pytest==7.4.3
pytextrank==3.2.5
python-dateutil==2.8.2
python-dotenv==1.0.0
python-multipart==0.0.6
pytorch-triton==2.2.0+e28a256d71
pytorch-triton-rocm==2.2.0+dafe145982
pytz==2023.3.post1
PyYAML==6.0.1
referencing==0.32.0
regex==2023.12.25
requests==2.28.1
requests-oauthlib==1.3.1
rich==13.7.0
rouge==1.0.1
rouge-score==0.1.2
rpds-py==0.16.2
rsa==4.9
sacrebleu==1.5.0
safetensors==0.4.1
scikit-learn==1.3.2
scipy==1.11.4
semantic-version==2.10.0
sentence-transformers==2.2.2
sentencepiece==0.1.99
sentry-sdk==1.39.1
setproctitle==1.3.3
six==1.16.0
smart-open==6.4.0
smmap==5.0.1
sniffio==1.3.0
soupsieve==2.5
spacy==3.7.2
spacy-legacy==3.0.12
spacy-loggers==1.0.5
SpeechRecognition==3.10.1
SQLAlchemy==2.0.24
sqlitedict==2.1.0
srsly==2.4.8
sse-starlette==1.8.2
starlette==0.32.0.post1
sympy==1.11.1
tabledata==1.3.3
tcolorpy==0.1.4
tensorboard==2.15.1
tensorboard-data-server==0.7.2
termcolor==2.4.0
thinc==8.2.2
threadpoolctl==3.2.0
tiktoken==0.5.2
timm==0.9.12
tokenizers==0.15.0
toolz==0.12.0
torch==2.3.0.dev20231218+rocm5.7
torchaudio==2.2.0.dev20231218+rocm5.7
torchdata==0.7.1.dev20231218
torchtext==0.17.0.dev20231218+cpu
torchvision==0.18.0.dev20231218+rocm5.7
tqdm==4.64.1
tqdm-multiprocess==0.0.11
transformers==4.36.2
triton==2.1.0
typepy==1.3.2
typer==0.9.0
typing_extensions==4.8.0
tzdata==2023.4
urllib3==1.26.13
uvicorn==0.25.0
uvloop==0.19.0
wandb==0.16.1
wasabi==1.1.2
watchfiles==0.21.0
weasel==0.3.4
websockets==11.0.3
Werkzeug==3.0.1
xxhash==3.4.1
yarl==1.9.4
zstandard==0.22.0
EOF

            cd $installation_path/text-generation-webui
            git clone https://github.com/arlo-phoenix/bitsandbytes-rocm-5.6.git
            cd bitsandbytes-rocm-5.6
            git checkout 62353b0200b8557026c176e74ac48b84b953a854
            BUILD_CUDA_EXT=0 pip install --pre -r ../custom_requirements.txt --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7
            make hip ROCM_TARGET=gfx1100 ROCM_HOME=/opt/rocm-5.7.3/
            pip install . --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7

            cd $installation_path/text-generation-webui
            git clone https://github.com/ROCmSoftwarePlatform/flash-attention.git
            cd flash-attention
            git checkout 68aac13d3b3296d13062ab3ff40fe58d5e7b3023
            pip install . --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7

            cd $installation_path/text-generation-webui
            git clone https://github.com/turboderp/exllamav2 repositories/exllamav2
            cd repositories/exllamav2
            git checkout 970af13551120579913ab62f7e320c6b35d2f445
            pip install . --index-url https://download.pytorch.org/whl/nightly/rocm5.7

            cd $installation_path/text-generation-webui
            tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export CUDA_VISIBLE_DEVICES=0
source $installation_path/text-generation-webui/.venv/bin/activate
python server.py --api --listen --loader=exllamav2  \
  --auto-devices --extensions sd_api_pictures send_pictures gallery 
EOF
            chmod u+x run.sh
            ;;
        4)
            # Basic
            sudo apt-get update
            sudo apt-get -y install snapd build-essential libgtk-3-dev portaudio19-dev
            sudo snap install node --classic
            mkdir -p $installation_path
            cd $installation_path
            rm -Rf SillyTavern
            git clone https://github.com/SillyTavern/SillyTavern.git
            cd SillyTavern
            git checkout 37d6f13b14bd944d4baa1048d03eb993724ea7f6
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
            git checkout a399907b4e60af3e4f9fc8004c684817321ef6f5
            
            python3.11 -m venv .venv --prompt SillyTavern-extras
            source .venv/bin/activate

            tee --append custom_requirements.txt <<EOF
absl-py==2.0.0
accelerate==0.25.0
aiohttp==3.9.1
aiosignal==1.3.1
annotated-types==0.6.0
anyascii==0.3.2
anyio==4.2.0
asgiref==3.7.2
attrs==23.2.0
audioread==3.0.1
Babel==2.14.0
backoff==2.2.1
bangla==0.0.2
bcrypt==4.1.2
blinker==1.7.0
blis==0.7.11
bnnumerizer==0.0.2
bnunicodenormalizer==0.1.6
Brotli==1.1.0
build==1.0.3
cachetools==5.3.2
catalogue==2.0.10
certifi==2023.7.22
cffi==1.16.0
charset-normalizer==3.3.2
chroma-hnswlib==0.7.3
chromadb==0.4.22
click==8.1.7
cloudpathlib==0.16.0
cmake==3.28.1
colorama==0.4.6
coloredlogs==15.0.1
confection==0.1.4
contourpy==1.2.0
coqpit==0.0.17
cutlet==0.3.0
cycler==0.12.1
cymem==2.0.8
Cython==3.0.7
dateparser==1.1.8
decorator==5.1.1
Deprecated==1.2.14
diffusers==0.25.0
docopt==0.6.2
edge-tts==6.1.9
einops==0.7.0
emoji==2.8.0
encodec==0.1.1
fastapi==0.108.0
filelock==3.13.1
Flask==3.0.0
flask-cloudflared==0.0.14
Flask-Compress==1.14
Flask-Cors==4.0.0
flatbuffers==23.5.26
fonttools==4.47.0
frozenlist==1.4.1
fsspec==2023.12.2
fugashi==1.3.0
g2pkk==0.1.2
google-auth==2.26.1
google-auth-oauthlib==1.2.0
googleapis-common-protos==1.62.0
grpcio==1.60.0
gruut==2.2.3
gruut-ipa==0.13.0
gruut-lang-de==2.0.0
gruut-lang-en==2.0.0
gruut-lang-es==2.0.0
gruut-lang-fr==2.0.2
h11==0.14.0
hangul-romanize==0.1.0
httptools==0.6.1
huggingface-hub==0.20.2
humanfriendly==10.0
idna==3.6
importlib-metadata==6.11.0
importlib-resources==6.1.1
inflect==7.0.0
itsdangerous==2.1.2
jaconv==0.3.4
jamo==0.4.1
jieba==0.42.1
Jinja2==3.1.2
joblib==1.3.2
jsonlines==1.2.0
kiwisolver==1.4.5
kubernetes==28.1.0
langcodes==3.3.0
lazy_loader==0.3
librosa==0.10.1
lit==17.0.6
llvmlite==0.41.1
loguru==0.7.2
Markdown==3.5.1
MarkupSafe==2.1.3
matplotlib==3.8.2
mmh3==4.0.1
mojimoji==0.0.12
monotonic==1.6
more-itertools==10.1.0
mpmath==1.3.0
msgpack==1.0.7
multidict==6.0.4
murmurhash==1.0.10
networkx==2.8.8
nltk==3.8.1
num2words==0.5.13
numba==0.58.1
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
pandas==1.5.3
Pillow==9.5.0
platformdirs==4.1.0
pooch==1.8.0
posthog==3.1.0
preshed==3.0.9
protobuf==4.23.4
psutil==5.9.7
pulsar-client==3.4.0
pyasn1==0.5.1
pyasn1-modules==0.3.0
PyAudio==0.2.14
pycparser==2.21
pydantic==2.5.3
pydantic_core==2.14.6
pydub==0.25.1
pynndescent==0.5.11
pyparsing==3.1.1
PyPika==0.48.9
pypinyin==0.50.0
pyproject_hooks==1.0.0
pysbd==0.3.4
PySocks==1.7.1
python-crfsuite==0.9.10
python-dateutil==2.8.2
python-dotenv==1.0.0
pytorch-triton-rocm==2.2.0+dafe145982
pyttsx3==2.90
pytz==2023.3.post1
PyYAML==6.0.1
regex==2023.12.25
requests==2.31.0
requests-oauthlib==1.3.1
rsa==4.9
safetensors==0.4.1
scikit-learn==1.3.2
scipy==1.11.4
selenium==4.16.0
sentence-transformers==2.2.2
sentencepiece==0.1.99
silero-api-server==0.3.1
six==1.16.0
smart-open==6.4.0
sniffio==1.3.0
sortedcontainers==2.4.0
sounddevice==0.4.6
soundfile==0.12.1
soxr==0.3.7
spacy==3.7.2
spacy-legacy==3.0.12
spacy-loggers==1.0.5
srsly==2.4.8
srt==3.5.3
stanza==1.6.1
starlette==0.32.0.post1
stream2sentence==0.2.2
SudachiDict-core==20230927
SudachiPy==0.6.8
sympy==1.12
tenacity==8.2.3
tensorboard==2.15.1
tensorboard-data-server==0.7.2
thinc==8.2.2
threadpoolctl==3.2.0
tiktoken==0.5.2
tokenizers==0.15.0
torch==2.3.0.dev20240106+rocm5.7
torchaudio==2.2.0.dev20240106+rocm5.7
torchvision==0.18.0.dev20240106+rocm5.7
tqdm==4.66.1
trainer==0.0.36
transformers==4.36.2
trio==0.23.2
trio-websocket==0.11.1
triton==2.1.0
TTS==0.21.3
typer==0.9.0
typing_extensions==4.9.0
tzlocal==5.2
umap-learn==0.5.5
Unidecode==1.3.7
unidic-lite==1.0.8
urllib3==1.26.18
uvicorn==0.25.0
uvloop==0.19.0
vosk==0.3.45
wasabi==1.1.2
watchfiles==0.21.0
weasel==0.3.4
websocket-client==1.7.0
websockets==12.0
webuiapi==0.9.7
Werkzeug==3.0.1
wrapt==1.16.0
wsproto==1.2.0
wxPython==4.2.1
xtts-api-server==0.8.3
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
python $installation_path/SillyTavern-extras/server.py --cuda --listen --enable-modules=chromadb
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