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
    printf '%s\n' "$token" > "$file"
}

# Print the token to use
read_shared_token() {
    local file
    file=$(shared_token_file)
    if [[ -f "$file" ]]; then
        cat "$file"
    fi
}

export -f shared_token_file save_shared_token read_shared_token
