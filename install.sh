#!/bin/bash

# ROCM-AI-Installer
# Copyright © 2023-2026 Mateusz Dera

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

set -e

# Version
VERSION="17"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.env"

# Default values
DEFAULT_HSA_VERSION=""
DEFAULT_GFX="gfx1100"
DEFAULT_AI_DIR="${HOME}/AI"
DEFAULT_HF_TOKEN=""

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
actcheckbox=black,yellow
'

# Files
source $SCRIPT_DIR/interfaces.sh
source $SCRIPT_DIR/backup.sh

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        HSA_VERSION="${HSA_OVERRIDE_GFX_VERSION:-$DEFAULT_HSA_VERSION}"
        GFX_VERSION="${TARGET_GFX:-$DEFAULT_GFX}"
        GFX_LIST="${TARGET_GFX_ALL:-}"
        AI_DIR="${AI_HOST_DIR:-$DEFAULT_AI_DIR}"
        HF_TOKEN="${HF_TOKEN:-$DEFAULT_HF_TOKEN}"
    else
        HSA_VERSION="$DEFAULT_HSA_VERSION"
        GFX_LIST="$(detect_gpus)"
        GFX_LIST="$(IFS=' '; set -- $GFX_LIST; IFS=';'; echo "$*")"
        GFX_VERSION="${GFX_LIST%%;*}"
        GFX_VERSION="${GFX_VERSION:-$DEFAULT_GFX}"
        AI_DIR="$DEFAULT_AI_DIR"
        HF_TOKEN="$DEFAULT_HF_TOKEN"
        save_config
    fi
}

save_config() {
    local display_var="${DISPLAY:-:0}"
    local wayland_var="${WAYLAND_DISPLAY:-wayland-0}"
    local xdg_var="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

    cat > "$CONFIG_FILE" << EOF

TARGET_GFX=${GFX_VERSION}

TARGET_GFX_ALL="${GFX_LIST:-$GFX_VERSION}"

AI_HOST_DIR="${AI_DIR}"

HF_TOKEN="${HF_TOKEN}"

DISPLAY_VAR=${display_var}
WAYLAND_DISPLAY_VAR=${wayland_var}
XDG_RUNTIME_DIR_VAR=${xdg_var}
EOF

    if [ -n "$HSA_VERSION" ]; then
        cat >> "$CONFIG_FILE" << EOF

HSA_OVERRIDE_GFX_VERSION=${HSA_VERSION}
EOF
    fi

    echo "Configuration saved to: $CONFIG_FILE"
}

check_whiptail() {
    if ! command -v whiptail &> /dev/null; then
        echo "Error: whiptail is not installed. Please install it first:"
        echo "  sudo apt install whiptail"
        exit 1
    fi
}

variable_change_reminder() {
    whiptail --title "Recreate container required" \
        --msgbox "This change is saved to .env but is NOT applied to the existing container.\n\nRun 'Create a container' from the main menu to rebuild it with the new settings." \
        12 70 2>&1 > /dev/tty
}

KNOWN_GFX=(
    "gfx1250|Instinct MI400 series (CDNA5)"
    "gfx1201|Radeon RX 9070 / 9070 XT (RDNA4)"
    "gfx1200|Radeon RX 9060 XT (RDNA4)"
    "gfx1153|Ryzen AI integrated (RDNA3.5)"
    "gfx1152|Krackan Point integrated (RDNA3.5)"
    "gfx1151|Ryzen AI Max 395 Strix Halo (RDNA3.5)"
    "gfx1150|Ryzen AI 300 Strix Point (RDNA3.5)"
    "gfx1103|Ryzen 7040/8040 Phoenix integrated (RDNA3)"
    "gfx1102|Radeon RX 7600 / 7700S (RDNA3)"
    "gfx1101|Radeon RX 7700 XT / 7800 XT (RDNA3)"
    "gfx1100|Radeon RX 7900 XTX / XT / GRE, W7900 (RDNA3)"
    "gfx1036|Raphael / Granite Ridge integrated (RDNA2)"
    "gfx1035|Rembrandt integrated (RDNA2)"
    "gfx1034|Radeon RX 6500 XT (RDNA2)"
    "gfx1032|Radeon RX 6600 / 6650 (RDNA2)"
    "gfx1031|Radeon RX 6700 XT (RDNA2)"
    "gfx1030|Radeon RX 6800 / 6900 XT, W6800 (RDNA2)"
    "gfx1012|Radeon RX 5500 XT (RDNA)"
    "gfx1011|Radeon Pro V520 (RDNA)"
    "gfx1010|Radeon RX 5700 XT (RDNA)"
    "gfx950|Instinct MI350 series (CDNA4)"
    "gfx942|Instinct MI300 series (CDNA3)"
    "gfx90a|Instinct MI200 series (CDNA2)"
    "gfx908|Instinct MI100 (CDNA)"
)

