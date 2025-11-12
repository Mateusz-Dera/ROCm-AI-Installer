#!/bin/bash

# ROCM-AI-Installer
# Copyright © 2023-2025 Mateusz Dera

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

# Backup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/backup.sh"

# Colors
export NEWT_COLORS='
root=,black
textbox=white,black
border=blue,black
window=white,black
title=yellow,black
button=black,yellow
compactbutton=yellow,black
listbox=white,black
actlistbox=black,white
actsellistbox=black,yellow
checkbox=white,black
actcheckbox=yellow,black
'

# Function to display the main menu
show_menu() {
    choice=$(whiptail --title "ROCm-AI-Installer $version" --menu "Choose an option:" 17 100 10 \
    0 "Installation path ($installation_path)" \
    1 "Install required packages" \
    2 "Text generation" \
    3 "Image & video generation" \
    4 "Music generation" \
    5 "Voice generation" \
    6 "3D models generation" \
    7 "Tools" \
    --cancel-button "Exit" \
    2>&1 > /dev/tty)

    case $choice in
        0)
            set_installation_path
            ;;
        1)
            install
            ;;
        2)
            text_generation
            ;;
        3)
            image_generation
            ;;
        4)
            music_generation
            ;;
        5)
            voice_generation
            ;;
        6)
            d3_generation
            ;;
        7)
            tools
            ;;
        *)
            exit 0
            ;;
    esac
}

# Text generation
text_generation() {
    second=true
    while $second; do
        
        choice=$(whiptail --title "Text generation" --menu "Choose an option:" 15 100 6 --cancel-button "Back" \
            0 "Install KoboldCPP" \
            1 "Text generation web UI" \
            2 "SillyTavern" \
            3 "Install llama.cpp" \
            4 "Ollama" \
            5 "Install vLLM" \
            2>&1 > /dev/tty)
        status=$?
        

        if [ $status -ne 0 ]; then
            return 0
        fi

        case "$choice" in
            "0")
                install_koboldcpp
                ;;
            "1")
                text_generation_web_ui
                ;;
            "2")
                sillytavern
                ;;
            "3")
                install_llama_cpp
                ;;
            "4")
                ollama
                ;;
            "5")
                install_vllm
                ;;
            "")
                echo "Previous menu..."
                second=false
                ;;
            *)
                echo "Invalid selection."
                second=false
                ;;
        esac
    done
}

# Ollama
ollama() {
    second=true
    while $second; do
        
        choice=$(whiptail --title "Ollama" --menu "Choose an option:" 15 100 2 --cancel-button "Back" \
            0 "Install" \
            1 "Uninstall" \
            2>&1 > /dev/tty)
        

        if [ $status -ne 0 ]; then
            return 0
        fi

        case "$choice" in
            "0")
                install_ollama
                ;;
            "1")
                uninstall_ollama
                ;;
            "")
                echo "Previous menu..."
                second=false
                ;;
            *)
                echo "Invalid selection."
                second=false
                ;;
        esac
    done
}

# Text generation web UI
text_generation_web_ui() {
    second=true
    while $second; do
        
        choice=$(whiptail --title "Text generation" --menu "Choose an option:" 15 100 4 --cancel-button "Back" \
            0 "Backup" \
            1 "Install" \
            2 "Restore" \
            2>&1 > /dev/tty)
        

        if [ $status -ne 0 ]; then
            return 0
        fi

        case "$choice" in
            "0")
                text_generation_web_ui_backup
                ;;
            "1")
                install_text_generation_web_ui
                ;;
            "2")
                text_generation_web_ui_restore
                ;;
            "")
                echo "Previous menu..."
                second=false
                ;;
            *)
                echo "Invalid selection."
                second=false
                ;;
        esac
    done
}

text_generation_web_ui_backup() {
    CHOICES=$(whiptail --checklist "Backup:" 14 50 4 --cancel-button "Back" \
        0 "Backup models" ON \
        1 "Backup characters" ON \
        2 "Backup presets" ON \
        3 "Backup instruction-templates" ON 3>&1 1>&2 2>&3)

    status=$?
    
    if [ $status -ne 0 ]; then
        return 0
    fi

    perform_textgen_backup "$CHOICES"
}

