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

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/interfaces.sh"

# Check if rocm container is running and start it if needed
basic_container

# Global variables for tracking backup results
declare -a successful_backups=()
declare -a failed_backups=()

# Function to log messages with timestamp
log_message() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >&2
}

# Function to backup a directory with improved error handling
backup_directory() {
    local source_path="$1"
    local dest_path="$2"
    local item_name="$3"

    # Validate inputs
    if [[ -z "$source_path" || -z "$dest_path" || -z "$item_name" ]]; then
        log_message "ERROR" "backup_directory: Missing required parameters"
        return 1
    fi

    # Check if source exists
    if ! podman exec -t rocm bash -c "[ -e '$source_path' ]" 2>/dev/null; then
        log_message "WARNING" "Source path does not exist: $source_path"
        failed_backups+=("$item_name (source not found)")
        return 1
    fi

    # Create parent directory for destination
    local dest_parent
    dest_parent="$(dirname "$dest_path")"
    if ! podman exec -t rocm bash -c "mkdir -p '$dest_parent'" 2>/dev/null; then
        log_message "ERROR" "Failed to create parent directory: $dest_parent"
        failed_backups+=("$item_name (parent dir creation failed)")
        return 1
    fi

    # Remove existing destination if it exists
    if podman exec -t rocm bash -c "[ -e '$dest_path' ]" 2>/dev/null; then
        if ! podman exec -t rocm bash -c "rm -rf '$dest_path'" 2>/dev/null; then
            log_message "ERROR" "Failed to remove existing destination: $dest_path"
            failed_backups+=("$item_name (cleanup failed)")
            return 1
        fi
    fi

    # Perform the backup using cp with verbose output
    log_message "INFO" "Backing up: $source_path -> $dest_path"

    if podman exec -t rocm bash -c "[ -d '$source_path' ]" 2>/dev/null; then
        # Directory backup
        if podman exec -t rocm bash -c "cp -r '$source_path' '$dest_path'" 2>/dev/null; then
            log_message "SUCCESS" "Successfully backed up directory: $item_name"
            successful_backups+=("$item_name")
            return 0
        else
            log_message "ERROR" "Failed to backup directory: $source_path"
            failed_backups+=("$item_name (copy failed)")
            return 1
        fi
    else
        # File backup
        if podman exec -t rocm bash -c "cp '$source_path' '$dest_path'" 2>/dev/null; then
            log_message "SUCCESS" "Successfully backed up file: $item_name"
            successful_backups+=("$item_name")
            return 0
        else
            log_message "ERROR" "Failed to backup file: $source_path"
            failed_backups+=("$item_name (copy failed)")
            return 1
        fi
    fi
}

# Function to backup a single file
backup_file() {
    local source_dir="$1"
    local dest_dir="$2"
    local filename="$3"
    local item_name="$4"

    # Validate inputs
    if [[ -z "$source_dir" || -z "$dest_dir" || -z "$filename" || -z "$item_name" ]]; then
        log_message "ERROR" "backup_file: Missing required parameters"
        return 1
    fi

    local source_path="$source_dir/$filename"
    local dest_path="$dest_dir/$filename"

    # Check if source file exists
    if ! podman exec -t rocm bash -c "[ -f '$source_path' ]" 2>/dev/null; then
        log_message "WARNING" "Source file does not exist: $source_path"
        failed_backups+=("$item_name (file not found)")
        return 1
    fi

    # Create destination directory
    if ! podman exec -t rocm bash -c "mkdir -p '$dest_dir'" 2>/dev/null; then
        log_message "ERROR" "Failed to create destination directory: $dest_dir"
        failed_backups+=("$item_name (dest dir creation failed)")
        return 1
    fi

    # Backup the file
    log_message "INFO" "Backing up file: $source_path -> $dest_path"

    if podman exec -t rocm bash -c "cp '$source_path' '$dest_path'" 2>/dev/null; then
        log_message "SUCCESS" "Successfully backed up file: $item_name"
        successful_backups+=("$item_name")
        return 0
    else
        log_message "ERROR" "Failed to backup file: $source_path"
        failed_backups+=("$item_name (copy failed)")
        return 1
    fi
}

