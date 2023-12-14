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

arch="x86_64"
export HSA_OVERRIDE_GFX_VERSION=11.0.0

# Default installation path
default_installation_path="$HOME/AI"
# Global variable for installation path
installation_path="$default_installation_path"

sudo apt-get update
sudo apt-get -y upgrade
sudo apt purge -y rocm*

sudo add-apt-repository -y -s deb http://security.ubuntu.com/ubuntu jammy main universe

sudo mkdir --parents --mode=0755 /etc/apt/keyrings
sudo rm /etc/apt/keyrings/rocm.gpg

sudo rm /etc/apt/sources.list.d/rocm.list
wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
    gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/5.7.2 jammy main" \
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

sudo apt-get install -y whiptail wget git git-lfs ffmpeg libstdc++-12-dev libtcmalloc-minimal4 python3 python3-venv python3-dev imagemagick libgl1 libglib2.0-0 amdgpu-dkms rocm-dev rocm-libs rocm-hip-sdk rocm-dkms rocm-libs

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
export COMMANDLINE_ARGS="--api --no-half-vae"
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
            if ! command -v python3.11 &> /dev/null; then
                echo "Install Python 3.11 first"
                exit 1
            fi
            mkdir -p $installation_path
            cd $installation_path
            rm -rf text-generation-webui
            git clone https://github.com/oobabooga/text-generation-webui.git
            cd text-generation-webui
            git checkout e4e35f357b5ea8dba397f142cb3b9f047bd11f61
            python3.11 -m venv .venv --prompt TextGen
            source .venv/bin/activate
tee --append custom_requirements.txt <<EOF
certifi==2022.12.7
charset-normalizer==2.1.1
cmake==3.25.0
colorama==0.4.6
filelock==3.9.0
fsspec==2023.12.0
idna==3.4
Jinja2==3.1.2
lit==15.0.7
MarkupSafe==2.1.3
mpmath==1.2.1
networkx==3.0rc1
numpy==1.24.1
packaging==22.0
Pillow==9.3.0
pytorch-triton==2.1.0+e650d3708b
pytorch-triton-rocm==2.1.0+dafe145982
requests==2.28.1
sympy==1.11.1
torch==2.2.0.dev20231128+rocm5.7
torchaudio==2.2.0.dev20231129+rocm5.7
torchdata==0.7.1
torchtext==0.17.0.dev20231128+cpu
torchvision==0.17.0.dev20231128+rocm5.7
tqdm==4.64.1
triton==2.1.0
typing_extensions==4.8.0
urllib3==1.26.13
EOF
            pip install -r custom_requirements.txt --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7
            cd $installation_path/text-generation-webui
            rm -rf bitsandbytes-rocm-5.6
            git clone https://github.com/arlo-phoenix/bitsandbytes-rocm-5.6.git
            cd bitsandbytes-rocm-5.6/
            git checkout e38b9e91b718e8b84f4678c423f72dd4decce4e5
            tee --append custom_requirements.txt <<EOF
iniconfig==2.0.0
lion-pytorch==0.1.2
pluggy==1.3.0
pytest==7.4.3
EOF
            BUILD_CUDA_EXT=0 pip install -r custom_requirements.txt --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7
            make hip ROCM_TARGET=gfx1100 ROCM_HOME=/opt/rocm-5.7.2/
            pip install . --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7

            pip install -U --index-url https://aiinfra.pkgs.visualstudio.com/PublicPackages/_packaging/Triton-Nightly/pypi/simple/ triton-nightly==2.1.0.post20231203000508
            pip install ninja==1.11.1

            cd $installation_path/text-generation-webui
            rm -rf flash-attention
            git clone https://github.com/ROCmSoftwarePlatform/flash-attention.git
            cd flash-attention
            git checkout 3d2b6f5d037782cc2c906909a46fb7e2e1b48b25
            pip install .

            cd $installation_path/text-generation-webui

            tee --append custom_requirements_amd.txt <<EOF
