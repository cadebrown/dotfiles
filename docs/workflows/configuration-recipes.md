---
title: Configuration recipes
description: Small, reversible recipes for profiles, optional stages, source changes, and diagnosis.
---

## Choose a setup profile

Use a `core` profile for a narrower command-line setup and defer optional
features by gate. Preserve the command and its output with a machine record so
the resulting state is explainable.

```bash
cd ~/dotfiles
DF_PROFILE=core \
DF_DO_AUTH=0 \
DF_DO_LOCAL_LLM=0 \
DF_DO_MACOS_SERVICES=0 \
./bootstrap.sh
```

The authoritative gate list is the header of
[`bootstrap.sh`](https://github.com/cadebrown/dotfiles/blob/main/bootstrap.sh#L38).
Skipping a stage leaves it unreconciled; tools from earlier runs may still be
installed. Final verification skips the corresponding check too. A disabled
gate is not an uninstall operation.

## Change a managed shell setting

Edit the chezmoi source, inspect the deployment, apply it, then test in a new
login shell:

```bash
"${EDITOR:-vi}" ~/dotfiles/home/dot_zshrc.tmpl
chezmoi diff
chezmoi apply
exec zsh -l
```

This edits the authoritative source before deployment. `chezmoi edit ~/.zshrc`
edits only the source; add `--apply` to deploy after the editor exits. The rendered target is
useful for observation but is not the source of truth. See
[chezmoi setup](/setup/chezmoi/).

## Diagnose runtime resolution

```bash
printf 'DF_USE_PLAT=%s\n' "${DF_USE_PLAT:-unset}"
printf 'LOCAL=%s\n' "${_LOCAL_PLAT:-unset}"
command -v node npm python cargo lean
bash ~/dotfiles/install/verify-path.sh
bash ~/dotfiles/install/verify-tools.sh
```

Use `verify-path.sh` for ordering and stale-symlink problems; use
`verify-tools.sh` for selected runtime postconditions. If a bootstrap run
reports degradations, repair the named component before assuming unrelated
commands are healthy. The [troubleshooting guide](/usage/troubleshooting/)
contains established symptom-to-cause procedures.
