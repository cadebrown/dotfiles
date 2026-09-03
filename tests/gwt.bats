#!/usr/bin/env bats

setup() {
    SCRIPT="${REPO:-$HOME/dotfiles}/home/dot_local/bin/executable_git-wt"
    TEST_ROOT="$(mktemp -d)"
    export HOME="$TEST_ROOT/home"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL="$TEST_ROOT/global.gitconfig"
    mkdir -p "$HOME"
    git config --global user.name "Test User"
    git config --global user.email test@example.com
    git config --global safe.bareRepository explicit
    git config --global gwt.github.com.user cadebrown
    git config --global gwt.gitlab-master.nvidia.com.user cadeb
}

teardown() {
    rm -rf "$TEST_ROOT"
}

make_repo() {
    local branch="${1:-main}"
    REPO_DIR="$TEST_ROOT/proj"
    git init -q -b "$branch" "$REPO_DIR"
    printf 'base\n' > "$REPO_DIR/tracked.txt"
    git -C "$REPO_DIR" add tracked.txt
    git -C "$REPO_DIR" commit -qm initial
}

@test "help describes policy commands and configuration" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"git wt new <name>"* ]]
    [[ "$output" == *'[gwt "github.com"]'* ]]

    run bash "$SCRIPT" help init
    [ "$status" -eq 0 ]
    [[ "$output" == *"preserves staged, unstaged, and untracked files"* ]]

    run bash "$SCRIPT" help add
    [ "$status" -eq 0 ]
    [[ "$output" == *"fetched remote-tracking branch"* ]]
    [[ "$output" == *"does not fetch"* ]]
}

@test "git discovers the helper as an external subcommand" {
    mkdir -p "$TEST_ROOT/bin"
    cp "$SCRIPT" "$TEST_ROOT/bin/git-wt"
    chmod +x "$TEST_ROOT/bin/git-wt"

    run env PATH="$TEST_ROOT/bin:$PATH" git wt help new
    [ "$status" -eq 0 ]
    [[ "$output" == *"Create a new personal branch"* ]]
}

@test "init preserves a nested branch path and working state" {
    make_repo cadeb/name/feat
    printf 'staged\n' >> "$REPO_DIR/tracked.txt"
    git -C "$REPO_DIR" add tracked.txt
    printf 'unstaged\n' >> "$REPO_DIR/tracked.txt"
    printf 'untracked\n' > "$REPO_DIR/untracked.txt"

    cd "$REPO_DIR"
    run bash "$SCRIPT" init --print-path
    [ "$status" -eq 0 ]
    [[ "$output" == *"$REPO_DIR/cadeb/name/feat"* ]]
    [ -d "$REPO_DIR/.bare" ]
    [ -f "$REPO_DIR/cadeb/name/feat/.git" ]
    [[ "$(head -n 1 "$REPO_DIR/cadeb/name/feat/.git")" == "gitdir: "*"/.bare/"* ]]

    status_output="$(git -C "$REPO_DIR/cadeb/name/feat" status --short)"
    [[ "$status_output" == *"MM tracked.txt"* ]]
    [[ "$status_output" == *"?? untracked.txt"* ]]
}

@test "new uses the GitHub identity rather than the remote owner" {
    make_repo
    git -C "$REPO_DIR" remote add origin git@github.com:some-org/project.git
    cd "$REPO_DIR"
    bash "$SCRIPT" init --print-path >/dev/null
    cd "$REPO_DIR/main"

    run bash "$SCRIPT" new name/feat
    [ "$status" -eq 0 ]
    [ -f "$REPO_DIR/cadebrown/name/feat/.git" ]
    [ "$(git -C "$REPO_DIR/cadebrown/name/feat" branch --show-current)" = "cadebrown/name/feat" ]
}

@test "new selects the NVIDIA identity from an SSH URL" {
    make_repo
    git -C "$REPO_DIR" remote add origin \
        ssh://git@gitlab-master.nvidia.com:12051/mathlibs/project.git
    cd "$REPO_DIR"
    bash "$SCRIPT" init --print-path >/dev/null
    cd "$REPO_DIR/main"

    run bash "$SCRIPT" new perf/fft
    [ "$status" -eq 0 ]
    [ -f "$REPO_DIR/cadeb/perf/fft/.git" ]
    [ "$(git -C "$REPO_DIR/cadeb/perf/fft" branch --show-current)" = "cadeb/perf/fft" ]
}

