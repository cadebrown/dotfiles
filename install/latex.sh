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
    _texbin=/Library/TeX/texbin
    if [[ ! -x "$_texbin/pdflatex" ]]; then
        log_warn "MacTeX not found — installed via Brewfile (cask \"mactex\"); run homebrew.sh"
        exit 0
    fi
    log_okay "MacTeX present: $("$_texbin/pdflatex" --version 2>/dev/null | head -1)"

    if [[ "${DF_MODE:-}" == "upgrade" ]]; then
        # The cask only moves on yearly MacTeX releases, so package-level updates
        # have to come from tlmgr, which writes root-owned /usr/local/texlive.
        # Skip rather than block bootstrap on a password prompt.
        if sudo -n true 2>/dev/null; then
            log_info "Updating TeX Live packages (tlmgr)"
            run_logged sudo -n "$_texbin/tlmgr" update --self --all || log_warn "tlmgr update failed"
        else
            log_warn "No sudo ticket — skipping tlmgr. Run: sudo tlmgr update --self --all"
        fi
    fi
    exit 0
fi

# --- Linux: TinyTeX ---

_tinytex_parent="$LOCAL_PLAT/tex"
_tinytex_root="$_tinytex_parent/.TinyTeX"
_tlmgr_glob=("$_tinytex_root"/bin/*/tlmgr)

if [[ -x "${_tlmgr_glob[0]:-}" ]]; then
    log_okay "TinyTeX already installed: $_tinytex_root"
else
    log_info "Installing TinyTeX → $_tinytex_root"
    ensure_dir "$_tinytex_parent"
    _tinytex_installer="$(mktemp)"
    download https://yihui.org/tinytex/install-bin-unix.sh "$_tinytex_installer"
    run_logged env TINYTEX_DIR="$_tinytex_parent" sh "$_tinytex_installer" "" --no-path
    rm -f "$_tinytex_installer"
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

if [[ "${DF_MODE:-}" == "upgrade" ]]; then
    log_info "Updating TeX Live packages (tlmgr)"
    run_logged "$_tlmgr" update --self --all || log_warn "tlmgr update failed"
fi

log_okay "TeX ready: $("$ARCH_BIN/pdflatex" --version 2>/dev/null | head -1 || echo 'pdflatex pending shell restart')"
