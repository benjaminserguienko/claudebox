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
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/commands.token.sh"

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

status_without_token_says_not_set() {
    local output
    reset_token_state
    output=$(_cmd_token status 2>&1) || return 1
    printf '%s' "$output" | grep -q 'not set'
}

check "token status reports when no token is set" status_without_token_says_not_set

status_names_saved_file_without_revealing_token() {
    local output
    reset_token_state
    save_shared_token "sk-ant-oat01-secret-value" || return 1
    output=$(_cmd_token status 2>&1) || return 1
    printf '%s' "$output" | grep -q 'oauth-token' &&
        ! printf '%s' "$output" | grep -q 'secret-value'
}

status_names_host_variable_without_revealing_token() {
    local output
    reset_token_state
    output=$(CLAUDE_CODE_OAUTH_TOKEN="sk-ant-oat01-secret-value" _cmd_token status 2>&1) || return 1
    printf '%s' "$output" | grep -q 'CLAUDE_CODE_OAUTH_TOKEN' &&
        ! printf '%s' "$output" | grep -q 'secret-value'
}

check "token status names the saved file without showing the token" status_names_saved_file_without_revealing_token
check "token status names the host variable without showing the token" status_names_host_variable_without_revealing_token

remove_forgets_saved_token() {
    local empty
    reset_token_state
    empty=$(make_slot empty)
    save_shared_token "sk-ant-oat01-saved" || return 1
    _cmd_token remove >/dev/null 2>&1 || return 1
    [ ! -e "$CLAUDEBOX_HOME/oauth-token" ] && ! slot_is_authenticated "$empty"
}

check "token remove forgets the saved token" remove_forgets_saved_token

# token set runs Claude in a container; stub the launcher and record what it got.
export PROJECT_DIR="$SANDBOX/project"
export PROJECT_PARENT_DIR="$CLAUDEBOX_HOME/projects/test"
export IMAGE_NAME="claudebox-test"
docker() { return 0; }
run_claudebox_container() {
    printf '%s\n' "$*" > "$SANDBOX/run-args"
    printf '%s\n' "$PROJECT_SLOT_DIR" > "$SANDBOX/run-slot"
    [ -d "$PROJECT_SLOT_DIR" ] && printf 'exists\n' >> "$SANDBOX/run-slot"
    return 0
}

set_saves_pasted_token_from_setup_token() {
    local slot output
    reset_token_state
    mkdir -p "$PROJECT_PARENT_DIR"
    rm -f "$SANDBOX/run-args" "$SANDBOX/run-slot"
    output=$(printf '  sk-ant-oat01-pasted  \n' | _cmd_token set 2>&1) || return 1
    slot=$(head -n 1 "$SANDBOX/run-slot")
    printf '%s' "$output" | grep -q 'Shared token saved' &&
        ! printf '%s' "$output" | grep -q 'pasted' &&
        grep -q 'setup-token' "$SANDBOX/run-args" &&
        grep -q '^exists$' "$SANDBOX/run-slot" &&
        case "$slot" in "$PROJECT_PARENT_DIR"/.*) true ;; *) false ;; esac &&
        [ ! -d "$slot" ] &&
        [ "$(read_shared_token)" = "sk-ant-oat01-pasted" ]
}

check "token set runs setup-token in a temporary slot and saves the pasted token" set_saves_pasted_token_from_setup_token

set_rejects_empty_paste_and_keeps_old_token() {
    reset_token_state
    mkdir -p "$PROJECT_PARENT_DIR"
    save_shared_token "sk-ant-oat01-old" || return 1
    if printf '   \n' | _cmd_token set >/dev/null 2>&1; then
        return 1
    fi
    [ "$(read_shared_token)" = "sk-ant-oat01-old" ]
}

check "token set rejects an empty paste and keeps the saved token" set_rejects_empty_paste_and_keeps_old_token

set_without_image_explains_and_runs_nothing() {
    local output status=0
    reset_token_state
    mkdir -p "$PROJECT_PARENT_DIR"
    rm -f "$SANDBOX/run-args"
    docker() { return 1; }
    output=$(printf 'sk-ant-oat01-x\n' | _cmd_token set 2>&1) || status=$?
    docker() { return 0; }
    [ "$status" -ne 0 ] &&
        printf '%s' "$output" | grep -q 'image' &&
        [ ! -f "$SANDBOX/run-args" ]
}

check "token set without a built image explains and starts no container" set_without_image_explains_and_runs_nothing

unknown_subcommand_shows_usage() {
    local output status=0
    output=$(_cmd_token bogus 2>&1) || status=$?
    [ "$status" -ne 0 ] && printf '%s' "$output" | grep -q 'Usage: claudebox token'
}

check "unknown token subcommand shows usage and fails" unknown_subcommand_shows_usage

printf '\n%d/%d tests passed\n' "$TESTS_PASSED" "$TESTS_RUN"
[ "$TESTS_PASSED" -eq "$TESTS_RUN" ]