# Function to restore a directory
restore_directory() {
    local source_path="$1"
    local dest_path="$2"
    local item_name="$3"

    # Validate inputs
    if [[ -z "$source_path" || -z "$dest_path" || -z "$item_name" ]]; then
        log_message "ERROR" "restore_directory: Missing required parameters"
        return 1
    fi

    # Check if backup source exists
    if ! podman exec -t rocm bash -c "[ -e '$source_path' ]" 2>/dev/null; then
        log_message "WARNING" "Backup source does not exist: $source_path"
        failed_backups+=("$item_name (backup not found)")
        return 1
    fi

    # Create parent directory for destination
    local dest_parent
    dest_parent="$(dirname "$dest_path")"
    if ! podman exec -t rocm bash -c "mkdir -p '$dest_parent'" 2>/dev/null; then
        log_message "ERROR" "Failed to create parent directory: $dest_parent"
        failed_backups+=("$item_name (parent dir creation failed)")
        return 1
    fi

    # Remove existing destination if it exists
    if podman exec -t rocm bash -c "[ -e '$dest_path' ]" 2>/dev/null; then
        if ! podman exec -t rocm bash -c "rm -rf '$dest_path'" 2>/dev/null; then
            log_message "ERROR" "Failed to remove existing destination: $dest_path"
            failed_backups+=("$item_name (cleanup failed)")
            return 1
        fi
    fi

    # Perform the restore
    log_message "INFO" "Restoring: $source_path -> $dest_path"

    if podman exec -t rocm bash -c "[ -d '$source_path' ]" 2>/dev/null; then
        # Directory restore
        if podman exec -t rocm bash -c "cp -r '$source_path' '$dest_path'" 2>/dev/null; then
            log_message "SUCCESS" "Successfully restored directory: $item_name"
            successful_backups+=("$item_name")
            return 0
        else
            log_message "ERROR" "Failed to restore directory: $source_path"
            failed_backups+=("$item_name (copy failed)")
            return 1
        fi
    else
        # File restore
        if podman exec -t rocm bash -c "cp '$source_path' '$dest_path'" 2>/dev/null; then
            log_message "SUCCESS" "Successfully restored file: $item_name"
            successful_backups+=("$item_name")
            return 0
        else
            log_message "ERROR" "Failed to restore file: $source_path"
            failed_backups+=("$item_name (copy failed)")
            return 1
        fi
    fi
}

# Function to restore a single file
restore_file() {
    local source_dir="$1"
    local dest_dir="$2"
    local filename="$3"
    local item_name="$4"

    # Validate inputs
    if [[ -z "$source_dir" || -z "$dest_dir" || -z "$filename" || -z "$item_name" ]]; then
        log_message "ERROR" "restore_file: Missing required parameters"
        return 1
    fi

    local source_path="$source_dir/$filename"
    local dest_path="$dest_dir/$filename"

    # Check if backup file exists
    if ! podman exec -t rocm bash -c "[ -f '$source_path' ]" 2>/dev/null; then
        log_message "WARNING" "Backup file does not exist: $source_path"
        failed_backups+=("$item_name (backup not found)")
        return 1
    fi

    # Create destination directory
    if ! podman exec -t rocm bash -c "mkdir -p '$dest_dir'" 2>/dev/null; then
        log_message "ERROR" "Failed to create destination directory: $dest_dir"
        failed_backups+=("$item_name (dest dir creation failed)")
        return 1
    fi

    # Restore the file
    log_message "INFO" "Restoring file: $source_path -> $dest_path"

    if podman exec -t rocm bash -c "cp '$source_path' '$dest_path'" 2>/dev/null; then
        log_message "SUCCESS" "Successfully restored file: $item_name"
        successful_backups+=("$item_name")
        return 0
    else
        log_message "ERROR" "Failed to restore file: $source_path"
        failed_backups+=("$item_name (copy failed)")
        return 1
    fi
}

# Function to reset backup tracking arrays
reset_backup_tracking() {
    successful_backups=()
    failed_backups=()
}

