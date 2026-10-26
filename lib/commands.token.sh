#!/usr/bin/env bash
# Token Commands - Shared login for all slots
# ============================================================================
# Commands: token status
# One `claude setup-token` login reused by every slot of every project.

_cmd_token() {
    local subcommand="${1:-status}"
    case "$subcommand" in
        status)
            _token_status
            ;;
    esac
}

_token_status() {
    printf '%s\n' "Shared token: not set"
}

export -f _cmd_token _token_status