text_generation_web_ui_restore() {
    CHOICES=$(whiptail --checklist "Restore:" 14 50 4 --cancel-button "Back" \
        0 "Restore models" ON \
        1 "Restore characters" ON \
        2 "Restore presets" ON \
        3 "Restore instruction-templates" ON 3>&1 1>&2 2>&3)

    status=$?
    
    if [ $status -ne 0 ]; then
        return 0
    fi

    perform_textgen_restore "$CHOICES"
}

# SillyTavern
sillytavern() {
    second=true
    while $second; do
        
        choice=$(whiptail --title "SillyTavern" --menu "Choose an option:" 15 100 4 --cancel-button "Back" \
            0 "Backup" \
            1 "Install" \
            2 "Install WhisperSpeech web UI extension" \
            3 "Restore" \
            2>&1 > /dev/tty)
        status=$?
        

        if [ $status -ne 0 ]; then
            return 0
        fi
        
        case "$choice" in
            "0")
                sillytavern_backup
                ;;
            "1")
                install_sillytavern
                ;;
            "2")
                install_sillytavern_whisperspeech_web_ui
                ;;
            "3")
                sillytavern_restore
                ;;
            "")
                echo "Previous menu..."
                second=true
                ;;
            *)
                echo "Invalid selection."
                second=true
                ;;
        esac
    done
}



# Backup SillyTavern
sillytavern_backup() {
    CHOICES=$(whiptail --checklist "Backup:" 21 50 14 --cancel-button "Back" \
        0 "Backup config.yaml" ON \
        1 "Backup settings.json" ON \
        2 "Backup characters" ON \
        3 "Backup groups" ON \
        4 "Backup worlds" ON \
        5 "Backup chats" ON \
        6 "Backup group chats" ON \
        7 "Backup user avatars images" ON \
        8 "Backup backgrounds images" ON \
        9 "Backup themes" ON \
        10 "Backup presets" ON \
        11 "Backup context" ON \
        12 "Backup instruct" ON \
        13 "Backup sysprompt" ON 3>&1 1>&2 2>&3)

    status=$?
    
    if [ $status -ne 0 ]; then
        return 0
    fi

    perform_sillytavern_backup "$CHOICES"
}

# Restore SillyTavern
sillytavern_restore() {
    CHOICES=$(whiptail --checklist "Restore:" 21 50 14 --cancel-button "Back" \
        0 "Restore config.yaml" ON \
        1 "Restore settings.json" ON \
        2 "Restore characters" ON \
        3 "Restore groups" ON \
        4 "Restore worlds" ON \
        5 "Restore chats" ON \
        6 "Restore group chats" ON \
        7 "Restore user avatars images" ON \
        8 "Restore backgrounds images" ON \
        9 "Restore themes" ON \
        10 "Restore presets" ON \
        11 "Restore context" ON \
        12 "Restore instruct" ON \
        13 "Restore sysprompt" ON 3>&1 1>&2 2>&3)

    status=$?
    
    if [ $status -ne 0 ]; then
        return 0
    fi

    perform_sillytavern_restore "$CHOICES"
}

image_generation() {
    second=true
    while $second; do
        
        choice=$(whiptail --title "Image generation" --menu "Choose an option:" 15 100 2 --cancel-button "Back" \
            0 "ComfyUI" \
            2>&1 > /dev/tty)
        status=$?
        

        if [ $status -ne 0 ]; then
            return 0
        fi

        case "$choice" in
            "0")
                comfyui_addons
                ;;
            "")
                echo "Previous menu..."
                second=false
                ;;
            *)
                echo "Invalid selection."
                second=false
                ;;
        esac
    done
}

