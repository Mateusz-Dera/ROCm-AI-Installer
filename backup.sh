#!/bin/bash

# ROCM-AI-Installer Backup System
# Copyright © 2023-2025 Mateusz Dera

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# Improved backup and restore system with better error handling and logging

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
    if [[ ! -e "$source_path" ]]; then
        log_message "WARNING" "Source path does not exist: $source_path"
        failed_backups+=("$item_name (source not found)")
        return 1
    fi
    
    # Create parent directory for destination
    local dest_parent
    dest_parent="$(dirname "$dest_path")"
    if ! mkdir -p "$dest_parent"; then
        log_message "ERROR" "Failed to create parent directory: $dest_parent"
        failed_backups+=("$item_name (parent dir creation failed)")
        return 1
    fi
    
    # Remove existing destination if it exists
    if [[ -e "$dest_path" ]]; then
        if ! rm -rf "$dest_path"; then
            log_message "ERROR" "Failed to remove existing destination: $dest_path"
            failed_backups+=("$item_name (cleanup failed)")
            return 1
        fi
    fi
    
    # Perform the backup using cp with verbose output
    log_message "INFO" "Backing up: $source_path -> $dest_path"
    
    if [[ -d "$source_path" ]]; then
        # Directory backup
        if cp -r "$source_path" "$dest_path" 2>/dev/null; then
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
        if cp "$source_path" "$dest_path" 2>/dev/null; then
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
    if [[ ! -f "$source_path" ]]; then
        log_message "WARNING" "Source file does not exist: $source_path"
        failed_backups+=("$item_name (file not found)")
        return 1
    fi
    
    # Create destination directory
    if ! mkdir -p "$dest_dir"; then
        log_message "ERROR" "Failed to create destination directory: $dest_dir"
        failed_backups+=("$item_name (dest dir creation failed)")
        return 1
    fi
    
    # Backup the file
    log_message "INFO" "Backing up file: $source_path -> $dest_path"
    
    if cp "$source_path" "$dest_path" 2>/dev/null; then
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
    if [[ ! -e "$source_path" ]]; then
        log_message "WARNING" "Backup source does not exist: $source_path"
        failed_backups+=("$item_name (backup not found)")
        return 1
    fi
    
    # Create parent directory for destination
    local dest_parent
    dest_parent="$(dirname "$dest_path")"
    if ! mkdir -p "$dest_parent"; then
        log_message "ERROR" "Failed to create parent directory: $dest_parent"
        failed_backups+=("$item_name (parent dir creation failed)")
        return 1
    fi
    
    # Remove existing destination if it exists
    if [[ -e "$dest_path" ]]; then
        if ! rm -rf "$dest_path"; then
            log_message "ERROR" "Failed to remove existing destination: $dest_path"
            failed_backups+=("$item_name (cleanup failed)")
            return 1
        fi
    fi
    
    # Perform the restore
    log_message "INFO" "Restoring: $source_path -> $dest_path"
    
    if [[ -d "$source_path" ]]; then
        # Directory restore
        if cp -r "$source_path" "$dest_path" 2>/dev/null; then
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
        if cp "$source_path" "$dest_path" 2>/dev/null; then
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
    if [[ ! -f "$source_path" ]]; then
        log_message "WARNING" "Backup file does not exist: $source_path"
        failed_backups+=("$item_name (backup not found)")
        return 1
    fi
    
    # Create destination directory
    if ! mkdir -p "$dest_dir"; then
        log_message "ERROR" "Failed to create destination directory: $dest_dir"
        failed_backups+=("$item_name (dest dir creation failed)")
        return 1
    fi
    
    # Restore the file
    log_message "INFO" "Restoring file: $source_path -> $dest_path"
    
    if cp "$source_path" "$dest_path" 2>/dev/null; then
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
            '"0"')
                backup_file "$installation_path/SillyTavern" "$installation_path/Backups/SillyTavern" "config.yaml" "config.yaml"
                ;;
            '"1"')
                backup_file "$installation_path/SillyTavern/data/default-user" "$installation_path/Backups/SillyTavern/data/default-user" "settings.json" "settings.json"
                ;;
            '"2"')
                backup_directory "$installation_path/SillyTavern/data/default-user/characters" "$installation_path/Backups/SillyTavern/data/default-user/characters" "characters folder"
                ;;
            '"3"')
                backup_directory "$installation_path/SillyTavern/data/default-user/groups" "$installation_path/Backups/SillyTavern/data/default-user/groups" "groups folder"
                ;;
            '"4"')
                backup_directory "$installation_path/SillyTavern/data/default-user/worlds" "$installation_path/Backups/SillyTavern/data/default-user/worlds" "worlds folder"
                ;;
            '"5"')
                backup_directory "$installation_path/SillyTavern/data/default-user/chats" "$installation_path/Backups/SillyTavern/data/default-user/chats" "chats folder"
                ;;
            '"6"')
                backup_directory "$installation_path/SillyTavern/data/default-user/group chats" "$installation_path/Backups/SillyTavern/data/default-user/group chats" "group chats folder"
                ;;
            '"7"')
                backup_directory "$installation_path/SillyTavern/data/default-user/User Avatars" "$installation_path/Backups/SillyTavern/data/default-user/User Avatars" "User Avatars folder"
                ;;
            '"8"')
                backup_directory "$installation_path/SillyTavern/data/default-user/backgrounds" "$installation_path/Backups/SillyTavern/data/default-user/backgrounds" "backgrounds folder"
                ;;
            '"9"')
                backup_directory "$installation_path/SillyTavern/data/default-user/themes" "$installation_path/Backups/SillyTavern/data/default-user/themes" "themes folder"
                ;;
            '"10"')
                backup_directory "$installation_path/SillyTavern/data/default-user/TextGen Settings" "$installation_path/Backups/SillyTavern/data/default-user/TextGen Settings" "TextGen Settings folder"
                ;;
            '"11"')
                backup_directory "$installation_path/SillyTavern/data/default-user/context" "$installation_path/Backups/SillyTavern/data/default-user/context" "context folder"
                ;;
            '"12"')
                backup_directory "$installation_path/SillyTavern/data/default-user/instruct" "$installation_path/Backups/SillyTavern/data/default-user/instruct" "instruct folder"
                ;;
            '"13"')
                backup_directory "$installation_path/SillyTavern/data/default-user/sysprompt" "$installation_path/Backups/SillyTavern/data/default-user/sysprompt" "sysprompt folder"
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
            '"0"')
                restore_file "$installation_path/Backups/SillyTavern" "$installation_path/SillyTavern" "config.yaml" "config.yaml"
                ;;
            '"1"')
                restore_file "$installation_path/Backups/SillyTavern/data/default-user" "$installation_path/SillyTavern/data/default-user" "settings.json" "settings.json"
                ;;
            '"2"')
                restore_directory "$installation_path/Backups/SillyTavern/data/default-user/characters" "$installation_path/SillyTavern/data/default-user/characters" "characters folder"
                ;;
            '"3"')
                restore_directory "$installation_path/Backups/SillyTavern/data/default-user/groups" "$installation_path/SillyTavern/data/default-user/groups" "groups folder"
                ;;
            '"4"')
                restore_directory "$installation_path/Backups/SillyTavern/data/default-user/worlds" "$installation_path/SillyTavern/data/default-user/worlds" "worlds folder"
                ;;
            '"5"')
                restore_directory "$installation_path/Backups/SillyTavern/data/default-user/chats" "$installation_path/SillyTavern/data/default-user/chats" "chats folder"
                ;;
            '"6"')
                restore_directory "$installation_path/Backups/SillyTavern/data/default-user/group chats" "$installation_path/SillyTavern/data/default-user/group chats" "group chats folder"
                ;;
            '"7"')
                restore_directory "$installation_path/Backups/SillyTavern/data/default-user/User Avatars" "$installation_path/SillyTavern/data/default-user/User Avatars" "User Avatars folder"
                ;;
            '"8"')
                restore_directory "$installation_path/Backups/SillyTavern/data/default-user/backgrounds" "$installation_path/SillyTavern/data/default-user/backgrounds" "backgrounds folder"
                ;;
            '"9"')
                restore_directory "$installation_path/Backups/SillyTavern/data/default-user/themes" "$installation_path/SillyTavern/data/default-user/themes" "themes folder"
                ;;
            '"10"')
                restore_directory "$installation_path/Backups/SillyTavern/data/default-user/TextGen Settings" "$installation_path/SillyTavern/data/default-user/TextGen Settings" "TextGen Settings folder"
                ;;
            '"11"')
                restore_directory "$installation_path/Backups/SillyTavern/data/default-user/context" "$installation_path/SillyTavern/data/default-user/context" "context folder"
                ;;
            '"12"')
                restore_directory "$installation_path/Backups/SillyTavern/data/default-user/instruct" "$installation_path/SillyTavern/data/default-user/instruct" "instruct folder"
                ;;
            '"13"')
                restore_directory "$installation_path/Backups/SillyTavern/data/default-user/sysprompt" "$installation_path/SillyTavern/data/default-user/sysprompt" "sysprompt folder"
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
            '"0"')
                backup_directory "$installation_path/text-generation-webui/user_data/models" "$installation_path/Backups/text-generation-webui/user_data/models" "models folder"
                ;;
            '"1"')
                backup_directory "$installation_path/text-generation-webui/user_data/characters" "$installation_path/Backups/text-generation-webui/user_data/characters" "characters folder"
                ;;
            '"2"')
                backup_directory "$installation_path/text-generation-webui/user_data/presets" "$installation_path/Backups/text-generation-webui/user_data/presets" "presets folder"
                ;;
            '"3"')
                backup_directory "$installation_path/text-generation-webui/user_data/instruction-templates" "$installation_path/Backups/text-generation-webui/user_data/instruction-templates" "instruction-templates folder"
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
            '"0"')
                restore_directory "$installation_path/Backups/text-generation-webui/user_data/models" "$installation_path/text-generation-webui/user_data/models" "models folder"
                ;;
            '"1"')
                restore_directory "$installation_path/Backups/text-generation-webui/user_data/characters" "$installation_path/text-generation-webui/user_data/characters" "characters folder"
                ;;
            '"2"')
                restore_directory "$installation_path/Backups/text-generation-webui/user_data/presets" "$installation_path/text-generation-webui/user_data/presets" "presets folder"
                ;;
            '"3"')
                restore_directory "$installation_path/Backups/text-generation-webui/user_data/instruction-templates" "$installation_path/text-generation-webui/user_data/instruction-templates" "instruction-templates folder"
                ;;
        esac
    done
    
    log_message "INFO" "Text Generation Web UI restore operation completed"
    generate_backup_summary "Restore"
}