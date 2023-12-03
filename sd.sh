#!/bin/bash
sudo apt update
sudo apt -y upgrade

installation_path="/home/mdera/AI"
arch="x86_64"
export HSA_OVERRIDE_GFX_VERSION=11.0.0

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

sudo apt -y install wget git git-lfs libstdc++-12-dev libtcmalloc-minimal4 python3 python3-venv libgl1 libglib2.0-0 amdgpu-dkms rocm-dev rocm-libs rocm-hip-sdk rocm-dkms rocm-libs

#TODO if python3.11 missing exit script

sudo rm /etc/ld.so.conf.d/rocm.conf
sudo tee --append /etc/ld.so.conf.d/rocm.conf <<EOF
/opt/rocm/lib
/opt/rocm/lib64
EOF
sudo ldconfig

mkdir -p $installation_path
cd $installation_path
rm -rf text-generation-webui
git clone https://github.com/oobabooga/text-generation-webui
cd text-generation-webui
python3.11 -m venv .venv
source .venv/bin/activate
pip install --pre cmake colorama filelock lit numpy Pillow Jinja2 \
	mpmath fsspec MarkupSafe certifi filelock networkx \
	sympy packaging requests \
         --index-url https://download.pytorch.org/whl/nightly/rocm5.7
pip install --pre torch==2.2.0.dev20231128   --index-url https://download.pytorch.org/whl/nightly/rocm5.7
pip install torchdata==0.7.1
pip install --pre torch==2.2.0.dev20231128 torchvision==0.17.0.dev20231128+rocm5.7 torchtext==0.17.0.dev20231128+cpu torchaudio triton pytorch-triton pytorch-triton-rocm    --index-url https://download.pytorch.org/whl/nightly/rocm5.7

cd $installation_path
rm -rf bitsandbytes-rocm-5.6
git clone https://github.com/arlo-phoenix/bitsandbytes-rocm-5.6.git
cd bitsandbytes-rocm-5.6/
BUILD_CUDA_EXT=0 pip install -r requirements.txt --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7
make hip ROCM_TARGET=gfx1100 ROCM_HOME=/opt/rocm-5.7.2/
pip install . --extra-index-url https://download.pytorch.org/whl/nightly/rocm5.7

pip install -U --index-url https://aiinfra.pkgs.visualstudio.com/PublicPackages/_packaging/Triton-Nightly/pypi/simple/ triton-nightly

pip install cmake ninja

cd $installation_path
rm -rf flash-attention
git clone https://github.com/ROCmSoftwarePlatform/flash-attention.git
cd flash-attention
pip install . --offload-arch $arch

cd $installation_path/text-generation-webui
sed -i "s@bitsandbytes==@bitsandbytes>=@g" requirements_amd.txt 
pip install -r requirements_amd.txt 

git clone https://github.com/turboderp/exllama repositories/exllama
git clone https://github.com/turboderp/exllamav2 repositories/exllamav2

tee --append run.sh <<EOF
#!/bin/bash
source $installation_path/text-generation-webui/.venv/bin/activate
python server.py --listen --loader=exllama  \
  --auto-devices --extensions sd_api_pictures send_pictures gallery 
EOF
chmod u+x run.sh