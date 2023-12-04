#!/bin/bash
sudo apt update
sudo apt -y upgrade

installation_path="/home/mdera/AI"
export HSA_OVERRIDE_GFX_VERSION=11.0.0

sudo apt install -y git

mkdir -p $installation_path
cd $installation_path
rm -Rf SillyTavern
git clone https://github.com/SillyTavern/SillyTavern.git
cd SillyTavern
sudo snap install node --classic