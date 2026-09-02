# Git worktrees

`gwt` creates branch-aware Git worktrees in a self-contained repository
directory. It preserves the complete branch hierarchy instead of flattening
slashes.

```text
~/dev/project/
├── .bare/
├── main/
└── cadeb/
    └── perf/
        └── fft/
```

In this example the last worktree checks out `cadeb/perf/fft`. Git stores the
shared repository data in `.bare`; each leaf directory is an ordinary working
tree.

The implementation is a Bash script installed as `git-wt` in the active
`~/.local` or PLAT-specific `bin` directory. Git discovers it as the external
subcommand `git wt`. The shell function `gwt` invokes the same command and
enters worktrees created by `gwt new`.

After installing or updating the dotfiles, open a new shell so `gwt` and the
interactive `gwtize` wrapper are loaded. `git wt` itself works as soon as the
script is installed.

The links between worktrees and `.bare` remain absolute. Relative worktree
metadata would make the container relocatable, but it creates a repository
extension that the system Git 2.43 on current Linux hosts cannot read.

## Convert a clone

Start at the root of a normal clone:

```sh
cd ~/dev/project
gwtize
```

`gwtize` is the interactive wrapper for `git wt init`. It converts `.git` to
`.bare`, creates a worktree whose path matches the current branch, preserves
staged, unstaged, and untracked files, and enters the new worktree.

Use an explicit primary path or add existing branches during conversion when
needed:

```sh
git wt init --path work --add release/13.5
```

`--path` changes only the primary directory name; it does not rename the
checked-out branch. The default path mirrors the branch and is preferred.

Conversion stops before changing the repository when it finds an active merge,
rebase, cherry-pick, revert, or bisect; sparse checkout; initialized submodules;
split index; existing linked worktrees; overlapping worktree paths; or a
filesystem path that conflicts with the primary worktree. Resolve that state
and rerun the command. Disable split index with
`git update-index --no-split-index`.

## Create a personal branch

```sh
gwt new perf/fft develop
```

`new` selects the configured username from the push remote's host, creates the
branch from the optional start point, uses the complete branch name as the
path, and enters the new worktree. The same logical command produces:

```text
remote       branch                    path
GitHub       cadebrown/perf/fft         ~/dev/project/cadebrown/perf/fft
NVIDIA       cadeb/perf/fft             ~/dev/project/cadeb/perf/fft
start point  develop
```

The start point defaults to `HEAD`:

```sh
gwt new docs/worktrees
```

Use `git wt new` instead when a script should stay in its current directory;
it prints the new worktree path on standard output.

Passing an already qualified name does not duplicate the prefix:

```sh
gwt new cadeb/perf/fft
```

## Add an existing branch

`add` never changes a branch name. Use it for shared branches, base branches,
or a branch that already has the correct namespace:

```sh
gwt add main
gwt add release/13.5
gwt add cadeb/perf/fft
```

The branch must already exist locally. Use `gwt new` when creating a personal
branch.

## Forge usernames

The remote repository owner is not necessarily your forge identity, so `gwt`
uses the push remote only to select a host. The Git config maps that host to an
explicit branch namespace:

```gitconfig
[gwt "github.com"]
    user = cadebrown

[gwt "gitlab-master.nvidia.com"]
    user = cadeb
```

Add another forge without changing the script:

```sh
git config --global gwt.example.com.user my-username
```

If the selected host has no mapping, `gwt new` stops without creating a branch
or directory and prints the corresponding `git config --global` command.

For a checked-out branch, remote selection follows `branch.<name>.pushRemote`,
`remote.pushDefault`, and `branch.<name>.remote`, then falls back to `origin` or
the repository's only remote.

## Other worktree operations

The remaining commands delegate to Git and keep their native arguments:

```sh
gwt list
gwt lock ../offline-worktree
gwt move ../old-path ../new-path
gwt remove ../finished-worktree
gwt repair
gwt prune --dry-run
```

Use `git worktree` directly for an operation that intentionally bypasses the
branch and path policy.

## Help

```sh
gwt help
gwt help new
gwt help add
gwt help init
```

The equivalent forms `gwt --help`, `git-wt --help`, and
`git wt <command> --help` work in any shell. Git reserves `git wt --help` for
manual-page lookup, so use `git wt help` for the top-level menu.
