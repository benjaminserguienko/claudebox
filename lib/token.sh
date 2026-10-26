#!/usr/bin/env bash
# Shared OAuth token
# ============================================================================
# One long-lived token from `claude setup-token`, saved once on the host and
# given to every slot of every project, so slots don't need their own login.

# Where the saved token lives
shared_token_file() {
    printf '%s/oauth-token\n' "${CLAUDEBOX_HOME:-$HOME/.claudebox}"
}

# Save a token for all projects
save_shared_token() {
    local token="$1"
    local file
    file=$(shared_token_file)
    mkdir -p "$(dirname "$file")"
    # The subshell umask keeps the file private from the moment it exists;
    # chmod also tightens a file left over with looser permissions.
    (
        umask 077
        printf '%s\n' "$token" > "$file"
    )
    chmod 600 "$file"
}

# Print the token to use: the host variable if set, otherwise the saved file
read_shared_token() {
    local file
    if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
        printf '%s\n' "$CLAUDE_CODE_OAUTH_TOKEN"
        return 0
    fi
    file=$(shared_token_file)
    if [[ -f "$file" ]]; then
        cat "$file"
    fi
}

# Succeeds when Claude in this slot can start without logging in
slot_is_authenticated() {
    local slot_dir="$1"
    [[ -f "$slot_dir/.claude/.credentials.json" ]]
}

export -f shared_token_file save_shared_token read_shared_token slot_is_authenticated
