{{ if eq .chezmoi.os "darwin" -}}
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
{{- else -}}
# LOCPATH must be exported before LANG. Exporting LANG triggers the shell's
# internal setlocale() call, which reads locale data using LOCPATH. If LOCPATH
# isn't set first, brew's glibc finds no locale archive and falls back to
# C/ASCII — wcwidth() then counts bytes instead of display columns, leaving
# remnant characters on screen after tab-completing multi-byte filenames.
# _LOCAL_PLAT is unset in non-login shells (profile never ran); fall back to
# the flat layout default.
export LOCPATH="${_LOCAL_PLAT:-$HOME/.local}/locale"
# LC_ALL is intentionally not set on Linux — the locale archive can't be loaded
# by bash's setlocale(), causing "cannot change locale" warnings on every
# subshell. LANG alone is sufficient and doesn't trigger the warning. But
# sessions from a Mac arrive WITH it set: macOS ships `SendEnv LANG LC_*` in
# /etc/ssh/ssh_config, so both plain ssh AND the VS Code/Cursor Remote-SSH
# server inherit LC_ALL=en_US.UTF-8 — and embedded terminals are NON-LOGIN
# shells, so a profile-only unset never runs there. On hosts whose system
# glibc lacks that locale, setlocale() falls back to C/ASCII and UTF-8 gets
# re-encoded as latin-1 mojibake (â€™, Â ) that rides terminal copy/paste.
# Drop it before LANG's setlocale runs. This partial is included from BOTH
# the login profiles and the interactive rc files for exactly that reason.
# See docs/usage/troubleshooting.md.
unset LC_ALL
export LANG=en_US.UTF-8
{{- end -}}
