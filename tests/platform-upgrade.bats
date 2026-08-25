#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "platform upgrade scripts parse" {
    bash -n "$REPO/bootstrap.sh"
    bash -n "$REPO/install/rust.sh"
    bash -n "$REPO/install/latex.sh"
    bash -n "$REPO/install/homebrew.sh"
}

@test "macOS rustup comes from the declared Homebrew prefix" {
    grep -Eq '^[[:space:]]*brew "rustup"' "$REPO/packages/Brewfile"
    grep -q 'brew --prefix rustup' "$REPO/install/rust.sh"
    ! grep -q 'RUSTUP_.*="/opt/homebrew' "$REPO/install/rust.sh"
}

@test "macOS rustup supports Homebrew's keg-only layout without rustup-init" {
    local prefix="$BATS_TEST_TMPDIR/rustup-prefix"
    local cargo_home="$BATS_TEST_TMPDIR/cargo-home"
    mkdir -p "$prefix/bin" "$cargo_home/bin"
    touch "$prefix/bin/rustup" "$prefix/bin/rustc" "$prefix/bin/cargo"
    chmod +x "$prefix/bin/rustup" "$prefix/bin/rustc" "$prefix/bin/cargo"

    run bash -c '
        source "$1/install/rust.sh"
        CARGO_HOME="$3"
        _link_homebrew_rustup_proxies "$2"
        test "$(readlink "$CARGO_HOME/bin/rustup")" = "$2/bin/rustup"
        test "$(readlink "$CARGO_HOME/bin/rustc")" = "$2/bin/rustc"
        test "$(readlink "$CARGO_HOME/bin/cargo")" = "$2/bin/cargo"
    ' _ "$REPO" "$prefix" "$cargo_home"

    [ "$status" -eq 0 ]
}

@test "TinyTeX compiled state is rooted under LOCAL_PLAT" {
    grep -q '_tinytex_parent="\$LOCAL_PLAT/tex"' "$REPO/install/latex.sh"
    grep -q 'TINYTEX_DIR="\$_tinytex_parent"' "$REPO/install/latex.sh"
    grep -q 'sys_bin "\$ARCH_BIN"' "$REPO/install/latex.sh"
}

@test "Homebrew only upgrades existing packages in explicit upgrade mode" {
    grep -q '_brew_upgrade="${DF_BREW_UPGRADE:-0}"' "$REPO/install/homebrew.sh"
    grep -q 'DF_BREW_UPGRADE="${DF_BREW_UPGRADE:-1}"' "$REPO/bootstrap.sh"
    grep -q '^export DF_BREW_UPGRADE$' "$REPO/bootstrap.sh"
    grep -q 'brew bundle install --no-upgrade' "$REPO/install/homebrew.sh"
    grep -q 'brew upgrade --formula --yes' "$REPO/install/homebrew.sh"
}

@test "Homebrew download concurrency is bounded and configurable" {
    grep -q 'HOMEBREW_DOWNLOAD_CONCURRENCY="${DF_BREW_DOWNLOAD_CONCURRENCY:-4}"' \
        "$REPO/install/homebrew.sh"
}

@test "Homebrew bundle package jobs are serialized" {
    grep -q '^export HOMEBREW_BUNDLE_NO_JOBS=1$' "$REPO/install/_lib.sh"
}

