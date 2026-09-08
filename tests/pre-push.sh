#!/usr/bin/env bash
# Validate each outgoing commit, not the mutable working tree.
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel)"
push_updates="$(cat)"
[[ -n "$push_updates" ]] || exit 0

# Git exports repository-local variables into hooks. They must not make the
# isolated clone's commands operate on the original repository instead.
for git_variable in $(git rev-parse --local-env-vars); do
    unset "$git_variable"
done

scratch_dir=""
cleanup() {
    [[ -z "$scratch_dir" ]] || rm -rf -- "$scratch_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

checked_commits=" "
while read -r local_ref local_oid remote_ref remote_oid extra; do
    [[ -n "$local_ref" && -n "$local_oid" && -n "$remote_ref" && -n "$remote_oid" && -z "$extra" ]] || {
        printf 'Malformed pre-push update; refusing unvalidated push.\n' >&2
        exit 1
    }
    case "$local_oid" in
        *[!0]*) ;;
        *) continue ;; # Deleting a ref publishes no new code.
    esac
    commit_oid="$(git -C "$repo_root" rev-parse --verify "$local_oid^{commit}")" || {
        printf 'Cannot validate outgoing object %s as a commit.\n' "$local_oid" >&2
        exit 1
    }
    case "$checked_commits" in *" $commit_oid "*) continue ;; esac
    # Keep snapshots under the same host mount as the checkout. macOS's
    # per-user TMPDIR is not shared with Colima/Docker by default.
    snapshot_parent="$repo_root/.ci-validation"
    (umask 077; mkdir -p "$snapshot_parent")
    scratch_dir="$(mktemp -d "$snapshot_parent/push.XXXXXXXX")"
    # A full independent clone makes Git history available to secret scanning
    # and Docker without alternates that point outside its mounted checkout.
    git -c core.hooksPath=/dev/null clone --quiet --no-local --no-checkout \
        "$repo_root" "$scratch_dir/repo"
    # Explicit SHA pushes can reference a commit outside advertised branches.
    git -C "$scratch_dir/repo" -c core.hooksPath=/dev/null fetch --quiet --no-tags "$repo_root" "$commit_oid"
    git -C "$scratch_dir/repo" -c core.hooksPath=/dev/null checkout --quiet --detach "$commit_oid"
    if [[ ! -x "$scratch_dir/repo/tests/ci.sh" ]]; then
        printf 'Commit %s has no shared CI entrypoint that is executable; refusing unvalidated push.\n' "$commit_oid" >&2
        exit 1
    fi
    printf 'Validating %s -> %s (%s) in an isolated checkout.\n' "$local_ref" "$remote_ref" "$commit_oid" >&2
    if ! "$scratch_dir/repo/tests/ci.sh" full; then
        printf 'Push blocked: validation failed for %s. Fix the failure and commit the correction.\n' "$commit_oid" >&2
        exit 1
    fi
    checked_commits="$checked_commits$commit_oid "
    cleanup
    scratch_dir=""
done <<< "$push_updates"
