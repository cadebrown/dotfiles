#!/usr/bin/env bats
# tests/netrc.bats — unit tests for the ~/.netrc helper family in install/_lib.sh.
#
# These helpers are how every auth.sh (parent and overlay) provisions credentials
# for curl/git/wget, so a parsing slip silently authenticates as the wrong user
# or drops an unrelated host's block. Each test runs against a throwaway HOME.
#
# Runs locally with brew-installed bats-core, and inside tests/run.sh docker.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    source "$REPO_ROOT/install/_lib.sh"
}

@test "_netrc_upsert creates the file at 600 with login and password" {
    _netrc_upsert example.com alice s3cret
    [ -f "$HOME/.netrc" ]
    [ "$(_netrc_login example.com)" = "alice" ]
    [ "$(stat -c '%a' "$HOME/.netrc" 2>/dev/null || stat -f '%OLp' "$HOME/.netrc")" = "600" ]
}

@test "_netrc_upsert replaces an existing host without touching its neighbours" {
    _netrc_upsert one.example alice tok1
    _netrc_upsert two.example bob   tok2
    _netrc_upsert one.example carol tok3

    [ "$(_netrc_login one.example)" = "carol" ]
    [ "$(_netrc_login two.example)" = "bob" ]
    # exactly one block per host — a stale duplicate would shadow the new creds
    [ "$(grep -c '^machine one.example$' "$HOME/.netrc")" -eq 1 ]
}

@test "_netrc_login reads the single-line netrc form" {
    printf 'machine solo.example login dave password tok\n' > "$HOME/.netrc"
    [ "$(_netrc_login solo.example)" = "dave" ]
}

@test "_netrc_login returns empty for an absent host or absent file" {
    [ -z "$(_netrc_login nothing.example)" ]
    _netrc_upsert present.example alice tok
    [ -z "$(_netrc_login absent.example)" ]
}

@test "_netrc_login is not confused by a host that is a prefix of another" {
    _netrc_upsert ci.example.org long tok2
    _netrc_upsert ci.example short tok1
    [ "$(_netrc_login ci.example)" = "short" ]
    [ "$(_netrc_login ci.example.org)" = "long" ]
}

@test "_netrc_remove drops one host and leaves the rest" {
    _netrc_upsert keep.example alice tok1
    _netrc_upsert drop.example bob   tok2
    _netrc_remove drop.example

    [ -z "$(_netrc_login drop.example)" ]
    [ "$(_netrc_login keep.example)" = "alice" ]
}

@test "_netrc_remove deletes the file once the last entry is gone" {
    _netrc_upsert only.example alice tok
    _netrc_remove only.example
    [ ! -f "$HOME/.netrc" ]
}

@test "a top-level default block survives upsert and remove" {
    printf 'default login anon password anon\n' > "$HOME/.netrc"
    _netrc_upsert host.example alice tok
    _netrc_remove host.example
    grep -q '^default login anon' "$HOME/.netrc"
}