@test "Linux Homebrew disables automatic cleanup for NFS prefixes" {
    run env LC_ALL=C LANG=C bash -c '
        source "$1/install/linux-packages.sh"
        stat() { printf "%s\n" nfs; }
        unset HOMEBREW_NO_INSTALL_CLEANUP
        _configure_brew_cleanup "$2"
        printf "%s\n" "${HOMEBREW_NO_INSTALL_CLEANUP:-}"
    ' _ "$REPO" "$BATS_TEST_TMPDIR"

    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "Linux Homebrew keeps automatic cleanup for local prefixes" {
    run env LC_ALL=C LANG=C bash -c '
        source "$1/install/linux-packages.sh"
        stat() { printf "%s\n" ext2; }
        unset HOMEBREW_NO_INSTALL_CLEANUP
        _configure_brew_cleanup "$2"
        test -z "${HOMEBREW_NO_INSTALL_CLEANUP:-}"
    ' _ "$REPO" "$BATS_TEST_TMPDIR"

    [ "$status" -eq 0 ]
}

@test "Ruby formula patch puts the new keg before the previous Ruby RPATH" {
    local fake_home="$BATS_TEST_TMPDIR/ruby-patch-home"
    local formula="$fake_home/.local/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/r/ruby.rb"
    mkdir -p "$(dirname "$formula")"
    cat >"$formula" <<'RUBY'
class Ruby < Formula
  def install
    paths = %w[libyaml openssl@3].map { |f| formula_opt_prefix(f) }
    # Add versioned Ruby RPATH so user-installed gems can work when user is switched to versioned Ruby
    paths << versioned_opt_prefix if OS.linux? && !versioned_formula?

    if build.stable?
      resource("rubygems").stage do
        ENV.prepend_path "PATH", bin

        mkdir_p HOMEBREW_PREFIX/"lib/ruby/gems/#{api_version}"
        system bin/"ruby", "setup.rb", "--prefix=#{buildpath}/vendor_gem"
      end
    end
  end
end
RUBY

    run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-ruby.sh"

    [ "$status" -eq 0 ]
    grep -Fq 'ENV.prepend "LDFLAGS", "-Wl,-rpath,#{lib}" if OS.linux?' "$formula"
    run grep -F 'mkdir_p HOMEBREW_PREFIX/' "$formula"
    [ "$status" -eq 1 ]

    run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-ruby.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"already applied"* ]]
    [ "$(grep -Fc 'ENV.prepend "LDFLAGS"' "$formula")" -eq 1 ]
}

@test "OpenSSH formula patch accepts an already-normalized sshd_config" {
    local fake_home="$BATS_TEST_TMPDIR/openssh-patch-home"
    local formula="$fake_home/.local/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/o/openssh.rb"
    mkdir -p "$(dirname "$formula")"
    cat >"$formula" <<'RUBY'
class Openssh < Formula
  def install
    # Don't hardcode Cellar paths in configuration files
    inreplace etc/"ssh/sshd_config", prefix, opt_prefix
  end
end
RUBY

    run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-openssh.sh"

    [ "$status" -eq 0 ]
    grep -Fq 'sshd_config = etc/"ssh/sshd_config"' "$formula"
    grep -Fq 'if sshd_config.read.include?(prefix.to_s)' "$formula"

    run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-openssh.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"already applied"* ]]
    [ "$(grep -Fc 'sshd_config = etc/' "$formula")" -eq 1 ]
}

@test "unattended cask upgrades require cached sudo" {
    grep -q 'DF_BREW_UPGRADE_CASKS:-auto' "$REPO/install/homebrew.sh"
    grep -q 'sudo -n true' "$REPO/install/homebrew.sh"
    ! grep -q 'log_warn "Cask upgrades' "$REPO/install/homebrew.sh"
}

@test "Python optional arguments are safe under macOS system Bash nounset" {
    grep -q '_uv_cmd=(uv tool install "$_pkg")' "$REPO/install/python.sh"
    ! grep -q '"${_uv_args\[@\]}"' "$REPO/install/python.sh"
}

@test "Rust optional flags are safe under macOS system Bash nounset" {
    grep -q '_rustup_cmd=("\$RUSTUP_BIN" update stable)' "$REPO/install/rust.sh"
    grep -q '_rustup_cmd=("\$CARGO_HOME/bin/rustup" update stable)' "$REPO/install/rust.sh"
    ! grep -Eq '"\$\{(_rustup_flags|_install_force)\[@\]\}"' "$REPO/install/rust.sh"
}

@test "upgrade ends with a strict managed-toolchain audit" {
    grep -q 'audit-versions.sh" --strict' "$REPO/bootstrap.sh"
    grep -q 'DF_STRICT_UPGRADE:-1' "$REPO/bootstrap.sh"
}
