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

export HSA_OVERRIDE_GFX_VERSION=11.0.0

# Default installation path
default_installation_path="$HOME/AI"
# Global variable for installation path
installation_path="$default_installation_path"

sudo apt-get update
sudo apt-get -y install whiptail

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

            sudo apt-get install -y python3.11 python3.11-venv python3.11-dev wget git git-lfs ffmpeg libstdc++-12-dev libtcmalloc-minimal4 python3 python3-venv python3-dev imagemagick libgl1 libglib2.0-0 amdgpu-dkms rocm-dev rocm-libs rocm-hip-sdk rocm-dkms rocm-libs

            sudo rm /etc/ld.so.conf.d/rocm.conf
            sudo tee --append /etc/ld.so.conf.d/rocm.conf <<EOF
/opt/rocm/lib
/opt/rocm/lib64
EOF
            sudo ldconfig
            ;;
        2)
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
            # Action for Option 2
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
altair==5.2.0
annotated-types==0.6.0
anyio==4.2.0
appdirs==1.4.4
attributedict==0.3.0
attrs==23.1.0
auto-gptq @ https://github.com/jllllll/AutoGPTQ/releases/download/v0.6.0/auto_gptq-0.6.0+rocm5.6-cp311-cp311-linux_x86_64.whl
autoawq==0.1.8
bitsandbytes @ file:///home/mdera/AI/text-generation-webui/bitsandbytes-rocm-5.6
blessings==1.7
cachetools==5.3.2
certifi==2023.11.17
chardet==5.2.0
charset-normalizer==3.3.2
click==8.1.7
cmake==3.28.1
codecov==2.1.13
colorama==0.4.6
coloredlogs==15.0.1
colour-runner==0.1.1
contourpy==1.2.0
coverage==7.4.0
cramjam==2.7.0
ctransformers @ https://github.com/jllllll/ctransformers-cuBLAS-wheels/releases/download/AVX2/ctransformers-0.2.27+cu121-py3-none-any.whl
cycler==0.12.1
DataProperty==1.0.1
datasets==2.16.0
deepdiff==6.7.1
dill==0.3.7
diskcache==5.6.3
distlib==0.3.8
distro==1.9.0
docker-pycreds==0.4.0
einops==0.7.0
exllama @ https://github.com/jllllll/exllama/releases/download/0.0.18/exllama-0.0.18+rocm5.6-cp311-cp311-linux_x86_64.whl
exllamav2 @ https://github.com/turboderp/exllamav2/releases/download/v0.0.11/exllamav2-0.0.11+rocm5.6-cp311-cp311-linux_x86_64.whl
fastapi==0.108.0
fastparquet==2023.10.1
ffmpy==0.3.1
filelock==3.13.1
flash-attn @ https://github.com/Dao-AILab/flash-attention/releases/download/v2.3.4/flash_attn-2.3.4+cu122torch2.1cxx11abiFALSE-cp311-cp311-linux_x86_64.whl
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
grpcio==1.60.0
h11==0.14.0
hqq==0.1.1.post1
httpcore==1.0.2
httpx==0.26.0
huggingface-hub==0.20.1
humanfriendly==10.0
idna==3.6
importlib-resources==6.1.1
iniconfig==2.0.0
inspecta==0.1.3
Jinja2==3.1.2
joblib==1.3.2
jsonlines==4.0.0
jsonschema==4.20.0
jsonschema-specifications==2023.12.1
kiwisolver==1.4.5
lion-pytorch==0.1.2
lit==17.0.6
llama_cpp_python @ https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/cpu/llama_cpp_python-0.2.25+cpuavx2-cp311-cp311-manylinux_2_31_x86_64.whl
llama_cpp_python_cuda @ https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/rocm/llama_cpp_python_cuda-0.2.25+rocm5.6.1-cp311-cp311-manylinux_2_31_x86_64.whl
llama_cpp_python_cuda_tensorcores @ https://github.com/oobabooga/llama-cpp-python-cuBLAS-wheels/releases/download/textgen-webui/llama_cpp_python_cuda_tensorcores-0.2.25+cu121-cp311-cp311-manylinux_2_31_x86_64.whl
lm-eval==0.3.0
Markdown==3.5.1
markdown-it-py==3.0.0
MarkupSafe==2.1.3
matplotlib==3.8.2
mbstrdecoder==1.1.3
mdurl==0.1.2
mpmath==1.3.0
multidict==6.0.4
multiprocess==0.70.15
networkx==3.2.1
ninja==1.11.1.1
nltk==3.8.1
numexpr==2.8.8
numpy==1.24.4
oauthlib==3.2.2
openai==1.6.1
optimum==1.16.1
ordered-set==4.1.0
orjson==3.9.10
packaging==23.2
pandas==2.2.0rc0
pathvalidate==3.2.0
peft==0.7.1
Pillow==10.1.0
platformdirs==4.1.0
pluggy==1.3.0
portalocker==2.8.2
protobuf==4.23.4
psutil==5.9.7
py-cpuinfo==9.0.0
pyarrow==14.0.2
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
pyproject-api==1.6.1
pytablewriter==1.2.0
pytest==7.4.3
python-dateutil==2.8.2
python-multipart==0.0.6
pytorch-triton==2.2.0+e28a256d71
pytorch-triton-rocm==2.2.0+dafe145982
pytz==2023.3.post1
PyYAML==6.0.1
referencing==0.32.0
regex==2023.12.25
requests==2.31.0
requests-oauthlib==1.3.1
rich==13.7.0
rootpath==0.1.1
rouge==1.0.1
rouge-score==0.1.2
rpds-py==0.16.1
rsa==4.9
sacrebleu==1.5.0
safetensors==0.4.1
scikit-learn==1.4.0rc1
SciPy==1.12.0rc1
semantic-version==2.10.0
sentencepiece==0.1.99
sentry-sdk==1.39.1
setproctitle==1.3.3
six==1.16.0
smmap==5.0.1
sniffio==1.3.0
SpeechRecognition==3.10.1
sqlitedict==2.1.0
sse-starlette==1.8.2
starlette==0.32.0.post1
sympy==1.12
tabledata==1.3.3
tabulate==0.9.0
tcolorpy==0.1.4
tensorboard==2.15.1
tensorboard-data-server==0.7.2
termcolor==2.4.0
texttable==1.7.0
threadpoolctl==3.2.0
tiktoken==0.5.2
timm==0.9.12
tokenizers==0.15.0
toml==0.10.2
toolz==0.12.0
torch==2.3.0.dev20231223+rocm5.7
torchaudio==2.2.0.dev20231223+rocm5.7
torchdata==0.7.1.dev20231223
torchtext==0.17.0.dev20231223+cpu
torchvision==0.18.0.dev20231223+rocm5.7
tox==4.11.4
tqdm==4.66.1
tqdm-multiprocess==0.0.11
transformers==4.36.2
triton==2.1.0
typepy==1.3.2
typing_extensions==4.9.0
tzdata==2023.3
urllib3==2.1.0
uvicorn==0.25.0
virtualenv==20.25.0
wandb==0.16.1
websockets==11.0.3
Werkzeug==3.0.1
xxhash==3.4.1
yarl==1.9.4
zstandard==0.22.0
EOF
           
            BUILD_CUDA_EXT=0 pip install --pre -r custom_requirements.txt --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7
            cd $installation_path/text-generation-webui
            rm -rf bitsandbytes-rocm-5.6
            git clone https://github.com/arlo-phoenix/bitsandbytes-rocm-5.6.git
            cd bitsandbytes-rocm-5.6/
            git checkout 62353b0200b8557026c176e74ac48b84b953a854

            make hip ROCM_TARGET=gfx1100 ROCM_HOME=/opt/rocm-6.0.0/
            pip install . --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7

            cd $installation_path/text-generation-webui

            git clone https://github.com/turboderp/exllamav2.git repositories/exllamav2

            cd $installation_path/text-generation-webui/repositories/exllamav2
            git checkout d36077cf92e9d6b0d646764f43e4a1ea070c1440

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
            sudo snap install node --classic
            sudo apt-get -y install build-essential libgtk-3-dev
            mkdir -p $installation_path
            cd $installation_path
            rm -Rf SillyTavern
            git clone https://github.com/SillyTavern/SillyTavern.git
            cd SillyTavern
            git checkout 6508a2d92474017aa21f5ac363effd5566995523
            mv ./start.sh ./run.sh

            # Default config
            cd ./default
            sed -i 's/listen: false/listen: true/' config.yaml
            sed -i 's/whitelistMode: true/whitelistMode: false/' config.yaml
            sed -i 's/basicAuthMode: false/basicAuthMode: true/' config.yaml

            # Extras
            cd $installation_path

            rm -Rf SillyTavern-extras
            git clone https://github.com/SillyTavern/SillyTavern-extras
            cd SillyTavern-extras
            git checkout 08a18dc506d8d73685de5c4d28980fa544e258e0
            
            python3.11 -m venv .venv --prompt SillyTavern-extras
            source .venv/bin/activate

            tee --append custom_requirements.txt <<EOF
