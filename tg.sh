#!/bin/bash
sudo apt update
sudo apt -y upgrade

installation_path="/home/mdera/AI"
arch="x86_64"
export HSA_OVERRIDE_GFX_VERSION=11.0.0

sudo apt install -y wget git python3 python3-venv libgl1 libglib2.0-0
#

mkdir -p $installation_path
cd $installation_path
sudo rm -rf stable-diffusion-webui
git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
cd stable-diffusion-webui

sudo rm -rf webui-user.sh
tee --append webui-user.sh <<EOF
 export TORCH_COMMAND="pip install --pre torch==2.2.0.dev20231128 torchvision==0.17.0.dev20231128+rocm5.7 --index-url https://download.pytorch.org/whl/nightly/rocm5.7"
 export COMMANDLINE_ARGS="--api"
EOF