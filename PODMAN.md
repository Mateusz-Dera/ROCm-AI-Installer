# ROCm-AI-Installer
A script that automatically installs the required dependencies to run selected AI applications on AMD Radeon GPUs.

## Info:
[![Version](https://img.shields.io/badge/Version-10.0-orange.svg)](https://github.com/Mateusz-Dera/ROCm-AI-Installer/blob/main/README.md)

> [!Note]
> From version 10.0, the script is distribution-independent thanks to the use of Podman. 
> If the distribution supports <b>Podman</b> and <b>amdgpu</b> is correctly configured, the script should work properly.

> [!Important]
> All models and applications are tested on a GPU with 24GB of VRAM.<br>
> Some applications may not work on GPUs with less VRAM.

### Test platform:
|Name|Info|
|:---|:---|
|CPU|AMD Ryzen 9 9950X3D|
|GPU|AMD Radeon 7900XTX|
|RAM|64GB DDR5 6600MHz|
|Motherboard|Gigabyte X870 AORUS ELITE WIFI7 (BIOS F8)|
|OS|Debian 13.2|
|Kernel|6.12.57+deb13-amd64|
|ROCm|7.1.1|

## Instalation:

1\. Install Podman.

> [!Note]
> If you are using Debian 13.2, you can use <b>sudo apt-get update && sudo apt-get -y install podman podman-compose qemu-system</b> (should also work on Ubuntu 24.04)


2\. Make sure that <b>/dev/dri</b> and <b>/dev/kfd</b> are accessible.
```bash
ls /dev/dri
ls /dev/kfd
```

> [!Important]
> If not, you need to properly configure <b>amdgpu</b> for your distribution.

3\. Make sure that your user has permissions for the <b>video</b> and render <b>groups</b>.

```bash
sudo usermod -aG video,render $USER
```

> [!Important]
> If not, you need reboot after this step.

4\. Clone repository.
```bash
git clone https://github.com/Mateusz-Dera/ROCm-AI-Installer.git
```

5\. By default, the script is configured for AMD Radeon 7900XTX. For other cards and architectures, edit <b>GFX_VERSION</b> and <b>GFX</b> variables in the <b>Dockerfile</b> (not tested).

6\. Run installer. 
```bash
bash ./install.sh
```

7\. Set variables

8\. Create container if you are upgrading or running the script for the first time.

9\. Install selected app.

10\. Go to the installation path with the selected app and run:
```bash
./run.sh
```