detect_gpu_archs() {
    detect_gpus | awk '!seen[$0]++' | tr '\n' ' '
}

configure_gfx() {
    local quiet="${1:-}"
    local detected preselect entries=() tag desc state extra selected primary chosen
    local -a picked

    detected="$(detect_gpus)"

    if [ -n "$GFX_LIST" ]; then
        preselect=" ${GFX_LIST//;/ } "
    elif [ -n "$detected" ]; then
        preselect=" $detected "
    else
        preselect=" $GFX_VERSION "
    fi

    for entry in "${KNOWN_GFX[@]}"; do
        tag="${entry%%|*}"; desc="${entry#*|}"
        [[ " $detected " == *" $tag "* ]] && desc="$desc [detected]"
        state=OFF
        [[ "$preselect" == *" $tag "* ]] && state=ON
        entries+=("$tag" "$desc" "$state")
    done

    for tag in $detected; do
        [[ " ${KNOWN_GFX[*]} " == *"$tag|"* ]] && continue
        entries+=("$tag" "unknown to this list [detected]" "ON")
    done

    extra="No AMD GPU detected - select manually."
    [ -n "$detected" ] && extra="Detected: ${detected% }"

    selected=$(whiptail --title "Target GFX Architectures" --separate-output \
        --checklist "Select every GPU architecture to build and install packages for.\nSpace toggles, Enter confirms.\n\n${extra}" \
        24 78 12 "${entries[@]}" 2>&1 > /dev/tty)

    [ $? -ne 0 ] && return 0

    mapfile -t picked <<< "$selected"
    [ ${#picked[@]} -eq 1 ] && [ -z "${picked[0]}" ] && picked=()
    if [ ${#picked[@]} -eq 0 ]; then
        whiptail --title "Nothing selected" \
            --msgbox "At least one architecture is required. Previous setting kept: ${GFX_VERSION}" \
            8 70 2>&1 > /dev/tty
        return 0
    fi

    GFX_LIST="$(IFS=';'; echo "${picked[*]}")"

    GFX_VERSION="${picked[0]}"
    save_config

    [ -n "$quiet" ] && return 0

    whiptail --title "Success" \
        --msgbox "Architectures: ${GFX_LIST//;/ }\n\nPackages are installed for all of them.\nEach application asks which card to use when it is installed." \
        11 70 2>&1 > /dev/tty
    variable_change_reminder
}

configure_path() {
    local new_path
    new_path=$(whiptail --title "AI Workspace Directory" \
        --inputbox "Enter the host directory to mount as container workspace:\n\nThis directory will be created if it doesn't exist.\n\nCurrent value: ${AI_DIR}" \
        14 70 "$AI_DIR" 2>&1 > /dev/tty)

    if [ $? -eq 0 ] && [ -n "$new_path" ]; then
        new_path="${new_path/#\~/$HOME}"
        AI_DIR="$new_path"

        if [ ! -d "$AI_DIR" ]; then
            if whiptail --title "Create Directory" --yesno "Directory '$AI_DIR' does not exist.\n\nDo you want to create it?" 10 60 2>&1 > /dev/tty; then
                if ! mkdir -p "$AI_DIR"; then
                    whiptail --title "Error" --msgbox "Failed to create directory: ${AI_DIR}\n\nPlease check permissions." 10 60 2>&1 > /dev/tty
                    return 1
                fi

                chmod 775 "$AI_DIR" 2>/dev/null || true

                save_config
                whiptail --title "Success" --msgbox "Directory created: ${AI_DIR}\nPermissions: 775\n\nNote: Ownership will be managed by Podman when container starts." 12 70 2>&1 > /dev/tty
                variable_change_reminder
            else
                return 0
            fi
        else
            chmod 775 "$AI_DIR" 2>/dev/null || true

            save_config
            whiptail --title "Success" --msgbox "Path set to: ${AI_DIR}\n\nNote: Ownership will be managed by Podman when container starts." 10 70 2>&1 > /dev/tty
            variable_change_reminder
        fi
    fi
}

configure_hf_token() {
    local new_token
    new_token=$(whiptail --title "HuggingFace Token (optional)" \
        --inputbox "Enter your HuggingFace access token (optional).\n\nRequired only for models that need access approval.\nLeave empty to skip.\n\nCurrent value: ${HF_TOKEN:-(not set)}" \
        14 70 "$HF_TOKEN" 2>&1 > /dev/tty)

    if [ $? -eq 0 ]; then
        HF_TOKEN="$new_token"
        save_config
        if [ -n "$HF_TOKEN" ]; then
            whiptail --title "Success" --msgbox "HuggingFace token saved." 8 50 2>&1 > /dev/tty
        else
            whiptail --title "Success" --msgbox "HuggingFace token cleared." 8 50 2>&1 > /dev/tty
        fi
        variable_change_reminder
    fi
}

create_container() {
    if ! command -v podman-compose &> /dev/null; then
        whiptail --title "Error" --msgbox "podman-compose is not installed!\n\nPlease install Podman first from the Basic Install menu." 10 60 2>&1 > /dev/tty
        return
    fi

    configure_gfx quiet

    if whiptail --title "Create Container" --yesno "This will:\n1. Stop and remove existing container\n2. Build new container (podman-compose build)\n3. Start container (podman-compose up -d)\n\nArchitectures: ${GFX_LIST//;/ }\n\nContinue?" 16 60 2>&1 > /dev/tty; then
        if [ -n "$AI_DIR" ]; then
            if [ ! -d "$AI_DIR" ]; then
                echo "Creating directory $AI_DIR..."
                if ! mkdir -p "$AI_DIR"; then
                    whiptail --title "Error" --msgbox "Failed to create directory: ${AI_DIR}\n\nCannot proceed with container creation." 10 60 2>&1 > /dev/tty
                    return 1
                fi
            fi

            echo "Setting permissions on $AI_DIR..."
            if ! chmod -R 775 "$AI_DIR" 2>/dev/null; then
                echo "Warning: Could not set permissions on $AI_DIR, but continuing..."
            fi

            echo "Directory $AI_DIR ready for container mount"
        fi

        save_config

        if command -v xhost &> /dev/null; then
            xhost +local: 2>/dev/null || true
        fi

        echo "Stopping and removing existing container..."
        podman-compose down
        podman rm -f rocm 2>/dev/null || true

        if [ -n "$HSA_VERSION" ]; then
            export HSA_OVERRIDE_GFX_VERSION="$HSA_VERSION"
        else
            unset HSA_OVERRIDE_GFX_VERSION
        fi

        echo "Building container..."
        podman-compose build

        echo "Starting container..."
        podman-compose up -d

        whiptail --title "Success" --msgbox "Container created and started successfully!\n\nTo enter the container, run:\npodman exec -it rocm /bin/bash" 12 60 2>&1 > /dev/tty
    fi
}

# trellis.cpp
trellis_cpp() {
    second=true
    while $second; do

        choice=$(whiptail --title "trellis.cpp" --cancel-button "Back" --menu "Choose an option:" 15 100 2 \
            1 "ROCm" \
            2 "Vulkan" \
            2>&1 > /dev/tty)
        status=$?

        if [ $status -ne 0 ]; then
            return 0
        fi

        case "$choice" in
            "1")
                install_trellis_cpp
                ;;
            "2")
                install_trellis_cpp_vulkan
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

# llama.cpp TurboQuant
llama_cpp() {
    second=true
    while $second; do

        choice=$(whiptail --title "llama.cpp TurboQuant" --cancel-button "Back" --menu "Choose an option:" 15 100 2 \
            1 "ROCm" \
            2 "Vulkan" \
            2>&1 > /dev/tty)
        status=$?

        if [ $status -ne 0 ]; then
            return 0
        fi

        case "$choice" in
            "1")
                llama_cpp_menu "llama.cpp TurboQuant (ROCm)" "llama.cpp-turboquant" install_llama_cpp_turboquant
                ;;
            "2")
                llama_cpp_menu "llama.cpp TurboQuant (Vulkan)" "llama.cpp-turboquant-vulkan" install_llama_cpp_turboquant_vulkan
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

llama_cpp_menu() {
    local title="$1"
    local folder="$2"
    local install_fn="$3"

    second=true
    while $second; do

        choice=$(whiptail --title "$title" --cancel-button "Back" --menu "Choose an option:" 15 100 4 \
            1 "Backup" \
            2 "Install" \
            3 "Restore" \
            4 "Delete a backup" \
            2>&1 > /dev/tty)
        status=$?

        if [ $status -ne 0 ]; then
            return 0
        fi

        case "$choice" in
            "1")
                llama_cpp_backup "$folder"
                ;;
            "2")
                "$install_fn"
                ;;
            "3")
                llama_cpp_restore "$folder"
                ;;
            "4")
                snapshot_delete "$folder"
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

