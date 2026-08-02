#!/usr/bin/env bash
# install/latex.sh - TeX distribution: MacTeX on macOS (Brewfile cask), TinyTeX on Linux
#
# macOS gets full MacTeX via `cask "mactex"` in the Brewfile — this script only
# verifies it. Linux (no sudo) gets TinyTeX: user-prefix TeX Live with per-user
# tlmgr, ~200 MB base instead of multi-GB, identical engine to what arXiv runs.
# Missing packages install on demand: `tlmgr install <pkg>`.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "TeX distribution"

if [[ "$OS" == "darwin" ]]; then
    if [[ -x /Library/TeX/texbin/pdflatex ]]; then
        log_okay "MacTeX present: $(/Library/TeX/texbin/pdflatex --version 2>/dev/null | head -1)"
    else
        log_warn "MacTeX not found — installed via Brewfile (cask \"mactex\"); run homebrew.sh"
    fi
    exit 0
fi

# --- Linux: TinyTeX ---

_tinytex_root="$HOME/.TinyTeX"
_tlmgr_glob=("$_tinytex_root"/bin/*/tlmgr)

if [[ -x "${_tlmgr_glob[0]:-}" ]]; then
    log_okay "TinyTeX already installed: $_tinytex_root"
else
    log_info "Installing TinyTeX → $_tinytex_root"
    run_logged sh -c "curl -sL https://yihui.org/tinytex/install-bin-unix.sh | sh"
    _tlmgr_glob=("$_tinytex_root"/bin/*/tlmgr)
    [[ -x "${_tlmgr_glob[0]:-}" ]] || die "TinyTeX install failed (no tlmgr under $_tinytex_root/bin)"
fi

_tlmgr="${_tlmgr_glob[0]}"

# Symlink binaries into ARCH_BIN (already on PATH) instead of TinyTeX's default
# ~/.local/bin assumption — keeps the PLAT layout invariant.
run_logged "$_tlmgr" option sys_bin "$ARCH_BIN"
run_logged "$_tlmgr" path add

# Paper-writing baseline beyond scheme-infraonly; everything else on demand.
log_info "Installing base packages (latexmk chktex texcount latexdiff)"
run_logged "$_tlmgr" install latexmk chktex texcount latexdiff || log_warn "tlmgr install failed for some packages — retry manually"

log_okay "TeX ready: $("$ARCH_BIN/pdflatex" --version 2>/dev/null | head -1 || echo 'pdflatex pending shell restart')"
