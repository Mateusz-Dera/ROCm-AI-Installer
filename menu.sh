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

# Colors
export NEWT_COLORS='
root=,black
textbox=white,black
border=cyan,black
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
    1 "Install ROCm and required packages" \
    2 "Text generation" \
    3 "Image generation" \
    4 "Video generation" \
    5 "Music generation" \
    6 "Voice generation" \
    7 "3D models generation" \
    8 "Tools" \
    --cancel-button "Exit" \
    2>&1 > /dev/tty)

    case $choice in
        0)
            set_installation_path
            ;;
        1)
            install_rocm
            ;;
        2)
            text_generation
            ;;
        3)
            image_generation
            ;;
         4)
            video_generation
            ;;
        5)
            music_generation
            ;;
        6)
            voice_generation
            ;;
        7)
            d3_generation
            ;;
        8)
            tools
            ;;
        *)
            ;;
    esac
}

# Text generation
text_generation() {
    second=true
    while $second; do
        set +e
        choice=$(whiptail --title "Text generation" --menu "Choose an option:" 15 100 4 --cancel-button "Back" \
            0 "Install KoboldCPP" \
            1 "Text generation web UI" \
            2 "SillyTavern" \
            3 "Install llama.cpp" \
            2>&1 > /dev/tty)
        status=$?
        set -e

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
        set +e
        choice=$(whiptail --title "Text generation" --menu "Choose an option:" 15 100 4 --cancel-button "Back" \
            0 "Backup" \
            1 "Install" \
            2 "Restore" \
            2>&1 > /dev/tty)
        set -e

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
    set +e
    CHOICES=$(whiptail --checklist "Addons:" 20 50 14 --cancel-button "Back" \
        0 "Backup models" ON \
        1 "Backup characters" ON \
        2 "Backup presets" ON \
        3 "Backup instruction-templates" ON 3>&1 1>&2 2>&3)

    status=$?
    set -e

    if [ $status -ne 0 ]; then
        return 0
    fi

    for choice in $CHOICES; do
        echo $choice
        case $choice in
            '"0"')
                backup_and_restore $installation_path/text-generation-webui/models $installation_path/Backups/text-generation-webui/models
                ;;
            '"1"')
                backup_and_restore $installation_path/text-generation-webui/characters $installation_path/Backups/text-generation-webui/characters
                ;;
            '"2"')
                backup_and_restore $installation_path/text-generation-webui/presets $installation_path/Backups/text-generation-webui/presets
                ;;
            '"3"')
                backup_and_restore $installation_path/text-generation-webui/instruction-templates $installation_path/Backups/text-generation-webui/instruction-templates
            *)
                echo "Invalid selection."
                ;;
        esac
    done
}

text_generation_web_ui_restore() {
    set +e
    CHOICES=$(whiptail --checklist "Addons:" 20 50 14 --cancel-button "Back" \
        0 "Restore models" ON \
        1 "Restore characters" ON \
        2 "Restore presets" ON \
        3 "Restore instruction-templates" ON 3>&1 1>&2 2>&3)

    status=$?
    set -e

    if [ $status -ne 0 ]; then
        return 0
    fi

    for choice in $CHOICES; do
        echo $choice
        case $choice in
            '"0"')
                backup_and_restore $installation_path/Backups/text-generation-webui/models $installation_path/text-generation-webui/models
                ;;
            '"1"')
                backup_and_restore $installation_path/Backups/text-generation-webui/characters $installation_path/text-generation-webui/characters
                ;;
            '"2"')
                backup_and_restore $installation_path/Backups/text-generation-webui/presets $installation_path/text-generation-webui/presets
                ;;
            '"3"')
                backup_and_restore $installation_path/Backups/text-generation-webui/instruction-templates $installation_path/text-generation-webui/instruction-templates
            *)
                echo "Invalid selection."
                ;;
        esac
    done
}

