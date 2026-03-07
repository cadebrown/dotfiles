{ config, pkgs, lib, ... }:

let
  # Detect architecture
  isAarch64 = pkgs.stdenv.isAarch64;
in
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
    tree
    sd
    ncdu

    # JSON & Data
    jq

    # CLI utilities
    wget
    curl
    less
    rlwrap
    cloc
    imagemagick
    fastfetch

    # Monitoring
    htop
    btop

    # Editors
    neovim

    # Rust toolchain (via rustup, not nix)
    # rustup

    # Node (via mise, not nix)
    # nodejs

    # Python (via mise, not nix)
    # python3
  ];

  programs.zsh = {
    enable = false;  # managed by chezmoi
  };

  programs.git = {
    enable = false;  # managed by chezmoi
  };
}