# Function to generate summary message for whiptail
generate_backup_summary() {
    local operation="$1"  # "Backup" or "Restore"
    local summary_msg=""
    
    # Create failure message
    if [[ ${#failed_backups[@]} -gt 0 ]]; then
        summary_msg="Failed to ${operation,,}:\n"
        for item in "${failed_backups[@]}"; do
            summary_msg+="• $item\n"
        done
        summary_msg+="\n"
    fi
    
    # Create success message
    if [[ ${#successful_backups[@]} -gt 0 ]]; then
        summary_msg+="Successfully ${operation,,}d:\n"
        for item in "${successful_backups[@]}"; do
            summary_msg+="• $item\n"
        done
    fi
    
    # Set title based on results
    local summary_title="$operation Summary"
    if [[ ${#failed_backups[@]} -eq 0 && ${#successful_backups[@]} -gt 0 ]]; then
        summary_title="$operation Summary - All Successful"
    elif [[ ${#successful_backups[@]} -eq 0 ]]; then
        summary_title="$operation Summary - All Failed"
    fi
    
    # Display the summary
    if [[ -n "$summary_msg" ]]; then
        whiptail --title "$summary_title" --msgbox "$summary_msg" 22 70
    else
        whiptail --title "$operation Summary" --msgbox "No items were selected for $operation." 10 50
    fi
}

# SillyTavern backup function
perform_sillytavern_backup() {
    local choices="$1"
    
    # Reset tracking arrays
    reset_backup_tracking
    
    log_message "INFO" "Starting SillyTavern backup operation"
    
    for choice in $choices; do
        case $choice in
            '"1"')
                backup_file "/AI/SillyTavern" "/AI/Backups/SillyTavern" "config.yaml" "config.yaml"
                ;;
            '"2"')
                backup_file "/AI/SillyTavern/data/default-user" "/AI/Backups/SillyTavern/data/default-user" "settings.json" "settings.json"
                ;;
            '"3"')
                backup_directory "/AI/SillyTavern/data/default-user/characters" "/AI/Backups/SillyTavern/data/default-user/characters" "characters folder"
                ;;
            '"4"')
                backup_directory "/AI/SillyTavern/data/default-user/groups" "/AI/Backups/SillyTavern/data/default-user/groups" "groups folder"
                ;;
            '"5"')
                backup_directory "/AI/SillyTavern/data/default-user/worlds" "/AI/Backups/SillyTavern/data/default-user/worlds" "worlds folder"
                ;;
            '"6"')
                backup_directory "/AI/SillyTavern/data/default-user/chats" "/AI/Backups/SillyTavern/data/default-user/chats" "chats folder"
                ;;
            '"7"')
                backup_directory "/AI/SillyTavern/data/default-user/group chats" "/AI/Backups/SillyTavern/data/default-user/group chats" "group chats folder"
                ;;
            '"8"')
                backup_directory "/AI/SillyTavern/data/default-user/User Avatars" "/AI/Backups/SillyTavern/data/default-user/User Avatars" "User Avatars folder"
                ;;
            '"9"')
                backup_directory "/AI/SillyTavern/data/default-user/backgrounds" "/AI/Backups/SillyTavern/data/default-user/backgrounds" "backgrounds folder"
                ;;
            '"10"')
                backup_directory "/AI/SillyTavern/data/default-user/themes" "/AI/Backups/SillyTavern/data/default-user/themes" "themes folder"
                ;;
            '"11"')
                backup_directory "/AI/SillyTavern/data/default-user/TextGen Settings" "/AI/Backups/SillyTavern/data/default-user/TextGen Settings" "TextGen Settings folder"
                ;;
            '"12"')
                backup_directory "/AI/SillyTavern/data/default-user/context" "/AI/Backups/SillyTavern/data/default-user/context" "context folder"
                ;;
            '"13"')
                backup_directory "/AI/SillyTavern/data/default-user/instruct" "/AI/Backups/SillyTavern/data/default-user/instruct" "instruct folder"
                ;;
            '"14"')
                backup_directory "/AI/SillyTavern/data/default-user/sysprompt" "/AI/Backups/SillyTavern/data/default-user/sysprompt" "sysprompt folder"
                ;;
        esac
    done
    
    log_message "INFO" "SillyTavern backup operation completed"
    generate_backup_summary "Backup"
}

