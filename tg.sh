#!/bin/bash
sudo apt update
sudo apt -y upgrade

installation_path="/home/mdera/AI"
arch="x86_64"
export HSA_OVERRIDE_GFX_VERSION=11.0.0

sudo apt install -y wget git python3 python3-venv libgl1 libglib2.0-0
#

 if ! command -v python3.11 &> /dev/null; then
    echo "Install Python 3.11 first"
    exit 1
fi
mkdir -p $installation_path
cd $installation_path
rm -Rf stable-diffusion-webui
git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
cd stable-diffusion-webui
python3.11 -m venv .venv
source .venv/bin/activate
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/rocm5.7
pip install -r requirements.txt --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7

tee --append run.sh <<EOF
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.0.0
export TF_ENABLE_ONEDNN_OPTS=0
export TORCH_COMMAND="pip install torch torchvision --index-url https://download.pytorch.org/whl/nightly/rocm5.7"
export COMMANDLINE_ARGS="--api"
#export CUDA_VISIBLE_DEVICES="1"
source $installation_path/stable-diffusion-webui/.venv/bin/activate
$installation_path/stable-diffusion-webui/webui.sh 
EOF
chmod +x run.sh