accelerate==0.24.1  
huggingface-hub==0.19.4 
psutil==5.9.6 
pyyaml==6.0.1
aiohttp==3.9.1 
aiosignal==1.3.1 
attrs==23.1.0 
datasets==2.15.0 
dill==0.3.7 
frozenlist==1.4.0 
multidict==6.0.4 
multiprocess==0.70.15 
pandas==2.1.3 
pyarrow==14.0.1 
pyarrow-hotfix==0.6 
python-dateutil==2.8.2 
pytz==2023.3.post1 
six==1.16.0 
tzdata==2023.3 
xxhash==3.4.1 
yarl==1.9.3
einops==0.7.0
exllamav2==0.0.8
aiofiles==23.2.1
altair==5.2.0
annotated-types==0.6.0
anyio==3.7.1
click==8.1.7
contourpy==1.2.0
cycler==0.12.1
fastapi==0.104.1
ffmpy==0.3.1
fonttools==4.46.0
gradio==3.50.2
gradio-client==0.6.1
h11==0.14.0
httpcore==1.0.2
httpx==0.25.2
importlib-resources==6.1.1
jsonschema==4.20.0
jsonschema-specifications==2023.11.2
kiwisolver==1.4.5
matplotlib==3.8.2
orjson==3.9.10
pydantic==2.5.2
pydantic-core==2.14.5
pydub==0.25.1
pyparsing==3.1.1
python-multipart==0.0.6
referencing==0.31.1
rpds-py==0.13.2
semantic-version==2.10.0
sniffio==1.3.0
starlette==0.27.0
toolz==0.12.0
uvicorn==0.24.0.post1
websockets==11.0.3
markdown==3.5.1
coloredlogs==15.0.1
humanfriendly==10.0
optimum==1.14.0
protobuf==4.23
regex==2023.10.3
safetensors==0.4.1
sentencepiece==0.1.99
tokenizers==0.15.0
transformers==4.35.2
peft==0.6.2
Pillow==9.5.0
scipy==1.11.4
sentencepiece==0.1.99
absl-py==2.0.0
cachetools==5.3.2
google-auth==2.24.0
google-auth-oauthlib==1.1.0
grpcio==1.59.3
oauthlib==3.2.2
pyasn1==0.5.1
pyasn1-modules==0.3.0
requests-oauthlib==1.3.1
rsa==4.9
tensorboard==2.15.1
tensorboard-data-server==0.7.2
werkzeug==3.0.
GitPython==3.1.40
appdirs==1.4.4
docker-pycreds==0.4.0
sentry-sdk==1.38.0
setproctitle==1.3.3
smmap==5.0.1
wandb==0.16.0
gitdb==4.0.11
fastparquet==2023.10.1
pygments==2.17.2
SpeechRecognition==3.10.0
sse-starlette==1.8.2
tiktoken==0.5.2

#superboogav2
asgiref==3.7.2
backoff==2.2.1
bcrypt==4.1.1
chroma-hnswlib==0.7.3
chromadb==0.4.15
deprecated==1.2.14
flatbuffers==23.5.26
googleapis-common-protos==1.62.0
httptools==0.6.1
importlib-metadata==6.11.0
kubernetes==28.1.0
mmh3==4.0.1
monotonic==1.6
onnxruntime==1.16.3
opentelemetry-api==1.21.0
opentelemetry-exporter-otlp-proto-common==1.21.0
opentelemetry-exporter-otlp-proto-grpc==1.21.0
opentelemetry-instrumentation==0.42b0
opentelemetry-instrumentation-asgi==0.42b0
opentelemetry-instrumentation-fastapi==0.42b0
opentelemetry-proto==1.21.0
opentelemetry-sdk==1.21.0
opentelemetry-semantic-conventions==0.42b0
opentelemetry-util-http==0.42b0
overrides==7.4.0 
posthog==3.1.0
pulsar-client==3.3.0
pypika==0.48.9
python-dotenv==1.0.0
tenacity==8.2.3
tqdm==4.66.1
typer==0.9.0
uvloop==0.19.0
watchfiles==0.21.0
websocket-client==1.7.0
wrapt==1.16.0
zipp==3.17.0
joblib==1.3.2
nltk==3.8.1
scikit-learn==1.3.2
sentence_transformers==2.2.2
threadpoolctl==3.2.0
asttokens==2.4.1
blis==0.7.11
catalogue==2.0.10
cloudpathlib==0.16.0
confection==0.1.4
cymem==2.0.8
executing==2.0.1
graphviz==0.20.1
icecream==2.1.3
langcodes==3.3.0
murmurhash==1.0.10
preshed==3.0.9
pytextrank==3.2.5
smart-open==6.4.0
spacy==3.7.2
spacy-legacy==3.0.12
spacy-loggers==1.0.5
srsly==2.4.8
thinc==8.2.1
wasabi==1.1.2
weasel==0.3.4
docopt==0.6.2
num2words==0.5.13
Mako==1.3.0
alembic==1.13.0
colorlog==6.8.0
greenlet==3.0.2
optuna==3.5.0
sqlalchemy==2.0.23
beautifulsoup4==4.12.2
bs4==0.0.1

soupsieve==2.5

git+https://github.com/oobabooga/torch-grammar.git

