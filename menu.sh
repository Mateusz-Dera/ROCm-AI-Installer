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
border=magenta,black
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
            install_rocm
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
        
        choice=$(whiptail --title "Text generation" --menu "Choose an option:" 15 100 5 --cancel-button "Back" \
            0 "Install KoboldCPP" \
            1 "Text generation web UI" \
            2 "SillyTavern" \
            3 "Install llama.cpp" \
            4 "Ollama" \
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

    # Arrays to keep track of successes and failures
    successful_backups=()
    failed_backups=()

    for choice in $CHOICES; do
        echo $choice
        case $choice in
            '"0"')
                if backup_and_restore "$installation_path/text-generation-webui/user_data/models" "$installation_path/Backups/text-generation-webui/user_data/models"; then
                    successful_backups+=("models folder")
                else
                    failed_backups+=("models folder")
                fi
                ;;
            '"1"')
                if backup_and_restore "$installation_path/text-generation-webui/user_data/characters" "$installation_path/Backups/text-generation-webui/user_data/characters"; then
                    successful_backups+=("characters folder")
                else
                    failed_backups+=("characters folder")
                fi
                ;;
            '"2"')
                if backup_and_restore "$installation_path/text-generation-webui/user_data/presets" "$installation_path/Backups/text-generation-webui/user_data/presets"; then
                    successful_backups+=("presets folder")
                else
                    failed_backups+=("presets folder")
                fi
                ;;
            '"3"')
                if backup_and_restore "$installation_path/text-generation-webui/user_data/instruction-templates" "$installation_path/Backups/text-generation-webui/user_data/instruction-templates"; then
                    successful_backups+=("instruction-templates folder")
                else
                    failed_backups+=("instruction-templates folder")
                fi
                ;;
            *)
                echo "Invalid selection."
                ;;
        esac
    done

    # Create summary message - put failures first
    failure_msg=""
    success_msg=""
    
    if [ ${#failed_backups[@]} -gt 0 ]; then
        failure_msg="Failed to back up:\n"
        for item in "${failed_backups[@]}"; do
            failure_msg+="• $item\n"
        done
        failure_msg+="\n"
    fi
    
    if [ ${#successful_backups[@]} -gt 0 ]; then
        success_msg="Successfully backed up:\n"
        for item in "${successful_backups[@]}"; do
            success_msg+="• $item\n"
        done
    fi
    
    summary_title="Backup Summary"
    
    if [ ${#failed_backups[@]} -eq 0 ]; then
        summary_title="Backup Summary - All Successful"
    fi
    
    # Always show both failure and success messages (if any)
    # Put failures first as they're more important for users to see immediately
    summary_msg=""
    
    if [ ${#failed_backups[@]} -gt 0 ]; then
        summary_msg+="${failure_msg}"
    else
        summary_msg+="No failures detected.\n\n"
    fi
    
    summary_msg+="${success_msg}"
    
    whiptail --title "$summary_title" --msgbox "$summary_msg" 14 70
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

    # Arrays to keep track of successes and failures
    successful_restores=()
    failed_restores=()

    for choice in $CHOICES; do
        echo $choice
        case $choice in
            '"0"')
                if backup_and_restore "$installation_path/Backups/text-generation-webui/user_data/models" "$installation_path/text-generation-webui/user_data/models"; then
                    successful_restores+=("models folder")
                else
                    failed_restores+=("models folder")
                fi
                ;;
            '"1"')
                if backup_and_restore "$installation_path/Backups/text-generation-webui/user_data/characters" "$installation_path/text-generation-webui/user_data/characters"; then
                    successful_restores+=("characters folder")
                else
                    failed_restores+=("characters folder")
                fi
                ;;
            '"2"')
                if backup_and_restore "$installation_path/Backups/text-generation-webui/user_data/presets" "$installation_path/text-generation-webui/user_data/presets"; then
                    successful_restores+=("presets folder")
                else
                    failed_restores+=("presets folder")
                fi
                ;;
            '"3"')
                if backup_and_restore "$installation_path/Backups/text-generation-webui/user_data/instruction-templates" "$installation_path/text-generation-webui/user_data/instruction-templates"; then
                    successful_restores+=("instruction-templates folder")
                else
                    failed_restores+=("instruction-templates folder")
                fi
                ;;
            *)
                echo "Invalid selection."
                ;;
        esac
    done

    # Create summary message - put failures first
    failure_msg=""
    success_msg=""
    
    if [ ${#failed_restores[@]} -gt 0 ]; then
        failure_msg="Failed to restore:\n"
        for item in "${failed_restores[@]}"; do
            failure_msg+="• $item\n"
        done
        failure_msg+="\n"
    fi
    
    if [ ${#successful_restores[@]} -gt 0 ]; then
        success_msg="Successfully restored:\n"
        for item in "${successful_restores[@]}"; do
            success_msg+="• $item\n"
        done
    fi
    
    summary_title="Restore Summary"
    
    if [ ${#failed_restores[@]} -eq 0 ]; then
        summary_title="Restore Summary - All Successful"
    fi
    
    # Always show both failure and success messages (if any)
    # Put failures first as they're more important for users to see immediately
    summary_msg=""
    
    if [ ${#failed_restores[@]} -gt 0 ]; then
        summary_msg+="${failure_msg}"
    else
        summary_msg+="No failures detected.\n\n"
    fi
    
    summary_msg+="${success_msg}"
    
    whiptail --title "$summary_title" --msgbox "$summary_msg" 14 70
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


backup_and_restore() {
    local success=true
    local error_message=""
    
    # Check if folder exists
    if ! [ -e "$1" ]; then
        echo "Folder or file '$1' does not exist."
        return 1
    fi

    if ! [ -d "$2" ]; then
        # Create backup folder
        if ! mkdir -p "$2"; then
            echo "Failed to create folder '$2'."
            return 1
        fi
    else
        if ! rm -rf "$2"; then
            echo "Failed to remove old folder '$2'."
            return 1
        fi
    fi

    # Copy the contents $1 to $2
    if ! rsync -av --progress --delete "$1/" "$2" 2>/dev/null; then
        echo "Failed to copy contents of '$1' to '$2'."
        return 1
    fi
    
    return 0
}

backup_and_restore_file() {
    # Check if file exists
    if ! [ -e "$1/$3" ]; then
        echo "File '$1/$3' does not exist."
        return 1
    fi

    if ! [ -d "$2" ]; then
        # Create backup folder
        if ! mkdir -p "$2"; then
            echo "Failed to create folder '$2'."
            return 1
        fi
    fi

    # Copy the contents $1 to $2
    if ! cp -f "$1/$3" "$2/$3" 2>/dev/null; then
        echo "Failed to copy contents of '$1/$3' to '$2'."
        return 1
    fi
    
    return 0
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

    # Arrays to keep track of successes and failures
    successful_backups=()
    failed_backups=()

    for choice in $CHOICES; do
        echo $choice
        case $choice in
            '"0"')
                if backup_and_restore_file "$installation_path/SillyTavern" "$installation_path/Backups/SillyTavern" "config.yaml"; then
                    successful_backups+=("config.yaml")
                else
                    failed_backups+=("config.yaml")
                fi
                ;;
            '"1"')
                if backup_and_restore_file "$installation_path/SillyTavern/data/default-user" "$installation_path/Backups/SillyTavern/data/default-user" "settings.json"; then
                    successful_backups+=("settings.json")
                else
                    failed_backups+=("settings.json")
                fi
                ;;
            '"2"')
                if backup_and_restore "$installation_path/SillyTavern/data/default-user/characters" "$installation_path/Backups/SillyTavern/data/default-user/characters"; then
                    successful_backups+=("characters folder")
                else
                    failed_backups+=("characters folder")
                fi
                ;;
            '"3"')
                if backup_and_restore "$installation_path/SillyTavern/data/default-user/groups" "$installation_path/Backups/SillyTavern/data/default-user/groups"; then
                    successful_backups+=("groups folder")
                else
                    failed_backups+=("groups folder")
                fi
                ;;
            '"4"')
                if backup_and_restore "$installation_path/SillyTavern/data/default-user/worlds" "$installation_path/Backups/SillyTavern/data/default-user/worlds"; then
                    successful_backups+=("worlds folder")
                else
                    failed_backups+=("worlds folder")
                fi
                ;;
            '"5"')
                if backup_and_restore "$installation_path/SillyTavern/data/default-user/chats" "$installation_path/Backups/SillyTavern/data/default-user/chats"; then
                    successful_backups+=("chats folder")
                else
                    failed_backups+=("chats folder")
                fi
                ;;
            '"6"')
                if backup_and_restore "$installation_path/SillyTavern/data/default-user/group chats" "$installation_path/Backups/SillyTavern/data/default-user/group chats"; then
                    successful_backups+=("group chats folder")
                else
                    failed_backups+=("group chats folder")
                fi
                ;;
            '"7"')
                if backup_and_restore "$installation_path/SillyTavern/data/default-user/User Avatars" "$installation_path/Backups/SillyTavern/data/default-user/User Avatars"; then
                    successful_backups+=("User Avatars folder")
                else
                    failed_backups+=("User Avatars folder")
                fi
                ;;
            '"8"')
                if backup_and_restore "$installation_path/SillyTavern/data/default-user/backgrounds" "$installation_path/Backups/SillyTavern/data/default-user/backgrounds"; then
                    successful_backups+=("backgrounds folder")
                else
                    failed_backups+=("backgrounds folder")
                fi
                ;;
            '"9"')
                if backup_and_restore "$installation_path/SillyTavern/data/default-user/themes" "$installation_path/Backups/SillyTavern/data/default-user/themes"; then
                    successful_backups+=("themes folder")
                else
                    failed_backups+=("themes folder")
                fi
                ;;
            '"10"')
                if backup_and_restore "$installation_path/SillyTavern/data/default-user/TextGen Settings" "$installation_path/Backups/SillyTavern/data/default-user/TextGen Settings"; then
                    successful_backups+=("TextGen Settings folder")
                else
                    failed_backups+=("TextGen Settings folder")
                fi
                ;;
            '"11"')
                if backup_and_restore "$installation_path/SillyTavern/data/default-user/context" "$installation_path/Backups/SillyTavern/data/default-user/context"; then
                    successful_backups+=("context folder")
                else
                    failed_backups+=("context folder")
                fi
                ;;
            '"12"')
                if backup_and_restore "$installation_path/SillyTavern/data/default-user/instruct" "$installation_path/Backups/SillyTavern/data/default-user/instruct"; then
                    successful_backups+=("instruct folder")
                else
                    failed_backups+=("instruct folder")
                fi
                ;;
            '"13"')
                if backup_and_restore "$installation_path/SillyTavern/data/default-user/sysprompt" "$installation_path/Backups/SillyTavern/data/default-user/sysprompt"; then
                    successful_backups+=("sysprompt folder")
                else
                    failed_backups+=("sysprompt folder")
                fi
                ;;
            *)
                echo "Invalid selection."
                ;;
        esac
    done

    # Create summary message - put failures first
    failure_msg=""
    success_msg=""
    
    if [ ${#failed_backups[@]} -gt 0 ]; then
        failure_msg="Failed to back up:\n"
        for item in "${failed_backups[@]}"; do
            failure_msg+="• $item\n"
        done
        failure_msg+="\n"
    fi
    
    if [ ${#successful_backups[@]} -gt 0 ]; then
        success_msg="Successfully backed up:\n"
        for item in "${successful_backups[@]}"; do
            success_msg+="• $item\n"
        done
    fi
    
    summary_title="Backup Summary"
    
    if [ ${#failed_backups[@]} -eq 0 ]; then
        summary_title="Backup Summary - All Successful"
    fi
    
    # Always show both failure and success messages (if any)
    # Put failures first as they're more important for users to see immediately
    summary_msg=""
    
    if [ ${#failed_backups[@]} -gt 0 ]; then
        summary_msg+="${failure_msg}"
    else
        summary_msg+="No failures detected.\n\n"
    fi
    
    summary_msg+="${success_msg}"
    
    whiptail --title "$summary_title" --msgbox "$summary_msg" 22 70
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

    # Arrays to keep track of successes and failures
    successful_backups=()
    failed_backups=()

    for choice in $CHOICES; do
        echo $choice
        case $choice in
            '"0"')
                if backup_and_restore_file "$installation_path/Backups/SillyTavern" "$installation_path/SillyTavern" "config.yaml"; then
                    successful_backups+=("config.yaml")
                else
                    failed_backups+=("config.yaml")
                fi
                ;;
            '"1"')
                if backup_and_restore_file "$installation_path/Backups/SillyTavern/data/default-user" "$installation_path/SillyTavern/data/default-user" "settings.json"; then
                    successful_backups+=("settings.json")
                else
                    failed_backups+=("settings.json")
                fi
                ;;
            '"2"')
                if backup_and_restore "$installation_path/Backups/SillyTavern/data/default-user/characters" "$installation_path/SillyTavern/data/default-user/characters"; then
                    successful_backups+=("characters folder")
                else
                    failed_backups+=("characters folder")
                fi
                ;;
            '"3"')
                if backup_and_restore "$installation_path/Backups/SillyTavern/data/default-user/groups" "$installation_path/SillyTavern/data/default-user/groups"; then
                    successful_backups+=("groups folder")
                else
                    failed_backups+=("groups folder")
                fi
                ;;
            '"4"')
                if backup_and_restore "$installation_path/Backups/SillyTavern/data/default-user/worlds" "$installation_path/SillyTavern/data/default-user/worlds"; then
                    successful_backups+=("worlds folder")
                else
                    failed_backups+=("worlds folder")
                fi
                ;;
            '"5"')
                if backup_and_restore "$installation_path/Backups/SillyTavern/data/default-user/chats" "$installation_path/SillyTavern/data/default-user/chats"; then
                    successful_backups+=("chats folder")
                else
                    failed_backups+=("chats folder")
                fi
                ;;
            '"6"')
                if backup_and_restore "$installation_path/Backups/SillyTavern/data/default-user/group chats" "$installation_path/SillyTavern/data/default-user/group chats"; then
                    successful_backups+=("group chats folder")
                else
                    failed_backups+=("group chats folder")
                fi
                ;;
            '"7"')
                if backup_and_restore "$installation_path/Backups/SillyTavern/data/default-user/User Avatars" "$installation_path/SillyTavern/data/default-user/User Avatars"; then
                    successful_backups+=("User Avatars folder")
                else
                    failed_backups+=("User Avatars folder")
                fi
                ;;
            '"8"')
                if backup_and_restore "$installation_path/Backups/SillyTavern/data/default-user/backgrounds" "$installation_path/SillyTavern/data/default-user/backgrounds"; then
                    successful_backups+=("backgrounds folder")
                else
                    failed_backups+=("backgrounds folder")
                fi
                ;;
            '"9"')
                if backup_and_restore "$installation_path/Backups/SillyTavern/data/default-user/themes" "$installation_path/SillyTavern/data/default-user/themes"; then
                    successful_backups+=("themes folder")
                else
                    failed_backups+=("themes folder")
                fi
                ;;
            '"10"')
                if backup_and_restore "$installation_path/Backups/SillyTavern/data/default-user/TextGen Settings" "$installation_path/SillyTavern/data/default-user/TextGen Settings"; then
                    successful_backups+=("TextGen Settings folder")
                else
                    failed_backups+=("TextGen Settings folder")
                fi
                ;;
            '"11"')
                if backup_and_restore "$installation_path/Backups/SillyTavern/data/default-user/context" "$installation_path/SillyTavern/data/default-user/context"; then
                    successful_backups+=("context folder")
                else
                    failed_backups+=("context folder")
                fi
                ;;
            '"12"')
                if backup_and_restore "$installation_path/Backups/SillyTavern/data/default-user/instruct" "$installation_path/SillyTavern/data/default-user/instruct"; then
                    successful_backups+=("instruct folder")
                else
                    failed_backups+=("instruct folder")
                fi
                ;;
            '"13"')
                if backup_and_restore "$installation_path/Backups/SillyTavern/data/default-user/sysprompt" "$installation_path/SillyTavern/data/default-user/sysprompt"; then
                    successful_backups+=("sysprompt folder")
                else
                    failed_backups+=("sysprompt folder")
                fi
                ;;
            *)
                echo "Invalid selection."
                ;;
        esac
    done

    # Create summary message - put failures first
    failure_msg=""
    success_msg=""
    
    if [ ${#failed_backups[@]} -gt 0 ]; then
        failure_msg="Failed to restore:\n"
        for item in "${failed_backups[@]}"; do
            failure_msg+="• $item\n"
        done
        failure_msg+="\n"
    fi
    
    if [ ${#successful_backups[@]} -gt 0 ]; then
        success_msg="Successfully restored:\n"
        for item in "${successful_backups[@]}"; do
            success_msg+="• $item\n"
        done
    fi
    
    summary_title="Restore Summary"
    
    if [ ${#failed_backups[@]} -eq 0 ]; then
        summary_title="Restore Summary - All Successful"
    fi
    
    # Always show both failure and success messages (if any)
    # Put failures first as they're more important for users to see immediately
    summary_msg=""
    
    if [ ${#failed_backups[@]} -gt 0 ]; then
        summary_msg+="${failure_msg}"
    else
        summary_msg+="No failures detected.\n\n"
    fi
    
    summary_msg+="${success_msg}"
    
    whiptail --title "$summary_title" --msgbox "$summary_msg" 22 70
}

image_generation() {
    second=true
    while $second; do
        
        choice=$(whiptail --title "Image generation" --menu "Choose an option:" 15 100 4 --cancel-button "Back" \
            0 "ComfyUI" \
            1 "Install Cinemo" \
            2 "Install Ovis-U1-3B" \
            2>&1 > /dev/tty)
        status=$?
        

        if [ $status -ne 0 ]; then
            return 0
        fi

        case "$choice" in
            "0")
                comfyui_addons
                ;;
            "1")
                install_cinemo
                ;;
            "2")
                install_ovis
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
    
    CHOICES=$(whiptail --checklist "Addons:" 17 50 8 --cancel-button "Back" \
        0 "ComfyUI-Manager" ON \
        1 "ComfyUI-GGUF" ON \
        2 "ComfyUI-AuraSR" ON \
        3 "AuraFlow-v0.3" ON \
        4 "FLUX.1-schnell GGUF" ON \
        5 "AnimePro FLUX GGUF" ON \
        6 "Flex.1-alpha GGUF" ON \
        7 "Qwen-Image GGUF" ON 3>&1 1>&2 2>&3)

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
        
        choice=$(whiptail --title "Voice generation" --menu "Choose an option:" 15 100 8 --cancel-button "Back" \
            0 "Install WhisperSpeech web UI" \
            1 "Install F5-TTS" \
            2 "Install Matcha-TTS" \
            3 "Install Dia" \
            4 "Install Orpheus-TTS" \
            5 "Install IMS-Toucan" \
            6 "Install Chatterbox" \
            7 "HierSpeech++" \
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
                install_orpheus_tts
                ;;
            "5")
                install_ims_toucan
                ;;
            "6")
                install_chatterbox
                ;;
            "7")
                install_hierspeech
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
        
        choice=$(whiptail --title "3D generation" --menu "Choose an option:" 15 100 2 --cancel-button "Back" \
            0 "Install TripoSG" \
            1 "Install PartCrafter" \
            2>&1 > /dev/tty)

        case "$choice" in
            "0")
                install_triposg
                ;;
            "1")
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
        echo "Tools menu is under construction."

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
        

        if [ $status -ne 0 ]; then
            return 0
        fi
    done
}