# SillyTavern
sillytavern() {
    second=true
    while $second; do
        set +e
        choice=$(whiptail --title "SillyTavern" --menu "Choose an option:" 15 100 3 --cancel-button "Back" \
            0 "Backup" \
            1 "Install" \
            2 "Restore" \
            2>&1 > /dev/tty)
        status=$?
        set -e

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


sillytavern_backup() {
    set +e
    CHOICES=$(whiptail --checklist "Addons:" 20 50 14 --cancel-button "Back" \
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
    set -e

    if [ $status -ne 0 ]; then
        return 0
    fi

    for choice in $CHOICES; do
        echo $choice
        case $choice in
            '"0"')
                backup_and_restore_file $installation_path/SillyTavern $installation_path/Backups/SillyTavern config.yaml
                ;;
            '"1"')
                backup_and_restore_file $installation_path/SillyTavern/data/default-user $installation_path/Backups/SillyTavern/data/default-user settings.json
                ;;
            '"2"')
                backup_and_restore $installation_path/SillyTavern/data/default-user/characters $installation_path/Backups/SillyTavern/data/default-user/characters
                ;;
            '"3"')
                backup_and_restore $installation_path/SillyTavern/data/default-user/groups $installation_path/Backups/SillyTavern/data/default-user/groups
                ;;
            '"4"')
                backup_and_restore $installation_path/SillyTavern/data/default-user/worlds $installation_path/Backups/SillyTavern/data/default-user/worlds
                ;;
            '"5"')
                backup_and_restore $installation_path/SillyTavern/data/default-user/chats $installation_path/Backups/SillyTavern/data/default-user/chats
                ;;
            '"6"')
                backup_and_restore $installation_path/SillyTavern/data/default-user/group\ chats $installation_path/Backups/SillyTavern/data/default-user/group\ chats
                ;;
            '"7"')
                backup_and_restore $installation_path/SillyTavern/data/default-user/User\ Avatars $installation_path/Backups/SillyTavern/data/default-user/User\ Avatars
                ;;
            '"8"')
                backup_and_restore $installation_path/SillyTavern/data/default-user/backgrounds $installation_path/Backups/SillyTavern/data/default-user/backgrounds
                ;;
            '"9"')
                backup_and_restore $installation_path/SillyTavern/data/default-user/themes $installation_path/Backups/SillyTavern/data/default-user/themes
                ;;
            '"10"')
                backup_and_restore $installation_path/SillyTavern/data/default-user/TextGen\ Settings $installation_path/Backups/SillyTavern/data/default-user/TextGen\ Settings
                ;;
            '"11"')
                backup_and_restore $installation_path/SillyTavern/data/default-user/context $installation_path/Backups/SillyTavern/data/default-user/context
                ;;
            '"12"')
                backup_and_restore $installation_path/SillyTavern/data/default-user/instruct $installation_path/Backups/SillyTavern/data/default-user/instruct
                ;;
            '"13"')
                backup_and_restore $installation_path/SillyTavern/data/default-user/sysprompt $installation_path/Backups/SillyTavern/data/default-user/sysprompt
                ;;
            *)
                echo "Invalid selection."
                ;;
        esac
    done
    sillytavern
}

sillytavern_restore() {
    set +e
    CHOICES=$(whiptail --checklist "Addons:" 20 50 14 --cancel-button "Back" \
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
    set -e

    if [ $status -ne 0 ]; then
        return 0
    fi

    for choice in $CHOICES; do
        echo $choice
        case $choice in
            '"0"')
                backup_and_restore_file $installation_path/Backups/SillyTavern $installation_path/SillyTavern config.yaml
                ;;
            '"1"')
                backup_and_restore_file $installation_path/Backups/SillyTavern/data/default-user $installation_path/SillyTavern/data/default-user settings.json
                ;;
            '"2"')
                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/characters $installation_path/SillyTavern/data/default-user/characters
                ;;
            '"3"')
                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/groups $installation_path/SillyTavern/data/default-user/groups
                ;;
            '"4"')
                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/worlds $installation_path/SillyTavern/data/default-user/worlds
                ;;
            '"5"')
                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/chats $installation_path/SillyTavern/data/default-user/chats
                ;;
            '"6"')
                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/group\ chats $installation_path/SillyTavern/data/default-user/group\ chats
                ;;
            '"7"')
                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/User\ Avatars $installation_path/SillyTavern/data/default-user/User\ Avatars
                ;;
            '"8"')
                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/backgrounds $installation_path/SillyTavern/data/default-user/backgrounds
                ;;
            '"9"')
                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/themes $installation_path/SillyTavern/data/default-user/themes
                ;;
            '"10"')
                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/TextGen\ Settings $installation_path/SillyTavern/data/default-user/TextGen\ Settings
                ;;
            '"11"')
                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/context $installation_path/SillyTavern/data/default-user/context
                ;;
            '"12"')
                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/instruct $installation_path/SillyTavern/data/default-user/instruct
                ;;
            '"13"')
                backup_and_restore $installation_path/Backups/SillyTavern/data/default-user/sysprompt $installation_path/SillyTavern/data/default-user/sysprompt
                ;;
            *)
                echo "Invalid selection."
                ;;
        esac
    done
    sillytavern
}

