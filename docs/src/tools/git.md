# Git

Git config lives in `~/.gitconfig`, managed by chezmoi as `home/dot_gitconfig.tmpl`. Name and email are templated from per-machine chezmoi data.

## Notable settings

**Delta** is used as the pager for all diff output — side-by-side diffs with line numbers and syntax highlighting:

```
[core]
    pager = delta
[interactive]
    diffFilter = delta --color-only
[delta]
    navigate = true
    dark = true
    side-by-side = true
```

**Histogram diff** produces cleaner diffs than the default Myers algorithm, especially for refactored code:

```
[diff]
    algorithm = histogram
```

**Rebase workflow** is the default — `git pull` rebases instead of merging, and `autoSquash` + `autoStash` make interactive rebases smoother:

```
[pull]
    rebase = true
    ff = only
[rebase]
    autoSquash = true
    autoStash = true
```

**rerere** (reuse recorded resolution) remembers how merge conflicts were resolved and replays the resolution automatically next time:

```
[rerere]
    enabled = true
```

## Aliases

```sh
git lg        # pretty graph log, last 15 commits
git zip       # archive HEAD as latest.zip
git praise    # alias for blame (positivity FTW)
```

## Global gitignore

`~/.config/git/ignore` covers common noise across all repos: `.DS_Store`, editor swap files (`.swp`, `.idea/`, `.vscode/`), build artifacts (`*.o`, `*.so`), and secret files (`.env`).