# SillyTavern restore function
perform_sillytavern_restore() {
    local choices="$1"
    
    # Reset tracking arrays
    reset_backup_tracking
    
    log_message "INFO" "Starting SillyTavern restore operation"
    
    for choice in $choices; do
        case $choice in
            '"1"')
                restore_file "/AI/Backups/SillyTavern" "/AI/SillyTavern" "config.yaml" "config.yaml"
                ;;
            '"2"')
                restore_file "/AI/Backups/SillyTavern/data/default-user" "/AI/SillyTavern/data/default-user" "settings.json" "settings.json"
                ;;
            '"3"')
                restore_directory "/AI/Backups/SillyTavern/data/default-user/characters" "/AI/SillyTavern/data/default-user/characters" "characters folder"
                ;;
            '"4"')
                restore_directory "/AI/Backups/SillyTavern/data/default-user/groups" "/AI/SillyTavern/data/default-user/groups" "groups folder"
                ;;
            '"5"')
                restore_directory "/AI/Backups/SillyTavern/data/default-user/worlds" "/AI/SillyTavern/data/default-user/worlds" "worlds folder"
                ;;
            '"6"')
                restore_directory "/AI/Backups/SillyTavern/data/default-user/chats" "/AI/SillyTavern/data/default-user/chats" "chats folder"
                ;;
            '"7"')
                restore_directory "/AI/Backups/SillyTavern/data/default-user/group chats" "/AI/SillyTavern/data/default-user/group chats" "group chats folder"
                ;;
            '"8"')
                restore_directory "/AI/Backups/SillyTavern/data/default-user/User Avatars" "/AI/SillyTavern/data/default-user/User Avatars" "User Avatars folder"
                ;;
            '"9"')
                restore_directory "/AI/Backups/SillyTavern/data/default-user/backgrounds" "/AI/SillyTavern/data/default-user/backgrounds" "backgrounds folder"
                ;;
            '"10"')
                restore_directory "/AI/Backups/SillyTavern/data/default-user/themes" "/AI/SillyTavern/data/default-user/themes" "themes folder"
                ;;
            '"11"')
                restore_directory "/AI/Backups/SillyTavern/data/default-user/TextGen Settings" "/AI/SillyTavern/data/default-user/TextGen Settings" "TextGen Settings folder"
                ;;
            '"12"')
                restore_directory "/AI/Backups/SillyTavern/data/default-user/context" "/AI/SillyTavern/data/default-user/context" "context folder"
                ;;
            '"13"')
                restore_directory "/AI/Backups/SillyTavern/data/default-user/instruct" "/AI/SillyTavern/data/default-user/instruct" "instruct folder"
                ;;
            '"14"')
                restore_directory "/AI/Backups/SillyTavern/data/default-user/sysprompt" "/AI/SillyTavern/data/default-user/sysprompt" "sysprompt folder"
                ;;
        esac
    done
    
    log_message "INFO" "SillyTavern restore operation completed"
    generate_backup_summary "Restore"
}

# Text Generation Web UI backup function
perform_textgen_backup() {
    local choices="$1"
    
    # Reset tracking arrays
    reset_backup_tracking
    
    log_message "INFO" "Starting Text Generation Web UI backup operation"
    
    for choice in $choices; do
        case $choice in
            '"1"')
                backup_directory "/AI/text-generation-webui/user_data/models" "/AI/Backups/text-generation-webui/user_data/models" "models folder"
                ;;
            '"2"')
                backup_directory "/AI/text-generation-webui/user_data/characters" "/AI/Backups/text-generation-webui/user_data/characters" "characters folder"
                ;;
            '"3"')
                backup_directory "/AI/text-generation-webui/user_data/presets" "/AI/Backups/text-generation-webui/user_data/presets" "presets folder"
                ;;
            '"4"')
                backup_directory "/AI/text-generation-webui/user_data/instruction-templates" "/AI/Backups/text-generation-webui/user_data/instruction-templates" "instruction-templates folder"
                ;;
        esac
    done
    
    log_message "INFO" "Text Generation Web UI backup operation completed"
    generate_backup_summary "Backup"
}

# Text Generation Web UI restore function
perform_textgen_restore() {
    local choices="$1"
    
    # Reset tracking arrays
    reset_backup_tracking
    
    log_message "INFO" "Starting Text Generation Web UI restore operation"
    
    for choice in $choices; do
        case $choice in
            '"1"')
                restore_directory "/AI/Backups/text-generation-webui/user_data/models" "/AI/text-generation-webui/user_data/models" "models folder"
                ;;
            '"2"')
                restore_directory "/AI/Backups/text-generation-webui/user_data/characters" "/AI/text-generation-webui/user_data/characters" "characters folder"
                ;;
            '"3"')
                restore_directory "/AI/Backups/text-generation-webui/user_data/presets" "/AI/text-generation-webui/user_data/presets" "presets folder"
                ;;
            '"4"')
                restore_directory "/AI/Backups/text-generation-webui/user_data/instruction-templates" "/AI/text-generation-webui/user_data/instruction-templates" "instruction-templates folder"
                ;;
        esac
    done
    
    log_message "INFO" "Text Generation Web UI restore operation completed"
    generate_backup_summary "Restore"
}