image_generation() {
    second=true
    while $second; do
        set +e
        choice=$(whiptail --title "Image generation" --menu "Choose an option:" 15 100 3 --cancel-button "Back" \
            0 "Install ComfyUI" \
            1 "Install Artist" \
            2 "Install Animagine XL 4.0" \
            2>&1 > /dev/tty)
        status=$?
        set -e

        if [ $status -ne 0 ]; then
            return 0
        fi

        case "$choice" in
            "0")
                comfyui_addons
                ;;
            "1")
                install_artist
                ;;
            "2")
                install_animagine
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
    set +e
    CHOICES=$(whiptail --checklist "Addons:" 17 50 7 --cancel-button "Back" \
        0 "ComfyUI-Manager" ON \
        1 "ComfyUI-GGUF" ON \
        2 "ComfyUI-AuraSR" ON \
        3 "AuraFlow-v0.3" ON \
        4 "FLUX.1-schnell GGUF" ON \
        5 "AnimePro FLUX GGUF" ON \
        6 "Flex.1-alpha GGUF" ON 3>&1 1>&2 2>&3)

    status=$?
    set -e

    if [ $status -ne 0 ]; then
        return 0
    fi

    install_comfyui $CHOICES
}

video_generation() {
    second=true
    while $second; do
        set +e
        choice=$(whiptail --title "Video generation" --menu "Choose an option:" 15 100 1 --cancel-button "Back" \
            0 "Install AudioCraft" \
            2>&1 > /dev/tty)

        case "$choice" in
            "0")
                install_cinemo
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
        set -e

        if [ $status -ne 0 ]; then
            return 0
        fi
    done
}

music_generation() {
    second=true
    while $second; do
        set +e
        choice=$(whiptail --title "Music generation" --menu "Choose an option:" 15 100 1 --cancel-button "Back" \
            0 "Install AudioCraft" \
            2>&1 > /dev/tty)

        case "$choice" in
            "0")
                install_audiocraft
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
        set -e

        if [ $status -ne 0 ]; then
            return 0
        fi
    done
}

voice_generation() {
    second=true
    while $second; do
        set +e
        choice=$(whiptail --title "Voice generation" --menu "Choose an option:" 15 100 7 --cancel-button "Back" \
            0 "Install WhisperSpeech web UI" \
            1 "Install MeloTTS" \
            2 "Install MetaVoice" \
            3 "Install F5-TTS" \
            4 "Install Matcha-TTS" \
            5 "Install StableTTS" \
            6 "Install Dia" \
            2>&1 > /dev/tty)

        case "$choice" in
            "0")
                install_whisperspeech_web_ui
                ;;
            "1")
                install_melotts
                ;;
            "2")
                install_metavoice
                ;;
            "3")
                install_f5_tts
                ;;
            "4")
                install_matcha_tts
                ;;
            "5")
                install_stabletts
                ;;
            "6")
                install_dia
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
        set -e

        if [ $status -ne 0 ]; then
            return 0
        fi
    done
}

d3_generation() {
    second=true
    while $second; do
        set +e
        choice=$(whiptail --title "3D generation" --menu "Choose an option:" 15 100 2 --cancel-button "Back" \
            0 "Install TripoSR" \
            1 "Install TripoSG" \
            2>&1 > /dev/tty)

        case "$choice" in
            "0")
                install_triposr
                ;;
            "1")
                install_triposg
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
        set -e

        if [ $status -ne 0 ]; then
            return 0
        fi
    done
}

tools() {
    second=true
    while $second; do
        set +e
        choice=$(whiptail --title "Tools" --menu "Choose an option:" 15 100 1 --cancel-button "Back" \
            0 "Install Fastfetch" \
            2>&1 > /dev/tty)

        case "$choice" in
            "0")
                install_fastfetch
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
        set -e

        if [ $status -ne 0 ]; then
            return 0
        fi
    done
}