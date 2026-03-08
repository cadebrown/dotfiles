{ config, pkgs, lib, ... }:

{
  home.username = builtins.getEnv "USER";
  home.homeDirectory = builtins.getEnv "HOME";
  home.stateVersion = "24.11";

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    # Shell
    zsh
    zoxide
    fzf
    direnv

    # Git
    git
    git-lfs
    delta
    difftastic

    # Search & Files
    ripgrep
    fd
    bat
    bat-extras.batdiff
    bat-extras.batgrep
    bat-extras.batman
    bat-extras.batwatch
    tree
    sd
    ncdu
    ast-grep

    # JSON & Data
    jq

    # Media
    mpv
    imagemagick

    # CLI utilities
    wget
    curl
    less
    rlwrap
    cloc
    fastfetch
    lynx

    # Monitoring
    htop
    btop
    bottom
    glances

    # Editors
    neovim

    # Build
    fftw
    jdk

    # Containers (CLI tools only — daemon/service managed separately)
    docker-client
    podman
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    # Linux-only: qemu (macOS uses UTM/Homebrew)
    qemu
  ];

  programs.zsh = {
    enable = false;  # managed by chezmoi
  };

  programs.git = {
    enable = false;  # managed by chezmoi
  };
}