llama_cpp_backup() {
    CHOICES=$(whiptail --separate-output --cancel-button "Back" --checklist "Backup:" 12 60 3 \
        1 "Backup models" ON \
        2 "Backup drafts" ON \
        3 "Backup models.ini" ON 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$CHOICES" ]; then
        return 0
    fi

    perform_llamacpp_backup "$1" "$CHOICES"
    read -p "Press Enter to continue..."
}

llama_cpp_restore() {
    basic_container || return 0
    snapshot_select "$1" || return 0

    local entries
    snapshot_entries entries \
        1 "Restore models"      "user-models" \
        2 "Restore drafts"      "drafts" \
        3 "Restore models.ini"  "models.ini"

    if [ ${#entries[@]} -eq 0 ]; then
        whiptail --title "Restore" --msgbox "Backup ${SNAPSHOT_NAME} holds nothing that can be restored." 10 60
        return 0
    fi

    CHOICES=$(whiptail --separate-output --cancel-button "Back" \
        --checklist "Restore from ${SNAPSHOT_NAME}:" 12 60 3 "${entries[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$CHOICES" ]; then
        return 0
    fi

    perform_llamacpp_restore "$1" "$CHOICES"
    read -p "Press Enter to continue..."
}

# SillyTavern
sillytavern() {
    second=true
    while $second; do
        
        choice=$(whiptail --title "SillyTavern" --cancel-button "Back" --menu "Choose an option:" 15 100 4 \
            1 "Backup" \
            2 "Install" \
            3 "Restore" \
            4 "Delete a backup" \
            2>&1 > /dev/tty)
        status=$?
        

        if [ $status -ne 0 ]; then
            return 0
        fi
        
        case "$choice" in
            "1")
                sillytavern_backup
                ;;
            "2")
                install_sillytavern
                ;;
            "3")
                sillytavern_restore
                ;;
            "4")
                snapshot_delete "SillyTavern"
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
    CHOICES=$(whiptail --separate-output --cancel-button "Back" --checklist "Backup:" 21 50 14 \
        1 "Backup config.yaml" ON \
        2 "Backup settings.json" ON \
        3 "Backup characters" ON \
        4 "Backup groups" ON \
        5 "Backup worlds" ON \
        6 "Backup chats" ON \
        7 "Backup group chats" ON \
        8 "Backup user avatars images" ON \
        9 "Backup backgrounds images" ON \
        10 "Backup themes" ON \
        11 "Backup presets" ON \
        12 "Backup context" ON \
        13 "Backup instruct" ON \
        14 "Backup sysprompt" ON 3>&1 1>&2 2>&3)

    status=$?
    
    if [ $status -ne 0 ]; then
        return 0
    fi

    perform_sillytavern_backup "$CHOICES"
}