backup_and_restore() {
    local success=true
    local error_message=""
    
    # Check if folder exists
    if ! [ -e "$1" ]; then
        echo "Folder or file '$1' does not exist."
        return 1
    fi

    if ! [ -d "$2" ]; then
        # Create backup folder
        if ! mkdir -p "$2"; then
            echo "Failed to create folder '$2'."
            return 1
        fi
    else
        if ! rm -rf "$2"; then
            echo "Failed to remove old folder '$2'."
            return 1
        fi
    fi

    # Copy the contents $1 to $2
    if ! rsync -av --progress --delete "$1/" "$2" 2>/dev/null; then
        echo "Failed to copy contents of '$1' to '$2'."
        return 1
    fi
    
    return 0
}

backup_and_restore_file() {
    # Check if file exists
    if ! [ -e "$1/$3" ]; then
        echo "File '$1/$3' does not exist."
        return 1
    fi

    if ! [ -d "$2" ]; then
        # Create backup folder
        if ! mkdir -p "$2"; then
            echo "Failed to create folder '$2'."
            return 1
        fi
    fi

    # Copy the contents $1 to $2
    if ! cp -f "$1/$3" "$2/$3" 2>/dev/null; then
        echo "Failed to copy contents of '$1/$3' to '$2'."
        return 1
    fi
    
    return 0
}