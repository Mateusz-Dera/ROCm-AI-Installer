_log_filter() {
    LC_ALL=C sed -u 's/\x1b\[[0-9;?]*[a-zA-Z]//g' \
        | LC_ALL=C stdbuf -oL tr '\r' '\n' \
        | LC_ALL=C sed -u 's/^[[:space:]]*\([\o200-\o377][^ ]*[[:space:]]*\)\+//' \
        | LC_ALL=C grep --line-buffered -vE \
            '^(Resolving dependencies\.\.\.|(\[[0-9]+/[0-9]+\][[:space:]]*)?(Installing wheels\.\.\.|Preparing packages\.\.\.|[A-Za-z0-9._+-]+==[^[:space:]]*))[[:space:]]*$' \
        | LC_ALL=C grep --line-buffered -vE '^[[:space:]]*$'
}

attach_log() {
    [ -n "${TEST_LOG_ATTACHED:-}" ] && return 0
    export TEST_LOG_ATTACHED=1
    exec > >(_log_filter | tee -a "$1") 2>&1
}