sillytavern_restore() {
    basic_container || return 0
    snapshot_select "SillyTavern" || return 0

    local D="data/default-user"
    local entries
    snapshot_entries entries \
        1  "Restore config.yaml"          "config.yaml" \
        2  "Restore settings.json"        "$D/settings.json" \
        3  "Restore characters"           "$D/characters" \
        4  "Restore groups"               "$D/groups" \
        5  "Restore worlds"               "$D/worlds" \
        6  "Restore chats"                "$D/chats" \
        7  "Restore group chats"          "$D/group chats" \
        8  "Restore user avatars images"  "$D/User Avatars" \
        9  "Restore backgrounds images"   "$D/backgrounds" \
        10 "Restore themes"               "$D/themes" \
        11 "Restore presets"              "$D/TextGen Settings" \
        12 "Restore context"              "$D/context" \
        13 "Restore instruct"             "$D/instruct" \
        14 "Restore sysprompt"            "$D/sysprompt"

    if [ ${#entries[@]} -eq 0 ]; then
        whiptail --title "Restore" --msgbox "Backup ${SNAPSHOT_NAME} holds nothing that can be restored." 10 60
        return 0
    fi

    CHOICES=$(whiptail --separate-output --cancel-button "Back" \
        --checklist "Restore from ${SNAPSHOT_NAME}:" 21 50 14 "${entries[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$CHOICES" ]; then
        return 0
    fi

    perform_sillytavern_restore "$CHOICES"
}

# Text generation
text_generation() {
    second=true
    while $second; do
        
        choice=$(whiptail --title "Text generation" --cancel-button "Back" --menu "Choose an option:" 16 100 4 \
            1 "llama.cpp TurboQuant" \
            2 "SillyTavern" \
            3 "Install vLLM Gemma 4 (31B w4a16, compressed KV)" \
            4 "Install KoboldCPP" \
            2>&1 > /dev/tty)
        status=$?

        if [ $status -ne 0 ]; then
            return 0
        fi

        case "$choice" in
            "1")
                llama_cpp
                ;;
            "2")
                sillytavern
                ;;
            "3")
                install_vllm_gemma4
                ;;
            "4")
                install_koboldcpp
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

