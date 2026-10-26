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

# Say where the token comes from; never print the token itself
_token_status() {
    local file
    file=$(shared_token_file)
    if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
        printf '%s\n' "Shared token: set from CLAUDE_CODE_OAUTH_TOKEN"
    elif [[ -s "$file" ]]; then
        printf 'Shared token: saved in %s\n' "$file"
    else
        printf '%s\n' "Shared token: not set"
    fi
}

export -f _cmd_token _token_status
