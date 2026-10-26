#!/usr/bin/env bash
# Token Commands - Shared login for all slots
# ============================================================================
# Commands: token set, token status, token remove
# One `claude setup-token` login reused by every slot of every project.

_cmd_token() {
    local subcommand="${1:-status}"
    case "$subcommand" in
        set)
            _token_set
            ;;
        status)
            _token_status
            ;;
        remove)
            rm -f "$(shared_token_file)"
            ;;
        *)
            printf '%s\n' "Usage: claudebox token [set|status|remove]" >&2
            return 1
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

# Run `claude setup-token` in a container, then save the token it prints.
# A hidden temporary slot keeps the user's real slots untouched; the slot
# list only shows visible folders.
_token_set() {
    local PROJECT_SLOT_DIR token status=0
    if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        printf '%s\n' "ERROR: No Docker image found for this project." \
            "Run 'claudebox' here first, or run this command in a project you already use." >&2
        return 1
    fi
    PROJECT_SLOT_DIR=$(mktemp -d "$PROJECT_PARENT_DIR/.token-setup.XXXXXX")
    mkdir -p "$PROJECT_SLOT_DIR/.claude" "$PROJECT_SLOT_DIR/.config" "$PROJECT_SLOT_DIR/.cache"
    run_claudebox_container "" "interactive" setup-token || status=$?
    rm -rf "$PROJECT_SLOT_DIR"
    if [[ $status -ne 0 ]]; then
        return "$status"
    fi

    printf '%s' "Paste the token shown above: " >&2
    IFS= read -r -s token || true
    printf '\n' >&2
    # Tokens contain no whitespace; drop any picked up while copying.
    token=$(printf '%s' "$token" | tr -d '[:space:]')
    if [[ -z "$token" ]]; then
        printf '%s\n' "ERROR: No token pasted; nothing saved." >&2
        return 1
    fi
    save_shared_token "$token"
}

export -f _cmd_token _token_set _token_status