# llama-cpp-python (CPU only, AVX2)
https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/cpu/llama_cpp_python-0.2.19+cpuavx2-cp311-cp311-manylinux_2_31_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.11"
https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/cpu/llama_cpp_python-0.2.19+cpuavx2-cp310-cp310-manylinux_2_31_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.10"
https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/cpu/llama_cpp_python-0.2.19+cpuavx2-cp39-cp39-manylinux_2_31_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.9"
https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/cpu/llama_cpp_python-0.2.19+cpuavx2-cp38-cp38-manylinux_2_31_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.8"
https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/cpu/llama_cpp_python-0.2.19+cpuavx2-cp311-cp311-win_amd64.whl; platform_system == "Windows" and python_version == "3.11"
https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/cpu/llama_cpp_python-0.2.19+cpuavx2-cp310-cp310-win_amd64.whl; platform_system == "Windows" and python_version == "3.10"
https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/cpu/llama_cpp_python-0.2.19+cpuavx2-cp39-cp39-win_amd64.whl; platform_system == "Windows" and python_version == "3.9"
https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/cpu/llama_cpp_python-0.2.19+cpuavx2-cp38-cp38-win_amd64.whl; platform_system == "Windows" and python_version == "3.8"

# AMD wheels
https://github.com/jllllll/AutoGPTQ/releases/download/v0.5.1/auto_gptq-0.5.1+rocm5.6-cp311-cp311-linux_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.11"
https://github.com/jllllll/AutoGPTQ/releases/download/v0.5.1/auto_gptq-0.5.1+rocm5.6-cp310-cp310-linux_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.10"
https://github.com/jllllll/AutoGPTQ/releases/download/v0.5.1/auto_gptq-0.5.1+rocm5.6-cp39-cp39-linux_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.9"
https://github.com/jllllll/AutoGPTQ/releases/download/v0.5.1/auto_gptq-0.5.1+rocm5.6-cp38-cp38-linux_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.8"
https://github.com/jllllll/exllama/releases/download/0.0.18/exllama-0.0.18+rocm5.6-cp311-cp311-linux_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.11"
https://github.com/jllllll/exllama/releases/download/0.0.18/exllama-0.0.18+rocm5.6-cp310-cp310-linux_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.10"
https://github.com/jllllll/exllama/releases/download/0.0.18/exllama-0.0.18+rocm5.6-cp39-cp39-linux_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.9"
https://github.com/jllllll/exllama/releases/download/0.0.18/exllama-0.0.18+rocm5.6-cp38-cp38-linux_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.8"
https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/rocm/llama_cpp_python_cuda-0.2.19+rocm5.6.1-cp311-cp311-manylinux_2_31_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.11"
https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/rocm/llama_cpp_python_cuda-0.2.19+rocm5.6.1-cp310-cp310-manylinux_2_31_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.10"
https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/rocm/llama_cpp_python_cuda-0.2.19+rocm5.6.1-cp39-cp39-manylinux_2_31_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.9"
https://github.com/jllllll/llama-cpp-python-cuBLAS-wheels/releases/download/rocm/llama_cpp_python_cuda-0.2.19+rocm5.6.1-cp38-cp38-manylinux_2_31_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.8"
https://github.com/jllllll/GPTQ-for-LLaMa-CUDA/releases/download/0.1.1/gptq_for_llama-0.1.1+rocm5.6-cp311-cp311-linux_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.11"
https://github.com/jllllll/GPTQ-for-LLaMa-CUDA/releases/download/0.1.1/gptq_for_llama-0.1.1+rocm5.6-cp310-cp310-linux_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.10"
https://github.com/jllllll/GPTQ-for-LLaMa-CUDA/releases/download/0.1.1/gptq_for_llama-0.1.1+rocm5.6-cp39-cp39-linux_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.9"
https://github.com/jllllll/GPTQ-for-LLaMa-CUDA/releases/download/0.1.1/gptq_for_llama-0.1.1+rocm5.6-cp38-cp38-linux_x86_64.whl; platform_system == "Linux" and platform_machine == "x86_64" and python_version == "3.8"
EOF
            pip install -r custom_requirements_amd.txt 

            git clone https://github.com/turboderp/exllama.git repositories/exllama
            git clone https://github.com/turboderp/exllamav2.git repositories/exllamav2

            cd $installation_path/text-generation-webui/repositories/exllama
            git checkout 3b013cd53c7d413cf99ca04c7c28dd5c95117c0d

            cd $installation_path/text-generation-webui/repositories/exllamav2
            git checkout 5c974259bd245ace74ba4e8dda319d1f87d04c70

            cd $installation_path/text-generation-webui

            pip install --upgrade --force-reinstall numpy==1.26.2 pyarrow==14.0.1

            tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export CUDA_VISIBLE_DEVICES=0
source $installation_path/text-generation-webui/.venv/bin/activate
python server.py --api --listen --loader=exllama  \
  --auto-devices --extensions sd_api_pictures send_pictures gallery 