comfyui_addons(){
    
    CHOICES=$(whiptail --checklist "Addons:" 17 50 11 --cancel-button "Back" \
        0 "ComfyUI-Manager" ON \
        1 "ComfyUI-GGUF" ON \
        2 "ComfyUI-AuraSR" ON \
        3 "AuraFlow-v0.3" ON \
        4 "FLUX.1-schnell GGUF" ON \
        5 "AnimePro FLUX GGUF" ON \
        6 "Flex.1-alpha GGUF" ON \
        7 "Qwen-Image GGUF" ON \
        8 "Qwen-Image-Edit GGUF" ON \
        9 "Qwen-Image-Edit-2509 GGUF" ON \
        10 "Wan2.2-TI2V-5B" ON  3>&1 1>&2 2>&3)

    status=$?
    

    if [ $status -ne 0 ]; then
        return 0
    fi

    install_comfyui $CHOICES
}

music_generation() {
    second=true
    while $second; do
        
        choice=$(whiptail --title "Music generation" --menu "Choose an option:" 15 100 1 --cancel-button "Back" \
            0 "Install ACE-Step" \
            2>&1 > /dev/tty)

        case "$choice" in
            "0")
                install_ace_step
                ;;
            "")
                echo "Previous menu..."
                second=false
                ;;
            *)
                echo "Invalid selection."
                second=false
                ;;
        esac
        status=$?
        

        if [ $status -ne 0 ]; then
            return 0
        fi
    done
}

voice_generation() {
    second=true
    while $second; do
        
        choice=$(whiptail --title "Voice generation" --menu "Choose an option:" 15 100 7 --cancel-button "Back" \
            0 "Install WhisperSpeech web UI" \
            1 "Install F5-TTS" \
            2 "Install Matcha-TTS" \
            3 "Install Dia" \
            4 "Install IMS-Toucan" \
            5 "Install Chatterbox Multilingual" \
            6 "Install KaniTTS" \
            2>&1 > /dev/tty)

        case "$choice" in
            "0")
                install_whisperspeech_web_ui
                ;;
            "1")
                install_f5_tts
                ;;
            "2")
                install_matcha_tts
                ;;
            "3")
                install_dia
                ;;
            "4")
                install_ims_toucan
                ;;
            "5")
                install_chatterbox
                ;;
            "6")
                install_kanitts
                ;;
            "")
                echo "Previous menu..."
                second=false
                ;;
            *)
                echo "Invalid selection."
                second=false
                ;;
        esac
        status=$?
        

        if [ $status -ne 0 ]; then
            return 0
        fi
    done
}

d3_generation() {
    second=true
    while $second; do
        
        choice=$(whiptail --title "3D generation" --menu "Choose an option:" 15 100 1 --cancel-button "Back" \
            0 "Install PartCrafter" \
            2>&1 > /dev/tty)

        case "$choice" in
            "0")
                install_partcrafter
                ;;
            "")
                echo "Previous menu..."
                second=false
                ;;
            *)
                echo "Invalid selection."
                second=false
                ;;
        esac
        status=$?
        

        if [ $status -ne 0 ]; then
            return 0
        fi
    done
}

tools() {
    second=true
    while $second; do
        choice=$(whiptail --title "Tools" --menu "Choose an option:" 15 100 1 --cancel-button "Back" \
            0 "Install Fastfetch" \
            2>&1 > /dev/tty)

        case "$choice" in
            "0")
                fastfetch_menu
                ;;
            "")
                echo "Previous menu..."
                second=false
                ;;
            *)
                echo "Invalid selection."
                second=false
                ;;
        esac
        status=$?
        

        if [ $status -ne 0 ]; then
            return 0
        fi
    done
}

fastfetch_menu() {
    second=true
    while $second; do
        choice=$(whiptail --title "Fastfetch" --menu "Choose configuration:" 15 100 4 --cancel-button "Back" \
            0 "English" \
            1 "Polish" \
            2 "English - no logo" \
            3 "Polish - no logo" \
            2>&1 > /dev/tty)
        status=$?
        

        if [ $status -ne 0 ]; then
            return 0
        fi

        case "$choice" in
            "0")
                install_fastfetch "english"
                second=false
                ;;
            "1")
                install_fastfetch "polish"
                second=false
                ;;
            "2")
                install_fastfetch "english_no_logo"
                second=false
                ;;
            "3")
                install_fastfetch "polish_no_logo"
                second=false
                ;;
            "")
                echo "Previous menu..."
                second=false
                ;;
            *)
                echo "Invalid selection."
                second=false
                ;;
        esac
    done
}