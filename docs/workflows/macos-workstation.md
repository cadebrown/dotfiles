---
title: macOS services, windows, and media
description: The managed macOS boundary for local services, window management, and creative tools.
---

## Installed is separate from started

The macOS service installer wires Docker CLI plugins and does not enable local
service auto-start by default. Colima, Ollama, and mlxserve can be registered
only with an explicit policy; an already registered Homebrew service is retained.
The reason is operational: a login service can reserve substantial local
resources when no project needs it. Enable the explicit policy only when that
is desired:

```bash
DF_START_LOCAL_SERVICES=1 ./bootstrap.sh

# Otherwise start a service only for the work that needs it.
colima start
ollama serve
mlxserve
```

This default and the manual control paths are defined in
[`macos-services.sh`](https://github.com/cadebrown/dotfiles/blob/main/install/macos-services.sh#L2).
The bootstrap still verifies selected local-LLM executables; it does not make a
model request or prove a service is listening
([source](https://github.com/cadebrown/dotfiles/blob/main/install/verify-tools.sh#L118)).

## Window and media tools

The Brewfile declares AeroSpace, Ghostty, media players, image tools, Blender,
Kdenlive, and other macOS applications as managed packages or casks
([source](https://github.com/cadebrown/dotfiles/blob/main/packages/Brewfile#L256)).
Their actual configuration and macOS accessibility or screen-recording grants
remain host state. A package being present does not confer those permissions.

For a window-management change, edit the managed AeroSpace source, apply it,
then reload or use the application’s own diagnostic command. The operational
keymap and workspace conventions live in [AeroSpace usage](/usage/aerospace/).
For visual production, use [creative workflows](/usage/creative-workflows/) and
validate assets by opening or rendering them in their target application.

## A bounded service check

```bash
brew services list
colima status
curl --noproxy '*' --max-time 5 http://127.0.0.1:11434/api/tags
```

The last probe is meaningful only after intentionally starting Ollama. Treat an
unavailable local endpoint as a service-state observation, not an installation
failure, unless the selected workflow requires it.