annotated-types==0.6.0
anyio==4.2.0
asgiref==3.7.2
backoff==2.2.1
bcrypt==4.1.2
blinker==1.7.0
Brotli==1.1.0
cachetools==5.3.2
certifi==2023.11.17
charset-normalizer==3.3.2
chroma-hnswlib==0.7.3
chromadb==0.4.21
click==8.1.7
colorama==0.4.6
coloredlogs==15.0.1
Deprecated==1.2.14
fastapi==0.108.0
filelock==3.13.1
Flask==3.0.0
Flask-Compress==1.14
Flask-Cors==4.0.0
flatbuffers==23.5.26
fsspec==2023.12.2
google-auth==2.25.2
googleapis-common-protos==1.62.0
grpcio==1.60.0
h11==0.14.0
httptools==0.6.1
huggingface-hub==0.20.1
humanfriendly==10.0
idna==3.6
importlib-metadata==6.11.0
importlib-resources==6.1.1
itsdangerous==2.1.2
Jinja2==3.1.2
joblib==1.3.2
kubernetes==28.1.0
Markdown==3.5.1
MarkupSafe==2.1.3
mmh3==4.0.1
monotonic==1.6
mpmath==1.2.1
networkx==3.0rc1
nltk==3.8.1
numpy==1.26.2
oauthlib==3.2.2
onnxruntime==1.16.3
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
overrides==7.4.0
packaging==23.2
Pillow==9.3.0
posthog==3.1.0
protobuf==4.25.1
pulsar-client==3.3.0
pyasn1==0.5.1
pyasn1-modules==0.3.0
pydantic==2.5.3
pydantic_core==2.14.6
PyPika==0.48.9
python-dateutil==2.8.2
python-dotenv==1.0.0
pytorch-triton-rocm==2.2.0+dafe145982
PyYAML==6.0.1
regex==2023.12.25
requests==2.31.0
requests-oauthlib==1.3.1
rsa==4.9
safetensors==0.4.1
scikit-learn==1.3.2
scipy==1.11.4
sentence-transformers==2.2.2
sentencepiece==0.1.99
six==1.16.0
sniffio==1.3.0
starlette==0.32.0.post1
sympy==1.11.1
tenacity==8.2.3
threadpoolctl==3.2.0
tokenizers==0.15.0
torch==2.3.0.dev20231223+rocm5.7
torchvision==0.18.0.dev20231223+rocm5.7
tqdm==4.66.1
transformers==4.36.2
typer==0.9.0
typing_extensions==4.9.0
urllib3==1.26.18
uvicorn==0.25.0
uvloop==0.19.0
watchfiles==0.21.0
websocket-client==1.7.0
websockets==12.0
webuiapi==0.9.6
Werkzeug==3.0.1
wrapt==1.16.0
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