image_generation() {
    second=true
    while $second; do
        
        choice=$(whiptail --title "Image generation" --cancel-button "Back" --menu "Choose an option:" 15 100 2 \
            1 "ComfyUI" \
            2 "Install Krea 2 Turbo + Edit" \
            2>&1 > /dev/tty)
        status=$?

        if [ $status -ne 0 ]; then
            return 0
        fi

        case "$choice" in
            "1")
                comfyui_addons
                ;;
            "2")
                install_krea2
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
    CHOICES=$(whiptail --separate-output --cancel-button "Back" --checklist "Addons:" 15 50 4 \
        1 "Z-Image-Turbo" ON \
        2 "Z-Anime" ON \
        3 "Wan2.2-TI2V-5B" ON 3>&1 1>&2 2>&3)

    status=$?

    if [ $status -ne 0 ]; then
        return 0
    fi

    install_comfyui $CHOICES
}

music_generation() {
    second=true
    while $second; do

        choice=$(whiptail --title "Music generation" --cancel-button "Back" --menu "Choose an option:" 15 100 1 \
            1 "Install ACE-Step-1.5" \
            2>&1 > /dev/tty)
        status=$?

        if [ $status -ne 0 ]; then
            return 0
        fi

        case "$choice" in
            "1")
                install_ace_step_1_5
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

voice_generation() {
    second=true
    while $second; do

        choice=$(whiptail --title "Voice" --cancel-button "Back" --menu "Choose an option:" 15 100 3 \
            1 "Install Soprano" \
            2 "Install OmniVoice" \
            3 "Install Parakeet" \
            2>&1 > /dev/tty)
        status=$?

        if [ $status -ne 0 ]; then
            return 0
        fi

        case "$choice" in
            "1")
                install_soprano
                ;;
            "2")
                install_omnivoice
                ;;
            "3")
                install_parakeet
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

show_menu() {
    choice=$(whiptail --title "ROCm-AI-Installer $VERSION" --menu "Choose an option:" 20 100 7 \
    1 "Variables" \
    2 "Create a container" \
    3 "Text generation" \
    4 "Image & video generation" \
    5 "Music generation" \
    6 "Voice" \
    7 "3D generation" \
    --cancel-button "Exit" \
    2>&1 > /dev/tty)

    case $choice in
        1)
            variables
            ;;
        2)
            create_container
            ;;
        3)
            text_generation
            ;;
        4)
            image_generation
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
        *)
            exit 0
            ;;
    esac
}

# 3D generation

d3_generation() {
    second=true
    while $second; do

        choice=$(whiptail --title "3D generation" --cancel-button "Back" --menu "Choose an option:" 17 100 5 \
            1 "Install PartCrafter" \
            2 "Install trellis.cpp" \
            3 "Install ARDY" \
            4 "Install TripoSplat" \
            5 "Install AutoRemesher (retopology helper, non-AI)" \
            2>&1 > /dev/tty)

        case "$choice" in
            "1")
                install_partcrafter
                ;;
            "2")
                trellis_cpp
                ;;
            "3")
                install_ardy
                ;;
            "4")
                install_triposplat
                ;;
            "5")
                install_autoremesher
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

# Variables
variables() {
    second=true
    while $second; do

        choice=$(whiptail --title "Variables" --cancel-button "Back" --menu "Choose an option:" 14 100 3 \
            "1" "GFX" \
            "2" "PATH" \
            "3" "HuggingFace Token (optional)" \
            2>&1 > /dev/tty)
        status=$?

        if [ $status -ne 0 ]; then
            return 0
        fi

        case "$choice" in
            "1")
                configure_gfx
                ;;
            "2")
                configure_path
                ;;
            "3")
                configure_hf_token
                ;;
            *)
                echo "Invalid selection."
                second=false
                ;;
        esac
    done
}

check_whiptail
load_config

while show_menu; do
    :
done