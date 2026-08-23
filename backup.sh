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

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/interfaces.sh"

declare -a successful_backups=()
declare -a failed_backups=()

BACKUP_ROOT="/AI/Backups"
SNAPSHOT_DIR=""
SNAPSHOT_LINK_DEST=""

snapshot_sanitize() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._ -' '_' | sed 's/^[ .]*//; s/[ ]*$//' | cut -c1-64
}

snapshot_list() {
    local app="$1"
    podman exec -t rocm bash -c "
        [ -d '${BACKUP_ROOT}/${app}' ] || exit 0
        for d in '${BACKUP_ROOT}/${app}'/*/; do
            [ -d \"\$d\" ] || continue
            name=\$(basename \"\$d\")
            size=\$(du -sh \"\$d\" 2>/dev/null | cut -f1)
            when=\$(date -r \"\$d\" '+%Y-%m-%d %H:%M' 2>/dev/null)
            printf '%s|%s|%s\\n' \"\$name\" \"\$when\" \"\$size\"
        done" 2>/dev/null | tr -d '\r'
}

snapshot_pick() {
    local app="$1" title="$2" prompt="$3"
    local entries=() name when size first=""

    while IFS='|' read -r name when size; do
        [ -n "$name" ] || continue
        [ -z "$first" ] && first="$name"
        entries+=("$name" "${when}  ${size}" "$([ "$name" = "$first" ] && echo ON || echo OFF)")
    done < <(snapshot_list "$app" | sort -r)

    if [ ${#entries[@]} -eq 0 ]; then
        whiptail --title "$title" --msgbox "There is no backup of ${app} yet." 10 60
        return 1
    fi

    whiptail --title "$title" --radiolist "$prompt" 20 74 10 "${entries[@]}" 3>&1 1>&2 2>&3
}

snapshot_create() {
    local app="$1"
    local suggested name path

    suggested=$(date '+%Y-%m-%d_%H-%M')
    name=$(whiptail --title "Name this backup" --inputbox \
        "A name for this backup of ${app}.\n\nIt becomes a folder under ${BACKUP_ROOT}/${app}, so earlier backups stay where they are." \
        12 74 "$suggested" 3>&1 1>&2 2>&3) || return 1

    name=$(snapshot_sanitize "$name")
    if [ -z "$name" ]; then
        whiptail --title "Name this backup" --msgbox "That name has no usable characters." 10 60
        return 1
    fi

    path="${BACKUP_ROOT}/${app}/${name}"
    if podman exec -t rocm bash -c "[ -e '$path' ]" 2>/dev/null; then
        whiptail --title "Name already taken" --yesno \
            "A backup named '${name}' already exists.\n\nReplace it? Its current contents are deleted." 12 66 || return 1
        podman exec -t rocm bash -c "rm -rf '$path'" 2>/dev/null || return 1
    fi

    SNAPSHOT_LINK_DEST=""
    local previous
    previous=$(snapshot_list "$app" | sort -r | head -1 | cut -d'|' -f1)
    [ -n "$previous" ] && SNAPSHOT_LINK_DEST="${BACKUP_ROOT}/${app}/${previous}"

    podman exec -t rocm bash -c "mkdir -p '$path'" 2>/dev/null || return 1
    SNAPSHOT_DIR="$path"
    log_message "INFO" "Backup snapshot: $path"
    return 0
}

snapshot_manifest() {
    local app="$1"
    [ -n "$SNAPSHOT_DIR" ] || return 0
    local body="" item
    for item in "${successful_backups[@]}"; do
        body+="${item}"$'\n'
    done
    podman exec -t rocm bash -c "cat > '${SNAPSHOT_DIR}/manifest.txt' << 'MANIFESTEOF'
application: ${app}
created: $(date '+%Y-%m-%d %H:%M:%S')
items:
${body}MANIFESTEOF" 2>/dev/null || true
}

snapshot_delete() {
    local app="$1" name
    name=$(snapshot_pick "$app" "Delete a backup" "Which backup of ${app} should be deleted?") || return 0
    [ -n "$name" ] || return 0

    local path="${BACKUP_ROOT}/${app}/${name}"
    local size
    size=$(podman exec -t rocm bash -c "du -sh '$path' 2>/dev/null | cut -f1" | tr -d '\r')

    whiptail --title "Delete a backup" --defaultno --yesno \
        "Delete the backup '${name}' of ${app}?\n\nSize: ${size}\n\nThis cannot be undone." 13 66 || return 0

    if podman exec -t rocm bash -c "rm -rf '$path'" 2>/dev/null; then
        whiptail --title "Delete a backup" --msgbox "Deleted '${name}'." 10 60
    else
        whiptail --title "Delete a backup" --msgbox "Could not delete '${name}'." 10 60
    fi
}

log_message() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >&2
}

snapshot_copy_cmd() {
    local source_path="$1" dest_path="$2" link="" link_arg=""

    if [ -n "$SNAPSHOT_LINK_DEST" ] && [ -n "$SNAPSHOT_DIR" ]; then
        case "$dest_path" in
            "${SNAPSHOT_DIR}"/*) link="${SNAPSHOT_LINK_DEST}/${dest_path#${SNAPSHOT_DIR}/}" ;;
        esac
    fi
    [ -n "$link" ] && link_arg="--link-dest='${link}'"

    printf '%s' "if command -v rsync > /dev/null 2>&1; then mkdir -p '${dest_path}' && rsync -a --delete ${link_arg} '${source_path}/' '${dest_path}/'; else cp -a '${source_path}' '${dest_path}'; fi"
}

backup_directory() {
    local source_path="$1"
    local dest_path="$2"
    local item_name="$3"

    if [[ -z "$source_path" || -z "$dest_path" || -z "$item_name" ]]; then
        log_message "ERROR" "backup_directory: Missing required parameters"
        return 1
    fi

    if ! podman exec -t rocm bash -c "[ -e '$source_path' ]" 2>/dev/null; then
        log_message "WARNING" "Source path does not exist: $source_path"
        failed_backups+=("$item_name (source not found)")
        return 1
    fi

    local dest_parent
    dest_parent="$(dirname "$dest_path")"
    if ! podman exec -t rocm bash -c "mkdir -p '$dest_parent'" 2>/dev/null; then
        log_message "ERROR" "Failed to create parent directory: $dest_parent"
        failed_backups+=("$item_name (parent dir creation failed)")
        return 1
    fi

    if podman exec -t rocm bash -c "[ -e '$dest_path' ]" 2>/dev/null; then
        if ! podman exec -t rocm bash -c "rm -rf '$dest_path'" 2>/dev/null; then
            log_message "ERROR" "Failed to remove existing destination: $dest_path"
            failed_backups+=("$item_name (cleanup failed)")
            return 1
        fi
    fi

    log_message "INFO" "Backing up: $source_path -> $dest_path"

    if podman exec -t rocm bash -c "[ -d '$source_path' ]" 2>/dev/null; then
        if podman exec -t rocm bash -c "$(snapshot_copy_cmd "$source_path" "$dest_path")" 2>/dev/null; then
            log_message "SUCCESS" "Successfully backed up directory: $item_name"
            successful_backups+=("$item_name")
            return 0
        else
            log_message "ERROR" "Failed to backup directory: $source_path"
            failed_backups+=("$item_name (copy failed)")
            return 1
        fi
    else
        if podman exec -t rocm bash -c "cp -p '$source_path' '$dest_path'" 2>/dev/null; then
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

backup_file() {
    local source_dir="$1"
    local dest_dir="$2"
    local filename="$3"
    local item_name="$4"

    if [[ -z "$source_dir" || -z "$dest_dir" || -z "$filename" || -z "$item_name" ]]; then
        log_message "ERROR" "backup_file: Missing required parameters"
        return 1
    fi

    local source_path="$source_dir/$filename"
    local dest_path="$dest_dir/$filename"

    if ! podman exec -t rocm bash -c "[ -f '$source_path' ]" 2>/dev/null; then
        log_message "WARNING" "Source file does not exist: $source_path"
        failed_backups+=("$item_name (file not found)")
        return 1
    fi

    if ! podman exec -t rocm bash -c "mkdir -p '$dest_dir'" 2>/dev/null; then
        log_message "ERROR" "Failed to create destination directory: $dest_dir"
        failed_backups+=("$item_name (dest dir creation failed)")
        return 1
    fi

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

restore_directory() {
    local source_path="$1"
    local dest_path="$2"
    local item_name="$3"

    if [[ -z "$source_path" || -z "$dest_path" || -z "$item_name" ]]; then
        log_message "ERROR" "restore_directory: Missing required parameters"
        return 1
    fi

    if ! podman exec -t rocm bash -c "[ -e '$source_path' ]" 2>/dev/null; then
        log_message "WARNING" "Backup source does not exist: $source_path"
        failed_backups+=("$item_name (backup not found)")
        return 1
    fi

    local dest_parent
    dest_parent="$(dirname "$dest_path")"
    if ! podman exec -t rocm bash -c "mkdir -p '$dest_parent'" 2>/dev/null; then
        log_message "ERROR" "Failed to create parent directory: $dest_parent"
        failed_backups+=("$item_name (parent dir creation failed)")
        return 1
    fi

    if podman exec -t rocm bash -c "[ -e '$dest_path' ]" 2>/dev/null; then
        if ! podman exec -t rocm bash -c "rm -rf '$dest_path'" 2>/dev/null; then
            log_message "ERROR" "Failed to remove existing destination: $dest_path"
            failed_backups+=("$item_name (cleanup failed)")
            return 1
        fi
    fi

    log_message "INFO" "Restoring: $source_path -> $dest_path"

    if podman exec -t rocm bash -c "[ -d '$source_path' ]" 2>/dev/null; then
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
        if podman exec -t rocm bash -c "cp -p '$source_path' '$dest_path'" 2>/dev/null; then
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

restore_file() {
    local source_dir="$1"
    local dest_dir="$2"
    local filename="$3"
    local item_name="$4"

    if [[ -z "$source_dir" || -z "$dest_dir" || -z "$filename" || -z "$item_name" ]]; then
        log_message "ERROR" "restore_file: Missing required parameters"
        return 1
    fi

    local source_path="$source_dir/$filename"
    local dest_path="$dest_dir/$filename"

    if ! podman exec -t rocm bash -c "[ -f '$source_path' ]" 2>/dev/null; then
        log_message "WARNING" "Backup file does not exist: $source_path"
        failed_backups+=("$item_name (backup not found)")
        return 1
    fi

    if ! podman exec -t rocm bash -c "mkdir -p '$dest_dir'" 2>/dev/null; then
        log_message "ERROR" "Failed to create destination directory: $dest_dir"
        failed_backups+=("$item_name (dest dir creation failed)")
        return 1
    fi

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

reset_backup_tracking() {
    successful_backups=()
    failed_backups=()
}

generate_backup_summary() {
    local operation="$1"  # "Backup" or "Restore"
    local summary_msg=""
    
    if [[ ${#failed_backups[@]} -gt 0 ]]; then
        summary_msg="Failed to ${operation,,}:\n"
        for item in "${failed_backups[@]}"; do
            summary_msg+="• $item\n"
        done
        summary_msg+="\n"
    fi
    
    if [[ ${#successful_backups[@]} -gt 0 ]]; then
        summary_msg+="Successfully ${operation,,}d:\n"
        for item in "${successful_backups[@]}"; do
            summary_msg+="• $item\n"
        done
    fi
    
    local summary_title="$operation Summary"
    if [[ ${#failed_backups[@]} -eq 0 && ${#successful_backups[@]} -gt 0 ]]; then
        summary_title="$operation Summary - All Successful"
    elif [[ ${#successful_backups[@]} -eq 0 ]]; then
        summary_title="$operation Summary - All Failed"
    fi
    
    if [[ -n "$summary_msg" ]]; then
        whiptail --title "$summary_title" --msgbox "$summary_msg" 22 70
    else
        whiptail --title "$operation Summary" --msgbox "No items were selected for $operation." 10 50
    fi
}

perform_llamacpp_backup() {
    local folder="$1"
    local choices="$2"

    basic_container || return 1

    snapshot_create "$folder" || return 0

    reset_backup_tracking

    log_message "INFO" "Starting $folder backup operation"

    for choice in $choices; do
        case $choice in
            1)
                backup_directory "/AI/$folder/user-models" "$SNAPSHOT_DIR/user-models" "models"
                ;;
            2)
                backup_directory "/AI/$folder/drafts" "$SNAPSHOT_DIR/drafts" "drafts"
                ;;
            3)
                backup_file "/AI/$folder" "$SNAPSHOT_DIR" "models.ini" "models.ini"
                ;;
        esac
    done

    snapshot_manifest "$folder"

    log_message "INFO" "$folder backup operation completed"
    generate_backup_summary "Backup"
}

perform_llamacpp_restore() {
    local folder="$1"
    local choices="$2"

    basic_container || return 1

    local chosen
    chosen=$(snapshot_pick "$folder" "Restore" "Which backup of ${folder} should be restored?") || return 0
    [ -n "$chosen" ] || return 0
    SNAPSHOT_DIR="${BACKUP_ROOT}/${folder}/${chosen}"

    reset_backup_tracking

    log_message "INFO" "Starting $folder restore operation from ${chosen}"

    for choice in $choices; do
        case $choice in
            1)
                restore_directory "$SNAPSHOT_DIR/user-models" "/AI/$folder/user-models" "models"
                ;;
            2)
                restore_directory "$SNAPSHOT_DIR/drafts" "/AI/$folder/drafts" "drafts"
                ;;
            3)
                restore_file "$SNAPSHOT_DIR" "/AI/$folder" "models.ini" "models.ini"
                ;;
        esac
    done

    log_message "INFO" "$folder restore operation completed"
    generate_backup_summary "Restore"
}

perform_sillytavern_backup() {
    local choices="$1"

    basic_container || return 1

    snapshot_create "SillyTavern" || return 0

    reset_backup_tracking

    log_message "INFO" "Starting SillyTavern backup operation"
    
    for choice in $choices; do
        case $choice in
            1)
                backup_file "/AI/SillyTavern" "$SNAPSHOT_DIR" "config.yaml" "config.yaml"
                ;;
            2)
                backup_file "/AI/SillyTavern/data/default-user" "$SNAPSHOT_DIR/data/default-user" "settings.json" "settings.json"
                ;;
            3)
                backup_directory "/AI/SillyTavern/data/default-user/characters" "$SNAPSHOT_DIR/data/default-user/characters" "characters folder"
                ;;
            4)
                backup_directory "/AI/SillyTavern/data/default-user/groups" "$SNAPSHOT_DIR/data/default-user/groups" "groups folder"
                ;;
            5)
                backup_directory "/AI/SillyTavern/data/default-user/worlds" "$SNAPSHOT_DIR/data/default-user/worlds" "worlds folder"
                ;;
            6)
                backup_directory "/AI/SillyTavern/data/default-user/chats" "$SNAPSHOT_DIR/data/default-user/chats" "chats folder"
                ;;
            7)
                backup_directory "/AI/SillyTavern/data/default-user/group chats" "$SNAPSHOT_DIR/data/default-user/group chats" "group chats folder"
                ;;
            8)
                backup_directory "/AI/SillyTavern/data/default-user/User Avatars" "$SNAPSHOT_DIR/data/default-user/User Avatars" "User Avatars folder"
                ;;
            9)
                backup_directory "/AI/SillyTavern/data/default-user/backgrounds" "$SNAPSHOT_DIR/data/default-user/backgrounds" "backgrounds folder"
                ;;
            10)
                backup_directory "/AI/SillyTavern/data/default-user/themes" "$SNAPSHOT_DIR/data/default-user/themes" "themes folder"
                ;;
            11)
                backup_directory "/AI/SillyTavern/data/default-user/TextGen Settings" "$SNAPSHOT_DIR/data/default-user/TextGen Settings" "TextGen Settings folder"
                ;;
            12)
                backup_directory "/AI/SillyTavern/data/default-user/context" "$SNAPSHOT_DIR/data/default-user/context" "context folder"
                ;;
            13)
                backup_directory "/AI/SillyTavern/data/default-user/instruct" "$SNAPSHOT_DIR/data/default-user/instruct" "instruct folder"
                ;;
            14)
                backup_directory "/AI/SillyTavern/data/default-user/sysprompt" "$SNAPSHOT_DIR/data/default-user/sysprompt" "sysprompt folder"
                ;;
        esac
    done
    
    snapshot_manifest "SillyTavern"

    log_message "INFO" "SillyTavern backup operation completed"
    generate_backup_summary "Backup"
}

perform_sillytavern_restore() {
    local choices="$1"

    basic_container || return 1

    local chosen
    chosen=$(snapshot_pick "SillyTavern" "Restore" "Which backup of SillyTavern should be restored?") || return 0
    [ -n "$chosen" ] || return 0
    SNAPSHOT_DIR="${BACKUP_ROOT}/SillyTavern/${chosen}"

    reset_backup_tracking

    log_message "INFO" "Starting SillyTavern restore operation from ${chosen}"
    
    for choice in $choices; do
        case $choice in
            1)
                restore_file "$SNAPSHOT_DIR" "/AI/SillyTavern" "config.yaml" "config.yaml"
                ;;
            2)
                restore_file "$SNAPSHOT_DIR/data/default-user" "/AI/SillyTavern/data/default-user" "settings.json" "settings.json"
                ;;
            3)
                restore_directory "$SNAPSHOT_DIR/data/default-user/characters" "/AI/SillyTavern/data/default-user/characters" "characters folder"
                ;;
            4)
                restore_directory "$SNAPSHOT_DIR/data/default-user/groups" "/AI/SillyTavern/data/default-user/groups" "groups folder"
                ;;
            5)
                restore_directory "$SNAPSHOT_DIR/data/default-user/worlds" "/AI/SillyTavern/data/default-user/worlds" "worlds folder"
                ;;
            6)
                restore_directory "$SNAPSHOT_DIR/data/default-user/chats" "/AI/SillyTavern/data/default-user/chats" "chats folder"
                ;;
            7)
                restore_directory "$SNAPSHOT_DIR/data/default-user/group chats" "/AI/SillyTavern/data/default-user/group chats" "group chats folder"
                ;;
            8)
                restore_directory "$SNAPSHOT_DIR/data/default-user/User Avatars" "/AI/SillyTavern/data/default-user/User Avatars" "User Avatars folder"
                ;;
            9)
                restore_directory "$SNAPSHOT_DIR/data/default-user/backgrounds" "/AI/SillyTavern/data/default-user/backgrounds" "backgrounds folder"
                ;;
            10)
                restore_directory "$SNAPSHOT_DIR/data/default-user/themes" "/AI/SillyTavern/data/default-user/themes" "themes folder"
                ;;
            11)
                restore_directory "$SNAPSHOT_DIR/data/default-user/TextGen Settings" "/AI/SillyTavern/data/default-user/TextGen Settings" "TextGen Settings folder"
                ;;
            12)
                restore_directory "$SNAPSHOT_DIR/data/default-user/context" "/AI/SillyTavern/data/default-user/context" "context folder"
                ;;
            13)
                restore_directory "$SNAPSHOT_DIR/data/default-user/instruct" "/AI/SillyTavern/data/default-user/instruct" "instruct folder"
                ;;
            14)
                restore_directory "$SNAPSHOT_DIR/data/default-user/sysprompt" "/AI/SillyTavern/data/default-user/sysprompt" "sysprompt folder"
                ;;
        esac
    done
    
    log_message "INFO" "SillyTavern restore operation completed"
    generate_backup_summary "Restore"
}