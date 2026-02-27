#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

# ============================================================
# PHASE 3: RESTORE
# ============================================================
phase3_restore() {
    info "============================================="
    info "PHASE 3: RESTORE"
    info "============================================="

    basic_container || abort "Container 'rocm' is not running."

    # --- SillyTavern restore ---
    if $SILLYTAVERN_WAS_INSTALLED; then
        info "Restoring SillyTavern..."
        reset_backup_tracking

        local st_bak="/AI/Backups/SillyTavern"
        local st_dst="/AI/SillyTavern"
        local st_bdata="$st_bak/data/default-user"
        local st_ddata="$st_dst/data/default-user"

        restore_file  "$st_bak"    "$st_dst"              "config.yaml"   "config.yaml"   || true
        restore_file  "$st_bdata"  "$st_ddata"            "settings.json" "settings.json" || true
        restore_directory "$st_bdata/characters"          "$st_ddata/characters"          "characters"      || true
        restore_directory "$st_bdata/groups"              "$st_ddata/groups"              "groups"          || true
        restore_directory "$st_bdata/worlds"              "$st_ddata/worlds"              "worlds"          || true
        restore_directory "$st_bdata/chats"               "$st_ddata/chats"               "chats"           || true
        restore_directory "$st_bdata/group chats"         "$st_ddata/group chats"         "group chats"     || true
        restore_directory "$st_bdata/User Avatars"        "$st_ddata/User Avatars"        "User Avatars"    || true
        restore_directory "$st_bdata/backgrounds"         "$st_ddata/backgrounds"         "backgrounds"     || true
        restore_directory "$st_bdata/themes"              "$st_ddata/themes"              "themes"          || true
        restore_directory "$st_bdata/TextGen Settings"    "$st_ddata/TextGen Settings"    "TextGen Settings" || true
        restore_directory "$st_bdata/context"             "$st_ddata/context"             "context"         || true
        restore_directory "$st_bdata/instruct"            "$st_ddata/instruct"            "instruct"        || true
        restore_directory "$st_bdata/sysprompt"           "$st_ddata/sysprompt"           "sysprompt"       || true

        if container_file_exists "$st_dst/config.yaml"; then
            pass "SillyTavern restore verified (config.yaml present)"
        else
            abort "SillyTavern restore FAILED – config.yaml missing in $st_dst"
        fi
    fi

    # --- TabbyAPI restore ---
    if $TABBYAPI_WAS_INSTALLED; then
        info "Restoring TabbyAPI models..."
        reset_backup_tracking

        restore_directory "/AI/Backups/tabbyAPI/models" "/AI/tabbyAPI/models" "models" || true

        if container_dir_exists "/AI/tabbyAPI/models"; then
            pass "TabbyAPI restore verified (models directory present)"
        else
            abort "TabbyAPI restore FAILED – /AI/tabbyAPI/models missing after restore"
        fi
    fi

    if ! $SILLYTAVERN_WAS_INSTALLED && ! $TABBYAPI_WAS_INSTALLED; then
        info "No backups were created in phase 1 – restore skipped"
    fi

    info "Phase 3 DONE"
}

main() { phase3_restore; }

main "$@"
