#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/common.sh"

APP_DIR="/AI/SillyTavern"
APP_PORT=8000
APP_LOG="/tmp/sillytavern_server.log"
PROC_PAT="start.sh"
NODE_PAT="node.*server"

_cleanup() {
    stop_app "$PROC_PAT" "" > /dev/null 2>&1 || true
    stop_app "$NODE_PAT" "$APP_PORT" > /dev/null 2>&1 || true
    reset_container || true
}
trap _cleanup EXIT INT TERM

_status() {
    ctr "curl -s -o /dev/null -w '%{http_code}' --max-time 10 $1 http://localhost:${APP_PORT}/"
}

test_sillytavern() {
    info "============================================="
    info "TEST: SillyTavern (serves and demands a login)"
    info "============================================="

    require_container

    stop_app "$PROC_PAT" ""
    stop_app "$NODE_PAT" "$APP_PORT"

    run_install "SillyTavern" install_sillytavern "$APP_DIR"

    ctr "grep -q '^basicAuthMode: true' '${APP_DIR}/default/config.yaml'" \
        || abort "SillyTavern: the installer left basicAuthMode off - the interface would be open to anyone"
    pass "Installer turned basicAuthMode on"

    ctr "grep -q '^listen: true' '${APP_DIR}/default/config.yaml'" \
        || abort "SillyTavern: the installer left listen off - the interface would only answer on localhost"
    pass "Installer turned listen on"

    start_app SillyTavern "$APP_LOG"

    info "Waiting for the server..."
    wait_for_http_or_abort "SillyTavern" \
        "test \$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:${APP_PORT}/) != 000" \
        "$PROC_PAT" "$APP_LOG" 900
    pass "Server ready on port ${APP_PORT}"

    if ! listens_on_all_interfaces "$APP_PORT"; then
        fail "  Listening addresses: $(port_listen_addrs "$APP_PORT" | tr '\n' ' ')"
        abort "SillyTavern: not listening on 0.0.0.0:${APP_PORT}"
    fi
    pass "Listening on 0.0.0.0:${APP_PORT}"

    local anonymous
    anonymous=$(_status "")
    [ "$anonymous" = "401" ] \
        || abort "SillyTavern: an anonymous request returned ${anonymous}, expected 401 - the page is not asking for a login"
    pass "An anonymous request is refused with 401"

    ctr "curl -s -I --max-time 10 http://localhost:${APP_PORT}/ | grep -qi '^www-authenticate:.*basic'" \
        || abort "SillyTavern: the 401 carries no 'WWW-Authenticate: Basic' header - no login prompt would appear"
    pass "The 401 asks the browser for credentials (WWW-Authenticate: Basic)"

    local wrong
    wrong=$(_status "-u test_wrong_user:test_wrong_password")
    [ "$wrong" = "401" ] \
        || abort "SillyTavern: wrong credentials returned ${wrong}, expected 401 - the password is not being checked"
    pass "Wrong credentials are rejected with 401"

    stop_app "$PROC_PAT" ""
    stop_app "$NODE_PAT" "$APP_PORT"
    pass "SillyTavern stopped"

    ctr "rm -f '${APP_LOG}'"
    info "Test sillytavern DONE"
}

main() { test_sillytavern; }
main "$@"