EOF
            chmod u+x run.sh
            ;;
        3)
            # Basic
            sudo snap install node --classic
            sudo apt -y install build-essential libgtk-3-dev
            mkdir -p $installation_path
            cd $installation_path
            rm -Rf SillyTavern
            git clone https://github.com/SillyTavern/SillyTavern.git
            cd SillyTavern
            git checkout 6f610204d6794ad3ccea9395e1a132d7bf727909
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
            git checkout 2e6ab8be46f492f3ca4081fedbea13574e8659c0
            
            python3.11 -m venv .venv --prompt SillyTavern-extras
            source .venv/bin/activate

            tee --append custom_requirements.txt <<EOF
accelerate==0.25.0
aiohttp==3.9.1
aiosignal==1.3.1
annotated-types==0.6.0
anyio==3.7.1
asgiref==3.7.2
attrs==23.1.0
backoff==2.2.1
bcrypt==4.1.1
blinker==1.7.0
Brotli==1.1.0
cachetools==5.3.2
certifi==2023.7.22
cffi==1.16.0
charset-normalizer==3.3.2
chroma-hnswlib==0.7.3
chromadb==0.4.19
click==8.1.7
cmake==3.28.0
colorama==0.4.6
coloredlogs==15.0.1
contourpy==1.2.0
cycler==0.12.1
Deprecated==1.2.14
diffusers==0.24.0
edge-tts==6.1.9
fastapi==0.105.0
filelock==3.13.1
Flask==3.0.0
flask-cloudflared==0.0.14
Flask-Compress==1.14
Flask-Cors==4.0.0
flatbuffers==23.5.26
fonttools==4.46.0
frozenlist==1.4.0
fsspec==2023.12.2
google-auth==2.25.2
googleapis-common-protos==1.62.0
grpcio==1.60.0
h11==0.14.0
httptools==0.6.1
huggingface-hub==0.19.4
humanfriendly==10.0
idna==3.6
importlib-metadata==6.11.0
importlib-resources==6.1.1
itsdangerous==2.1.2
Jinja2==3.1.2
joblib==1.3.2
kiwisolver==1.4.5
kubernetes==28.1.0
lit==17.0.6
llvmlite==0.41.1
loguru==0.7.2
Markdown==3.5.1
MarkupSafe==2.1.3
matplotlib==3.8.2
mmh3==4.0.1
monotonic==1.6
more-itertools==10.1.0
mpmath==1.3.0
multidict==6.0.4
networkx==3.2.1
nltk==3.8.1
numba==0.58.1
numpy==1.26.2
oauthlib==3.2.2
onnxruntime==1.16.3
openai-whisper==20231117
opentelemetry-api==1.21.0
opentelemetry-exporter-otlp-proto-common==1.21.0
opentelemetry-exporter-otlp-proto-grpc==1.21.0
opentelemetry-instrumentation==0.42b0
opentelemetry-instrumentation-asgi==0.42b0
opentelemetry-instrumentation-fastapi==0.42b0
opentelemetry-proto==1.21.0
opentelemetry-sdk==1.21.0
opentelemetry-semantic-conventions==0.42b0
opentelemetry-util-http==0.42b0
outcome==1.3.0.post0
overrides==7.4.0
packaging==23.2
Pillow==9.5.0
posthog==3.1.0
protobuf==4.25.1
psutil==5.9.6
pulsar-client==3.3.0
pyasn1==0.5.1
pyasn1-modules==0.3.0
pycparser==2.21
pydantic==2.5.2
pydantic_core==2.14.5
pydub==0.25.1
pyparsing==3.1.1
PyPika==0.48.9
PySocks==1.7.1
python-dateutil==2.8.2
python-dotenv==1.0.0
pytorch-triton-rocm==2.1.0
PyYAML==6.0.1
regex==2023.10.3
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
sniffio==1.3.0
sortedcontainers==2.4.0
sounddevice==0.4.6
soundfile==0.12.1
srt==3.5.3
starlette==0.27.0
sympy==1.12
tenacity==8.2.3
threadpoolctl==3.2.0
tiktoken==0.5.2
tokenizers==0.15.0
torch==2.1.0+rocm5.6
torchaudio==2.1.0+rocm5.6
torchvision==0.16.0+rocm5.6
tqdm==4.66.1
transformers==4.36.1
trio==0.23.2
trio-websocket==0.11.1
triton==2.1.0
typer==0.9.0
typing_extensions==4.9.0
urllib3==1.26.18
uvicorn==0.24.0.post1
uvloop==0.19.0
vosk==0.3.45
watchfiles==0.21.0
websocket-client==1.7.0
websockets==12.0
webuiapi==0.9.6
Werkzeug==3.0.1
wrapt==1.16.0
wsproto==1.2.0
wxPython==4.2.1
yarl==1.9.4
zipp==3.17.0
EOF

            pip install -r custom_requirements.txt --extra-index-url https://download.pytorch.org/whl/rocm5.6
            
            cd $installation_path/SillyTavern-extras
            tee --append run.sh <<EOF
#!/bin/bash
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