@test "add preserves an existing branch name and nested path" {
    make_repo
    git -C "$REPO_DIR" branch team/review
    cd "$REPO_DIR"
    bash "$SCRIPT" init --print-path >/dev/null
    cd "$REPO_DIR/main"

    run bash "$SCRIPT" add team/review
    [ "$status" -eq 0 ]
    [ -f "$REPO_DIR/team/review/.git" ]
    [ "$(git -C "$REPO_DIR/team/review" branch --show-current)" = "team/review" ]
}

@test "add creates a tracking branch from a fetched remote branch" {
    make_repo
    remote_dir="$TEST_ROOT/remote.git"
    git init -q --bare "$remote_dir"
    git -C "$REPO_DIR" remote add origin "$remote_dir"
    git -C "$REPO_DIR" branch team/review
    git -C "$REPO_DIR" push -q origin main team/review
    git -C "$REPO_DIR" branch -D team/review
    git -C "$REPO_DIR" tag team/review
    ! git -C "$REPO_DIR" show-ref --verify --quiet refs/heads/team/review
    git -C "$REPO_DIR" show-ref --verify --quiet refs/remotes/origin/team/review
    cd "$REPO_DIR"
    bash "$SCRIPT" init --print-path >/dev/null
    cd "$REPO_DIR/main"

    run bash "$SCRIPT" add team/review
    [ "$status" -eq 0 ]
    [ -f "$REPO_DIR/team/review/.git" ]
    [ "$(git -C "$REPO_DIR/team/review" branch --show-current)" = "team/review" ]
    [ "$(git -C "$REPO_DIR/team/review" rev-parse --abbrev-ref '@{upstream}')" = "origin/team/review" ]
}

@test "add follows a nonstandard remote fetch mapping" {
    make_repo
    remote_dir="$TEST_ROOT/remote.git"
    git init -q --bare "$remote_dir"
    git -C "$REPO_DIR" remote add origin "$remote_dir"
    git -C "$REPO_DIR" branch team/mapped
    git -C "$REPO_DIR" push -q origin main team/mapped
    git -C "$REPO_DIR" branch -D team/mapped
    git -C "$REPO_DIR" config --unset-all remote.origin.fetch
    git -C "$REPO_DIR" config --add remote.origin.fetch \
        '+refs/heads/*:refs/remotes/mirror/*'
    while IFS= read -r ref; do
        git -C "$REPO_DIR" update-ref -d "$ref"
    done < <(git -C "$REPO_DIR" for-each-ref --format='%(refname)' refs/remotes/origin)
    git -C "$REPO_DIR" fetch -q origin
    git -C "$REPO_DIR" show-ref --verify --quiet refs/remotes/mirror/team/mapped
    cd "$REPO_DIR"
    bash "$SCRIPT" init --print-path >/dev/null
    cd "$REPO_DIR/main"

    run bash "$SCRIPT" add team/mapped
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO_DIR/team/mapped" branch --show-current)" = "team/mapped" ]
    [ "$(git -C "$REPO_DIR/team/mapped" rev-parse --abbrev-ref '@{upstream}')" = "mirror/team/mapped" ]
}

@test "add uses checkout.defaultRemote when remotes share a branch" {
    make_repo
    origin_dir="$TEST_ROOT/origin.git"
    upstream_dir="$TEST_ROOT/upstream.git"
    git init -q --bare "$origin_dir"
    git init -q --bare "$upstream_dir"
    git -C "$REPO_DIR" remote add origin "$origin_dir"
    git -C "$REPO_DIR" remote add upstream "$upstream_dir"
    git -C "$REPO_DIR" branch team/review
    git -C "$REPO_DIR" push -q origin main team/review
    git -C "$REPO_DIR" push -q upstream main team/review
    git -C "$REPO_DIR" branch -D team/review
    git -C "$REPO_DIR" config checkout.defaultRemote upstream
    cd "$REPO_DIR"
    bash "$SCRIPT" init --print-path >/dev/null
    cd "$REPO_DIR/main"

    run bash "$SCRIPT" add team/review
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO_DIR/team/review" branch --show-current)" = "team/review" ]
    [ "$(git -C "$REPO_DIR/team/review" rev-parse --abbrev-ref '@{upstream}')" = "upstream/team/review" ]
}

