#!/usr/bin/env bash
# Shared OAuth token: one `claude setup-token` login reused by every slot of
# every project. No Docker daemon is needed; Docker is stubbed where used.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/claudebox-shared-token.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

export HOME="$SANDBOX/home"
export CLAUDEBOX_HOME="$HOME/.claudebox"
export VERBOSE=false
unset CLAUDE_CODE_OAUTH_TOKEN
mkdir -p "$HOME"

# shellcheck disable=SC1091
source "$ROOT_DIR/lib/token.sh"

TESTS_RUN=0
TESTS_PASSED=0

check() {
    local name="$1"
    shift
    TESTS_RUN=$((TESTS_RUN + 1))
    printf 'Test %d: %s... ' "$TESTS_RUN" "$name"
    if "$@"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf 'PASS\n'
    else
        printf 'FAIL\n'
    fi
}

# Each case starts with no saved token and no host variable.
reset_token_state() {
    rm -rf "$CLAUDEBOX_HOME"
    unset CLAUDE_CODE_OAUTH_TOKEN
}

saved_token_is_read_back() {
    reset_token_state
    save_shared_token "sk-ant-oat01-saved" || return 1
    [ "$(read_shared_token)" = "sk-ant-oat01-saved" ]
}

check "saved token is read back" saved_token_is_read_back

# find -perm with an exact mode is POSIX; stat output differs on macOS.
saved_token_is_owner_only() {
    reset_token_state
    save_shared_token "sk-ant-oat01-private" || return 1
    [ -n "$(find "$CLAUDEBOX_HOME/oauth-token" -perm 600)" ]
}

check "saved token file is readable only by its owner" saved_token_is_owner_only

host_variable_wins_over_saved_token() {
    reset_token_state
    save_shared_token "sk-ant-oat01-saved" || return 1
    [ "$(CLAUDE_CODE_OAUTH_TOKEN="sk-ant-oat01-host" read_shared_token)" = "sk-ant-oat01-host" ]
}

check "host CLAUDE_CODE_OAUTH_TOKEN wins over the saved token" host_variable_wins_over_saved_token

make_slot() {
    local dir="$SANDBOX/slots/$1"
    rm -rf "$dir"
    mkdir -p "$dir/.claude"
    printf '%s\n' "$dir"
}

slot_login_decides_without_shared_token() {
    local logged_in empty
    reset_token_state
    logged_in=$(make_slot logged-in)
    empty=$(make_slot empty)
    printf '{}\n' > "$logged_in/.claude/.credentials.json"
    slot_is_authenticated "$logged_in" && ! slot_is_authenticated "$empty"
}

check "without a shared token only slots with their own login are authenticated" slot_login_decides_without_shared_token

saved_token_authenticates_every_slot() {
    local empty
    reset_token_state
    empty=$(make_slot empty)
    save_shared_token "sk-ant-oat01-saved" || return 1
    slot_is_authenticated "$empty"
}

host_variable_authenticates_every_slot() {
    local empty
    reset_token_state
    empty=$(make_slot empty)
    CLAUDE_CODE_OAUTH_TOKEN="sk-ant-oat01-host" slot_is_authenticated "$empty"
}

check "a saved shared token authenticates a slot without its own login" saved_token_authenticates_every_slot
check "a host token authenticates a slot without its own login" host_variable_authenticates_every_slot

printf '\n%d/%d tests passed\n' "$TESTS_PASSED" "$TESTS_RUN"
[ "$TESTS_PASSED" -eq "$TESTS_RUN" ]
