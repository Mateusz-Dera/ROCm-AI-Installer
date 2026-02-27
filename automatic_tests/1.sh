#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 1: BACKUP
# ============================================================
phase1_backup() {
    info "============================================="
    info "PHASE 1: BACKUP"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    # --- Detect installed apps that support backup ---
    if container_dir_exists "/AI/SillyTavern"; then
        SILLYTAVERN_WAS_INSTALLED=true
        info "SillyTavern detected – will create backup"
    else
        info "SillyTavern not installed – skipping backup"
    fi

    if container_dir_exists "/AI/tabbyAPI"; then
        TABBYAPI_WAS_INSTALLED=true
        info "TabbyAPI detected – will create backup"
    else
        info "TabbyAPI not installed – skipping backup"
    fi

    # --- SillyTavern backup ---
    if $SILLYTAVERN_WAS_INSTALLED; then
        info "Starting SillyTavern backup..."
        reset_backup_tracking

        local st_src="/AI/SillyTavern"
        local st_bak="/AI/Backups/SillyTavern"
        local st_data="$st_src/data/default-user"
        local st_bdata="$st_bak/data/default-user"

        backup_file  "$st_src"   "$st_bak"             "config.yaml"   "config.yaml"   || true
        backup_file  "$st_data"  "$st_bdata"            "settings.json" "settings.json" || true
        backup_directory "$st_data/characters"          "$st_bdata/characters"          "characters"      || true
        backup_directory "$st_data/groups"              "$st_bdata/groups"              "groups"          || true
        backup_directory "$st_data/worlds"              "$st_bdata/worlds"              "worlds"          || true
        backup_directory "$st_data/chats"               "$st_bdata/chats"               "chats"           || true
        backup_directory "$st_data/group chats"         "$st_bdata/group chats"         "group chats"     || true
        backup_directory "$st_data/User Avatars"        "$st_bdata/User Avatars"        "User Avatars"    || true
        backup_directory "$st_data/backgrounds"         "$st_bdata/backgrounds"         "backgrounds"     || true
        backup_directory "$st_data/themes"              "$st_bdata/themes"              "themes"          || true
        backup_directory "$st_data/TextGen Settings"    "$st_bdata/TextGen Settings"    "TextGen Settings" || true
        backup_directory "$st_data/context"             "$st_bdata/context"             "context"         || true
        backup_directory "$st_data/instruct"            "$st_bdata/instruct"            "instruct"        || true
        backup_directory "$st_data/sysprompt"           "$st_bdata/sysprompt"           "sysprompt"       || true

        # Verify – config.yaml must exist in backup
        if container_file_exists "$st_bak/config.yaml"; then
            pass "SillyTavern backup verified (config.yaml present)"
        else
            abort "SillyTavern backup FAILED – config.yaml missing in $st_bak"
        fi
    fi

    # --- TabbyAPI backup ---
    if $TABBYAPI_WAS_INSTALLED; then
        info "Starting TabbyAPI backup..."
        reset_backup_tracking

        backup_directory "/AI/tabbyAPI/models" "/AI/Backups/tabbyAPI/models" "models" || true

        if container_dir_exists "/AI/Backups/tabbyAPI/models"; then
            pass "TabbyAPI backup verified (models directory present)"
        else
            abort "TabbyAPI backup FAILED – /AI/Backups/tabbyAPI/models missing"
        fi
    fi

    if ! $SILLYTAVERN_WAS_INSTALLED && ! $TABBYAPI_WAS_INSTALLED; then
        info "No apps with backup support were previously installed – phase skipped"
    fi

    info "Phase 1 DONE"
}

main() {
    phase1_backup
    # Save state so phase3 can use SILLYTAVERN_WAS_INSTALLED / TABBYAPI_WAS_INSTALLED
    printf 'SILLYTAVERN_WAS_INSTALLED=%s\nTABBYAPI_WAS_INSTALLED=%s\n' \
        "$SILLYTAVERN_WAS_INSTALLED" "$TABBYAPI_WAS_INSTALLED" > "$TEST_STATE_FILE"
}

main "$@"