@test "add distinguishes a missing branch from new" {
    make_repo
    cd "$REPO_DIR"
    bash "$SCRIPT" init --print-path >/dev/null
    cd "$REPO_DIR/main"

    run bash "$SCRIPT" add missing/topic
    [ "$status" -eq 1 ]
    [[ "$output" == *"branch not found locally or in fetched remotes: missing/topic"* ]]
    [[ "$output" == *"git fetch <remote>"* ]]
    [[ "$output" == *"git wt new"* ]]
    [ ! -e "$REPO_DIR/missing/topic" ]
    run git show-ref --verify --quiet refs/heads/missing/topic
    [ "$status" -ne 0 ]
}

@test "add rejects tags and object IDs instead of detaching HEAD" {
    make_repo
    git -C "$REPO_DIR" tag release/candidate
    object_id="$(git -C "$REPO_DIR" rev-parse --short=12 HEAD)"
    cd "$REPO_DIR"
    bash "$SCRIPT" init --print-path >/dev/null
    cd "$REPO_DIR/main"

    for branch in release/candidate "$object_id"; do
        run bash "$SCRIPT" add "$branch"
        [ "$status" -eq 1 ]
        [[ "$output" == *"branch not found locally or in fetched remotes: $branch"* ]]
        [ ! -e "$REPO_DIR/$branch" ]
        run git show-ref --verify --quiet "refs/heads/$branch"
        [ "$status" -ne 0 ]
    done
}

@test "new reports a missing host identity without guessing" {
    make_repo
    git -C "$REPO_DIR" remote add origin git@example.com:group/project.git
    cd "$REPO_DIR"
    bash "$SCRIPT" init --print-path >/dev/null
    cd "$REPO_DIR/main"

    run bash "$SCRIPT" new topic
    [ "$status" -eq 1 ]
    [[ "$output" == *"no branch namespace configured for example.com"* ]]
    [[ "$output" == *"git config --global gwt.example.com.user <username>"* ]]
}

@test "init rejects a conflicting primary path before mutation" {
    make_repo
    mkdir "$REPO_DIR/main"
    printf 'content\n' > "$REPO_DIR/main/file.txt"
    git -C "$REPO_DIR" add main/file.txt
    git -C "$REPO_DIR" commit -qm conflict

    cd "$REPO_DIR"
    run bash "$SCRIPT" init
    [ "$status" -eq 1 ]
    [[ "$output" == *"primary path conflicts with repository content"* ]]
    [ -d "$REPO_DIR/.git" ]
    [ ! -e "$REPO_DIR/.bare" ]
    [ -f "$REPO_DIR/main/file.txt" ]
}

@test "init rolls back when moving repository content fails" {
    make_repo
    printf 'second\n' > "$REPO_DIR/second.txt"
    mkdir -p "$TEST_ROOT/bin"
    cat > "$TEST_ROOT/bin/mv" <<'EOF'
#!/usr/bin/env bash
count=0
[[ ! -f "$MV_TEST_STATE" ]] || count="$(< "$MV_TEST_STATE")"
count=$((count + 1))
printf '%s\n' "$count" > "$MV_TEST_STATE"
[[ "$count" -ne 3 ]] || exit 1
exec /bin/mv "$@"
EOF
    chmod +x "$TEST_ROOT/bin/mv"

    cd "$REPO_DIR"
    run env PATH="$TEST_ROOT/bin:$PATH" MV_TEST_STATE="$TEST_ROOT/mv-count" \
        bash "$SCRIPT" init
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed while moving"* ]]
    [ -d "$REPO_DIR/.git" ]
    [ ! -e "$REPO_DIR/.bare" ]
    [ -f "$REPO_DIR/tracked.txt" ]
    [ -f "$REPO_DIR/second.txt" ]
    [[ "$(git -C "$REPO_DIR" status --short)" == *"?? second.txt"* ]]
}

@test "incomplete rollback retains worktree data and recovery metadata" {
    make_repo
    printf 'second\n' > "$REPO_DIR/second.txt"
    mkdir -p "$TEST_ROOT/bin"
    cat > "$TEST_ROOT/bin/mv" <<'EOF'
#!/usr/bin/env bash
count=0
[[ ! -f "$MV_TEST_STATE" ]] || count="$(< "$MV_TEST_STATE")"
count=$((count + 1))
printf '%s\n' "$count" > "$MV_TEST_STATE"
[[ "$count" -ne 3 && "$count" -ne 4 ]] || exit 1
exec /bin/mv "$@"
EOF
    chmod +x "$TEST_ROOT/bin/mv"

    cd "$REPO_DIR"
    run env PATH="$TEST_ROOT/bin:$PATH" MV_TEST_STATE="$TEST_ROOT/mv-count" \
        bash "$SCRIPT" init
    [ "$status" -eq 1 ]
    [[ "$output" == *"rollback incomplete; no remaining worktree data was deleted"* ]]
    [ -d "$REPO_DIR/.bare" ]
    [ -f "$REPO_DIR/main/second.txt" ]
    [ -f "$REPO_DIR/tracked.txt" ]
    [ ! -e "$REPO_DIR/.git" ]
    config_backup="$(printf '%s\n' "$output" | sed -n 's/.*original config backup: //p')"
    index_backup="$(printf '%s\n' "$output" | sed -n 's/.*original index backup: //p')"
    [ -f "$config_backup" ]
    [ -f "$index_backup" ]
}

@test "init accepts a deinitialized submodule but refuses an initialized one" {
    CHILD_REPO="$TEST_ROOT/child"
    git init -q -b main "$CHILD_REPO"
    printf 'child\n' > "$CHILD_REPO/file.txt"
    git -C "$CHILD_REPO" add file.txt
    git -C "$CHILD_REPO" commit -qm initial

    make_repo
    git -C "$REPO_DIR" -c protocol.file.allow=always submodule add -q "$CHILD_REPO" sub
    git -C "$REPO_DIR" commit -qm submodule

    cd "$REPO_DIR"
    run bash "$SCRIPT" init
    [ "$status" -eq 1 ]
    [[ "$output" == *"deinitialize submodules before conversion"* ]]
    [ -d "$REPO_DIR/.git" ]

    git submodule deinit -q -f --all
    run bash "$SCRIPT" init --print-path
    [ "$status" -eq 0 ]
    [ -d "$REPO_DIR/.bare" ]
    [ -f "$REPO_DIR/main/.git" ]
}

@test "init rejects overlapping primary and extra worktree paths" {
    make_repo
    git -C "$REPO_DIR" branch team/review

    cd "$REPO_DIR"
    run bash "$SCRIPT" init --path team --add team/review
    [ "$status" -eq 1 ]
    [[ "$output" == *"primary and extra worktree paths overlap"* ]]
    [ -d "$REPO_DIR/.git" ]
    [ ! -e "$REPO_DIR/.bare" ]
}

@test "new rejects a namespace path that crosses a symlink" {
    make_repo
    git -C "$REPO_DIR" remote add origin git@github.com:some-org/project.git
    cd "$REPO_DIR"
    bash "$SCRIPT" init --print-path >/dev/null
    mkdir "$TEST_ROOT/outside"
    ln -s "$TEST_ROOT/outside" "$REPO_DIR/cadebrown"
    cd "$REPO_DIR/main"

    run bash "$SCRIPT" new topic
    [ "$status" -eq 1 ]
    [[ "$output" == *"worktree path crosses a symlink"* ]]
    [ ! -e "$TEST_ROOT/outside/topic" ]
    run git show-ref --verify --quiet refs/heads/cadebrown/topic
    [ "$status" -ne 0 ]
}

@test "new rejects a destination inside the primary worktree" {
    make_repo
    git -C "$REPO_DIR" remote add origin git@github.com:some-org/project.git
    cd "$REPO_DIR"
    bash "$SCRIPT" init --path cadebrown --print-path >/dev/null
    cd "$REPO_DIR/cadebrown"

    run bash "$SCRIPT" new topic
    [ "$status" -eq 1 ]
    [[ "$output" == *"worktree destination is inside an existing worktree"* ]]
    [ ! -e "$REPO_DIR/cadebrown/topic" ]
    run git show-ref --verify --quiet refs/heads/cadebrown/topic
    [ "$status" -ne 0 ]
}

@test "init rejects split index before mutation" {
    make_repo
    git -C "$REPO_DIR" update-index --split-index

    cd "$REPO_DIR"
    run bash "$SCRIPT" init
    [ "$status" -eq 1 ]
    [[ "$output" == *"git update-index --no-split-index"* ]]
    [ -d "$REPO_DIR/.git" ]
    [ ! -e "$REPO_DIR/.bare" ]
    run git status --short
    [ "$status" -eq 0 ]
}
