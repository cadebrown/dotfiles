#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "platform upgrade scripts parse" {
    bash -n "$REPO/bootstrap.sh"
    bash -n "$REPO/install/rust.sh"
    bash -n "$REPO/install/latex.sh"
    bash -n "$REPO/install/homebrew.sh"
    bash -n "$REPO/install/linux-packages.sh"
    bash -n "$REPO/install/patch-homebrew-superenv.sh"
    bash -n "$REPO/install/patch-homebrew-stdenv.sh"
    bash -n "$REPO/install/patch-homebrew-ncurses.sh"
    bash -n "$REPO/install/patch-homebrew-cc65.sh"
    bash -n "$REPO/install/patch-homebrew-m4.sh"
    bash -n "$REPO/install/patch-homebrew-pkgconf.sh"
    bash -n "$REPO/install/patch-homebrew-ruby.sh"
    bash -n "$REPO/install/patch-homebrew-apache-serf.sh"
    bash -n "$REPO/install/patch-homebrew-gecode.sh"
}

@test "Homebrew activation works when brew was absent from the original PATH" {
    fake_bin="$BATS_TEST_TMPDIR/fresh-brew/bin"
    mkdir -p "$fake_bin"
    printf '%s\n' '#!/bin/sh' \
        'if [ "$1" = shellenv ]; then' \
        "  printf 'export PATH=%s:\\$PATH\\n' '$fake_bin'" \
        'fi' > "$fake_bin/brew"
    chmod +x "$fake_bin/brew"

    run env PATH="/usr/bin:/bin" DF_HOMEBREW_BIN="$fake_bin/brew" REPO="$REPO" bash -c '
        source "$REPO/install/_lib.sh"
        activate_homebrew
        command -v brew
    '

    [ "$status" -eq 0 ]
    [ "$output" = "$fake_bin/brew" ]
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

@test "macOS Homebrew requires the Brewfile to be fully satisfied" {
    grep -q 'brew bundle check --no-upgrade --file="\$BREWFILE"' \
        "$REPO/install/homebrew.sh"
    ! grep -q 'Some Brewfile packages failed' "$REPO/install/homebrew.sh"
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

@test "Linux Homebrew environment patches follow the installed header opt keg" {
    local fake_home="$BATS_TEST_TMPDIR/brew-env-patch-home"
    local env_dir="$fake_home/.local/brew/Homebrew/Library/Homebrew/extend/os/linux/extend/ENV"
    local super_rb="$env_dir/super.rb"
    local std_rb="$env_dir/std.rb"
    mkdir -p "$env_dir"

    cat >"$super_rb" <<'RUBY'
module OS
  module Linux
    module Superenv
      def setup_build_environment(formula: nil)
        self["HOMEBREW_OPTIMIZATION_LEVEL"] = "O2"
        self["HOMEBREW_RPATH_PATHS"] = determine_rpath_paths(formula).to_s
        return unless ::Hardware::CPU.arm64?
      end

      def homebrew_extra_isystem_paths
        paths = []
        paths
      end
    end
  end
end
RUBY

    cat >"$std_rb" <<'RUBY'
module OS
  module Linux
    module Stdenv
      def setup_build_environment(formula: nil)
        prepend_path "CPATH", HOMEBREW_PREFIX/"include"
        prepend_path "LIBRARY_PATH", HOMEBREW_PREFIX/"lib"
        prepend_path "LD_RUN_PATH", HOMEBREW_PREFIX/"lib"
        return unless formula
      end
    end
  end
end
RUBY

    run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C bash "$REPO/install/patch-homebrew-superenv.sh"
    [ "$status" -eq 0 ]
    run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C bash "$REPO/install/patch-homebrew-stdenv.sh"
    [ "$status" -eq 0 ]

    grep -Fq 'paths << linux_headers.opt_include if linux_headers' "$super_rb"
    grep -Fq 'prepend_path "CPATH", linux_headers.opt_include if linux_headers' "$std_rb"
    [ "$(grep -Fc 'self["ac_cv_c_undeclared_builtin_options"]' "$super_rb")" -eq 1 ]
    [ "$(grep -Fc 'self["ac_cv_c_undeclared_builtin_options"]' "$std_rb")" -eq 1 ]
    ! grep -Fq 'linux_headers.include if linux_headers' "$super_rb"
    ! grep -Fq 'linux_headers.include if linux_headers' "$std_rb"

    run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C bash "$REPO/install/patch-homebrew-superenv.sh"
    [ "$status" -eq 0 ]
    run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C bash "$REPO/install/patch-homebrew-stdenv.sh"
    [ "$status" -eq 0 ]
    [ "$(grep -Fc 'linux_headers.opt_include if linux_headers' "$super_rb")" -eq 1 ]
    [ "$(grep -Fc 'linux_headers.opt_include if linux_headers' "$std_rb")" -eq 1 ]
}

@test "Linux formula patches emit stable linux-headers opt paths" {
    local script
    for script in ncurses cc65 m4 pkgconf; do
        grep -Fq 'ENV.prepend_path "CPATH", Formula["linux-headers@6.8"].opt_include.to_s' "$REPO/install/patch-homebrew-$script.sh"
    done
}

@test "Linux formula patches migrate header paths from formula versions to opt kegs" {
    local fake_home="$BATS_TEST_TMPDIR/brew-formula-header-migration-home"
    local spec script formula
    local -a specs=(
        "ncurses:n/ncurses.rb"
        "cc65:c/cc65.rb"
        "m4:m/m4.rb"
        "pkgconf:p/pkgconf.rb"
    )

    for spec in "${specs[@]}"; do
        script="${spec%%:*}"
        formula="$fake_home/.local/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/${spec#*:}"
        mkdir -p "$(dirname "$formula")"
        case "$script" in
            ncurses)
                cat >"$formula" <<'RUBY'
class Fixture < Formula
  def install
    ENV.delete("TERMINFO")
    on_linux do
      # linux-headers@6.8 provides asm/ioctls.h, linux/limits.h, linux/errno.h,
      # etc. Homebrew glibc requires these kernel headers transitively, but ncurses
      # does not declare the dependency. Using CPATH (not CPPFLAGS) because ncurses
      # subdirectory Makefiles use $(CC) $(CFLAGS) without $(CPPFLAGS) — GCC always
      # checks CPATH regardless of the Makefile.
      ENV.prepend_path "CPATH", Formula["linux-headers@6.8"].include.to_s
    end

    args = []
  end
end
RUBY
                ;;
            cc65)
                cat >"$formula" <<'RUBY'
class Fixture < Formula
  def install
    on_linux do
      # linux-headers@6.8 provides linux/errno.h, which Homebrew glibc requires
      # but cc65 does not declare as a dependency. Without this, the source build
      # fails with: fatal error: linux/errno.h: No such file or directory
      # Using CPATH (not CPPFLAGS) because the cc65 Makefile uses $(CC) $(CFLAGS)
      # without $(CPPFLAGS). GCC always checks CPATH regardless of the Makefile.
      ENV.prepend_path "CPATH", Formula["linux-headers@6.8"].include.to_s
    end
    system "make", "PREFIX=#{prefix}"
    system "make", "install", "PREFIX=#{prefix}"
  end
end
RUBY
                ;;
            m4)
                cat >"$formula" <<'RUBY'
class Fixture < Formula
  def install
    on_linux do
      # m4 1.4.21 bundled gnulib has a broken probe for undeclared builtins:
      # GCC treats memcpy/strchr as compiler builtins, so the test program
      # compiles silently and configure aborts with "cannot detect". Pre-set
      # the autoconf cache variable to skip the probe (standard AC mechanism).
      # Remove when m4 upgrades to a version with the fixed gnulib.
      ENV["ac_cv_c_undeclared_builtin_options"] = \
        "-Wimplicit-function-declaration -Werror=implicit-function-declaration"
      # linux-headers@6.8 provides asm/ioctls.h, linux/limits.h, linux/errno.h,
      # etc. Homebrew glibc requires these kernel headers transitively, but m4
      # does not declare the dependency. Using CPATH (not CPPFLAGS) because m4
      # gnulib subdirectory Makefiles do not propagate $(CPPFLAGS) to compile
      # rules. GCC always checks CPATH regardless of Makefile structure.
      ENV.prepend_path "CPATH", Formula["linux-headers@6.8"].include.to_s
    end
    system "./configure", "--disable-dependency-tracking", "--prefix=#{prefix}"
  end
end
RUBY
                ;;
            pkgconf)
                cat >"$formula" <<'RUBY'
class Fixture < Formula
  def install
    on_linux do
      ENV["ac_cv_c_undeclared_builtin_options"] = \
        "-Wimplicit-function-declaration -Werror=implicit-function-declaration"
      ENV.prepend_path "CPATH", Formula["linux-headers@6.8"].include.to_s
    end
  end
end
RUBY
                ;;
        esac

        run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
            bash "$REPO/install/patch-homebrew-$script.sh"
        [ "$status" -eq 0 ]
        grep -Fq 'Formula["linux-headers@6.8"].opt_include.to_s' "$formula"
        ! grep -Fq 'Formula["linux-headers@6.8"].include.to_s' "$formula"

        run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
            bash "$REPO/install/patch-homebrew-$script.sh"
        [ "$status" -eq 0 ]
        [[ "$output" == *"already applied"* ]]
        [ "$(grep -Fc 'Formula["linux-headers@6.8"].opt_include.to_s' "$formula")" -eq 1 ]
    done
}

@test "Linux Homebrew environment patches fail closed when upstream anchors move" {
    local fake_home="$BATS_TEST_TMPDIR/brew-env-rotted-anchor-home"
    local env_dir="$fake_home/.local/brew/Homebrew/Library/Homebrew/extend/os/linux/extend/ENV"
    mkdir -p "$env_dir"
    printf '%s\n' 'module ChangedSuperenv; end' >"$env_dir/super.rb"
    printf '%s\n' 'module ChangedStdenv; end' >"$env_dir/std.rb"

    run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C bash "$REPO/install/patch-homebrew-superenv.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing to start source builds"* ]]

    run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C bash "$REPO/install/patch-homebrew-stdenv.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing to start source builds"* ]]

    local missing_home="$BATS_TEST_TMPDIR/brew-env-missing-files-home"
    mkdir -p "$missing_home/.local"
    run env HOME="$missing_home" DF_USE_PLAT=0 LC_ALL=C LANG=C bash "$REPO/install/patch-homebrew-superenv.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing to start source builds"* ]]

    run env HOME="$missing_home" DF_USE_PLAT=0 LC_ALL=C LANG=C bash "$REPO/install/patch-homebrew-stdenv.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing to start source builds"* ]]
}

@test "apache-serf formula passes kernel headers through SCons CPPFLAGS" {
    grep -Fq 'patch-homebrew-apache-serf.sh' "$REPO/install/linux-packages.sh"

    local fake_home="$BATS_TEST_TMPDIR/apache-serf-patch-home"
    local formula="$fake_home/.local/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/a/apache-serf.rb"
    mkdir -p "$(dirname "$formula")"
    cat >"$formula" <<'RUBY'
class ApacheSerf < Formula
  on_linux do
    depends_on "zlib-ng-compat"
  end

  def install
    args = %W[
      APR=#{Formula["apr"].opt_prefix}
      CC=#{ENV.cc}
      CFLAGS=#{ENV.cflags}
      LINKFLAGS=#{ENV.ldflags}
    ]
    args << "ZLIB=#{formula_opt_prefix("zlib-ng-compat")}" if OS.linux?
    system "scons", *args
    system "scons", "install"
  end
end
RUBY

    run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-apache-serf.sh"

    [ "$status" -eq 0 ]
    local expected='args << "CPPFLAGS=#{ENV.cppflags} -isystem#{Formula["linux-headers@6.8"].opt_include}" if OS.linux?'
    grep -Fq "$expected" "$formula"
    grep -Fq 'depends_on "linux-headers@6.8" => :build' "$formula"
    local zlib_line cppflags_line scons_line
    zlib_line=$(grep -nF 'args << "ZLIB=' "$formula" | cut -d: -f1)
    cppflags_line=$(grep -nF "$expected" "$formula" | cut -d: -f1)
    scons_line=$(grep -nF 'system "scons", *args' "$formula" | cut -d: -f1)
    [ "$zlib_line" -lt "$cppflags_line" ]
    [ "$cppflags_line" -lt "$scons_line" ]

    run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-apache-serf.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"already applied"* ]]
    [ "$(grep -Fc "$expected" "$formula")" -eq 1 ]
    [ "$(grep -Fc 'depends_on "linux-headers@6.8" => :build' "$formula")" -eq 1 ]

    local legacy_home="$BATS_TEST_TMPDIR/apache-serf-legacy-patch-home"
    formula="$legacy_home/.local/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/a/apache-serf.rb"
    mkdir -p "$(dirname "$formula")"
    cat >"$formula" <<'RUBY'
class ApacheSerf < Formula
  on_linux do
    depends_on "linux-headers@6.8" => :build
    depends_on "zlib-ng-compat"
  end

  def install
    args = []
    args << "ZLIB=#{formula_opt_prefix("zlib-ng-compat")}" if OS.linux?
    args << "CPPFLAGS=#{ENV.cppflags} -isystem#{Formula["linux-headers@6.8"].include}" if OS.linux?
    system "scons", *args
  end
end
RUBY

    run env HOME="$legacy_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-apache-serf.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"installed opt keg"* ]]
    grep -Fq "$expected" "$formula"
    ! grep -Fq 'Formula["linux-headers@6.8"].include' "$formula"

    local rotted_home="$BATS_TEST_TMPDIR/apache-serf-rotted-anchor-home"
    formula="$rotted_home/.local/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/a/apache-serf.rb"
    mkdir -p "$(dirname "$formula")"
    cat >"$formula" <<'RUBY'
class ChangedApacheSerf < Formula
  on_linux do
    depends_on "zlib-ng-compat"
  end

  def install
    args = []
    system "scons", *new_args
  end
end
RUBY
    cp "$formula" "$formula.before"

    run env HOME="$rotted_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-apache-serf.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing to start source builds"* ]]
    cmp -s "$formula.before" "$formula"

    local missing_home="$BATS_TEST_TMPDIR/apache-serf-missing-formula-home"
    mkdir -p "$missing_home/.local"

    run env HOME="$missing_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-apache-serf.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"apache-serf.rb not found"* ]]
    [[ "$output" == *"refusing to start source builds"* ]]
}

@test "Gecode formula patch disables CMake Gist and Qt atomically on Linux" {
    local fake_home="$BATS_TEST_TMPDIR/gecode-cmake-patch-home"
    local formula="$fake_home/.local/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/g/gecode.rb"
    mkdir -p "$(dirname "$formula")"
    cat >"$formula" <<'RUBY'
class Gecode < Formula
  depends_on "cmake" => :build
  depends_on "qtbase"

  def install
    args = %w[
      -DGECODE_ENABLE_EXAMPLES=OFF
      -DGECODE_ENABLE_GIST=ON
      -DGECODE_ENABLE_MPFR=OFF
      -DGECODE_ENABLE_QT=ON
    ]
    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
  end
end
RUBY

    run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-gecode.sh"

    [ "$status" -eq 0 ]
    grep -Fq 'pour_bottle? do' "$formula"
    grep -Fq 'reason "Linux bottle contains Gist and requires Qt"' "$formula"
    grep -Fq 'satisfy { OS.mac? }' "$formula"
    grep -Fq 'depends_on "qtbase" if OS.mac?' "$formula"
    grep -Fq -- '-DGECODE_ENABLE_GIST=#{OS.mac? ? "ON" : "OFF"}' "$formula"
    grep -Fq -- '-DGECODE_ENABLE_QT=#{OS.mac? ? "ON" : "OFF"}' "$formula"
    ! grep -Fq '      -DGECODE_ENABLE_GIST=ON' "$formula"
    ! grep -Fq '      -DGECODE_ENABLE_QT=ON' "$formula"

    run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-gecode.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"already applied"* ]]
    [ "$(grep -Fc 'pour_bottle? do' "$formula")" -eq 1 ]
    [ "$(grep -Fc 'satisfy { OS.mac? }' "$formula")" -eq 1 ]
    [ "$(grep -Fc 'depends_on "qtbase" if OS.mac?' "$formula")" -eq 1 ]
    [ "$(grep -Fc -- '-DGECODE_ENABLE_GIST=#{OS.mac? ? "ON" : "OFF"}' "$formula")" -eq 1 ]
    [ "$(grep -Fc -- '-DGECODE_ENABLE_QT=#{OS.mac? ? "ON" : "OFF"}' "$formula")" -eq 1 ]

    local guarded_home="$BATS_TEST_TMPDIR/gecode-guarded-dependency-home"
    formula="$guarded_home/.local/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/g/gecode.rb"
    mkdir -p "$(dirname "$formula")"
    cat >"$formula" <<'RUBY'
class GuardedGecode < Formula
  depends_on "cmake" => :build
  depends_on "qtbase" if OS.mac?

  def install
    args = %w[
      -DGECODE_ENABLE_EXAMPLES=OFF
      -DGECODE_ENABLE_GIST=ON
      -DGECODE_ENABLE_MPFR=OFF
      -DGECODE_ENABLE_QT=ON
    ]
    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
  end
end
RUBY

    run env HOME="$guarded_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-gecode.sh"

    [ "$status" -eq 0 ]
    [ "$(grep -Fc 'depends_on "qtbase" if OS.mac?' "$formula")" -eq 1 ]
    ! grep -Fq 'if OS.mac? if OS.mac?' "$formula"
    grep -Fq 'pour_bottle? do' "$formula"
    grep -Fq -- '-DGECODE_ENABLE_GIST=#{OS.mac? ? "ON" : "OFF"}' "$formula"

    local rotted_home="$BATS_TEST_TMPDIR/gecode-rotted-anchor-home"
    formula="$rotted_home/.local/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/g/gecode.rb"
    mkdir -p "$(dirname "$formula")"
    cat >"$formula" <<'RUBY'
class ChangedGecode < Formula
  depends_on "qtbase"

  def install
    args = ["-DGECODE_ENABLE_MPFR=OFF"]
    system "cmake", *args
  end
end
RUBY
    cp "$formula" "$formula.before"

    run env HOME="$rotted_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-gecode.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing to start source builds"* ]]
    cmp -s "$formula.before" "$formula"

    local missing_home="$BATS_TEST_TMPDIR/gecode-missing-formula-home"
    mkdir -p "$missing_home/.local"

    run env HOME="$missing_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-gecode.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"gecode.rb not found"* ]]
    [[ "$output" == *"refusing to start source builds"* ]]
}

@test "Linux Gecode reconciliation rebuilds a broken poured keg from source" {
    local prefix="$BATS_TEST_TMPDIR/gecode-prefix"
    local calls="$BATS_TEST_TMPDIR/gecode-calls"
    mkdir -p "$prefix/lib"
    touch "$prefix/lib/libgecodegist.so"

    run env GECODE_PREFIX="$prefix" CALLS="$calls" DF_USE_PLAT=0 LC_ALL=C LANG=C bash -c '
        source "$1/install/linux-packages.sh"
        brew() {
            case "$1 $2" in
                "list --formula") printf "%s\n" gecode ;;
                "linkage --test") return 0 ;;
                "--prefix gecode") printf "%s\n" "$GECODE_PREFIX" ;;
                "reinstall --build-from-source")
                    [[ "$3" == "gecode" ]] || return 97
                    printf "%s\n" "$*" >>"$CALLS"
                    mv "$GECODE_PREFIX/lib/libgecodegist.so" "$GECODE_PREFIX/rebuilt-without-gist"
                    ;;
                *) return 98 ;;
            esac
        }
        _reconcile_brew_gecode
    ' _ "$REPO"

    [ "$status" -eq 0 ]
    grep -Fxq 'reinstall --build-from-source gecode' "$calls"
}

@test "Linux Bundle preinstalls a working Subversion for Netpbm SVN fetches" {
    local brewfile="$BATS_TEST_TMPDIR/Brewfile"
    local state="$BATS_TEST_TMPDIR/subversion-installed"
    local calls="$BATS_TEST_TMPDIR/subversion-calls"
    printf '%s\n' 'brew "graphviz"' >"$brewfile"

    run env STATE="$state" CALLS="$calls" DF_USE_PLAT=0 LC_ALL=C LANG=C bash -c '
        source "$1/install/linux-packages.sh"
        brew() {
            case "$1 $2" in
                "list --formula")
                    [[ ! -f "$STATE" ]] || printf "%s\n" subversion
                    return 0
                    ;;
                "install subversion")
                    printf "%s\n" "$*" >>"$CALLS"
                    : >"$STATE"
                    ;;
                "--prefix subversion") printf "%s\n" "$3" ;;
                *) return 98 ;;
            esac
        }
        svn() { [[ -f "$STATE" ]]; }
        _ensure_brew_subversion_for_brewfile "$2"
        _ensure_brew_subversion_for_brewfile "$2"
    ' _ "$REPO" "$brewfile"

    [ "$status" -eq 0 ]
    [ "$(grep -Fc 'install subversion' "$calls")" -eq 1 ]
}

@test "Linux preinstalls Subversion before starting Bundle" {
    local subversion_line bundle_line
    subversion_line=$(grep -n '^_ensure_brew_subversion_for_brewfile "\$_BREWFILE_TMP"$' \
        "$REPO/install/linux-packages.sh" | cut -d: -f1)
    bundle_line=$(grep -n '^_run_brew_bundle "\$_BREWFILE_TMP" ' \
        "$REPO/install/linux-packages.sh" | cut -d: -f1)

    [ "$subversion_line" -lt "$bundle_line" ]
}

@test "Linux Bundle retries after a transient nonzero install with satisfied dependencies" {
    local brewfile="$BATS_TEST_TMPDIR/Brewfile"
    local calls="$BATS_TEST_TMPDIR/bundle-calls"
    printf '%s\n' 'brew "graphviz"' >"$brewfile"

    run env CALLS="$calls" DF_USE_PLAT=0 LC_ALL=C LANG=C bash -c '
        source "$1/install/linux-packages.sh"
        brew() {
            printf "%s\n" "$*" >>"$CALLS"
            if [[ "$1 $2" == "bundle install" ]]; then
                [[ "$(grep -Fc "bundle install" "$CALLS")" -gt 1 ]]
                return
            fi
            if [[ "$1 $2" == "bundle check" ]]; then
                [[ " $* " == *" --no-upgrade "* ]]
                return
            fi
            return 98
        }
        _run_brew_bundle "$2" --no-upgrade
    ' _ "$REPO" "$brewfile"

    [ "$status" -eq 0 ]
    [ "$(wc -l <"$calls")" -eq 4 ]
    [ "$(sed -n '1p' "$calls")" = "bundle install --no-upgrade --file=$brewfile" ]
    [ "$(sed -n '2p' "$calls")" = "bundle check --no-upgrade --file=$brewfile" ]
    [ "$(sed -n '3p' "$calls")" = "bundle install --no-upgrade --file=$brewfile" ]
    [ "$(sed -n '4p' "$calls")" = "bundle check --no-upgrade --file=$brewfile" ]
    [[ "$output" == *"brew bundle retry completed cleanly"* ]]
}

@test "Linux Bundle verifies a successful install against the Brewfile" {
    local brewfile="$BATS_TEST_TMPDIR/Brewfile"
    local calls="$BATS_TEST_TMPDIR/bundle-success-calls"
    printf '%s\n' 'brew "graphviz"' >"$brewfile"

    run env CALLS="$calls" DF_USE_PLAT=0 LC_ALL=C LANG=C bash -c '
        source "$1/install/linux-packages.sh"
        brew() {
            printf "%s\n" "$*" >>"$CALLS"
            [[ "$1 $2" == "bundle install" ]] && return 0
            [[ "$1 $2" == "bundle check" ]] && return 11
            return 98
        }
        _run_brew_bundle "$2" --no-upgrade
    ' _ "$REPO" "$brewfile"

    [ "$status" -eq 11 ]
    [ "$(wc -l <"$calls")" -eq 2 ]
    [ "$(sed -n '1p' "$calls")" = "bundle install --no-upgrade --file=$brewfile" ]
    [ "$(sed -n '2p' "$calls")" = "bundle check --no-upgrade --file=$brewfile" ]
}

@test "Linux package reconciliation fails when Bundle remains incomplete" {
    grep -q 'die "brew bundle failed' "$REPO/install/linux-packages.sh"
    ! grep -q 'some packages may not be installed' "$REPO/install/linux-packages.sh"
    ! grep -q 'brew update failed.*definitions may be stale' "$REPO/install/linux-packages.sh"
    grep -q 'brew tap homebrew/core --force' "$REPO/install/linux-packages.sh"
    grep -q 'die "Could not tap homebrew/core' "$REPO/install/linux-packages.sh"
}

@test "Linux Bundle preserves the first failure when dependency check fails" {
    local brewfile="$BATS_TEST_TMPDIR/Brewfile"
    local calls="$BATS_TEST_TMPDIR/bundle-check-failed-calls"
    printf '%s\n' 'brew "graphviz"' >"$brewfile"

    run env CALLS="$calls" DF_USE_PLAT=0 LC_ALL=C LANG=C bash -c '
        source "$1/install/linux-packages.sh"
        brew() {
            printf "%s\n" "$*" >>"$CALLS"
            [[ "$1 $2" == "bundle install" ]] && return 7
            [[ "$1 $2" == "bundle check" ]] && return 9
            return 98
        }
        _run_brew_bundle "$2" --no-upgrade
    ' _ "$REPO" "$brewfile"

    [ "$status" -eq 7 ]
    [ "$(wc -l <"$calls")" -eq 2 ]
    [ "$(sed -n '1p' "$calls")" = "bundle install --no-upgrade --file=$brewfile" ]
    [ "$(sed -n '2p' "$calls")" = "bundle check --no-upgrade --file=$brewfile" ]
}

@test "Linux Bundle does not hide a failed upgrade behind dependency state" {
    local brewfile="$BATS_TEST_TMPDIR/Brewfile"
    printf '%s\n' 'brew "graphviz"' >"$brewfile"

    run env DF_USE_PLAT=0 LC_ALL=C LANG=C bash -c '
        source "$1/install/linux-packages.sh"
        brew() {
            [[ "$1 $2" == "bundle install" ]] && return 7
            [[ "$1 $2" == "bundle check" ]] && return 0
            return 98
        }
        _run_brew_bundle "$2"
    ' _ "$REPO" "$brewfile"

    [ "$status" -eq 7 ]
}

@test "Linux Bundle propagates interrupts without checking or retrying" {
    local brewfile="$BATS_TEST_TMPDIR/Brewfile"
    local calls="$BATS_TEST_TMPDIR/bundle-interrupt-calls"
    printf '%s\n' 'brew "graphviz"' >"$brewfile"

    run env CALLS="$calls" DF_USE_PLAT=0 LC_ALL=C LANG=C bash -c '
        source "$1/install/linux-packages.sh"
        brew() {
            printf "%s\n" "$*" >>"$CALLS"
            [[ "$1 $2" == "bundle install" ]] && return 130
            return 98
        }
        _run_brew_bundle "$2"
    ' _ "$REPO" "$brewfile"

    [ "$status" -eq 130 ]
    [ "$(wc -l <"$calls")" -eq 1 ]
    grep -Fxq 'bundle install --file='"$brewfile" "$calls"
}

@test "Ruby formula patch isolates the build runner from the previous keg" {
    local fake_home="$BATS_TEST_TMPDIR/ruby-patch-home"
    local formula="$fake_home/.local/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/r/ruby.rb"
    mkdir -p "$(dirname "$formula")"
    cat >"$formula" <<'RUBY'
class Ruby < Formula
  def install
    paths = %w[libyaml openssl@3].map { |f| formula_opt_prefix(f) }
    # Add versioned Ruby RPATH so user-installed gems can work when user is switched to versioned Ruby
    paths << versioned_opt_prefix if OS.linux? && !versioned_formula?
    ENV.prepend "LDFLAGS", "-Wl,-rpath,#{lib}" if OS.linux?

    system "./configure", *args
    system "make"
    system "make", "install"

    if build.stable?
      resource("rubygems").stage do
        ENV.prepend_path "PATH", bin

        mkdir_p HOMEBREW_PREFIX/"lib/ruby/gems/#{api_version}"
        system bin/"ruby", "setup.rb", "--prefix=#{buildpath}/vendor_gem"
      end
    end

    config_file = lib/"ruby/#{api_version}/rubygems/defaults/operating_system.rb"
    config_file.write rubygems_config
  end
end
RUBY

    run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-ruby.sh"

    [ "$status" -eq 0 ]
    grep -Fq 'ENV.prepend "LDFLAGS", "-Wl,--enable-new-dtags -Wl,-rpath,#{lib}" if OS.linux?' "$formula"
    ! grep -Fq 'ENV.prepend "LDFLAGS", "-Wl,-rpath,#{lib}" if OS.linux?' "$formula"
    grep -Fq 'mkdir_p "lib/rubygems/defaults"' "$formula"
    grep -Fq 'touch "lib/rubygems/defaults/operating_system.rb"' "$formula"
    local defaults_line configure_line install_line restore_line
    defaults_line=$(grep -nF 'touch "lib/rubygems/defaults/operating_system.rb"' "$formula" | cut -d: -f1)
    configure_line=$(grep -nF 'system "./configure", *args' "$formula" | cut -d: -f1)
    install_line=$(grep -nF 'system "make", "install"' "$formula" | cut -d: -f1)
    restore_line=$(grep -nF 'config_file.write rubygems_config' "$formula" | cut -d: -f1)
    [ "$defaults_line" -lt "$configure_line" ]
    [ "$configure_line" -lt "$install_line" ]
    [ "$install_line" -lt "$restore_line" ]
    run grep -F 'mkdir_p HOMEBREW_PREFIX/' "$formula"
    [ "$status" -eq 1 ]

    run env HOME="$fake_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-ruby.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"already applied"* ]]
    [ "$(grep -Fc 'ENV.prepend "LDFLAGS"' "$formula")" -eq 1 ]
    [ "$(grep -Fc 'touch "lib/rubygems/defaults/operating_system.rb"' "$formula")" -eq 1 ]

    local clean_home="$BATS_TEST_TMPDIR/ruby-clean-upstream-home"
    formula="$clean_home/.local/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/r/ruby.rb"
    mkdir -p "$(dirname "$formula")"
    cat >"$formula" <<'RUBY'
class Ruby < Formula
  def install
    paths << versioned_opt_prefix if OS.linux? && !versioned_formula?
    system "./configure", *args
    system "make"
    system "make", "install"
    config_file = lib/"ruby/#{api_version}/rubygems/defaults/operating_system.rb"
    config_file.write rubygems_config
  end
end
RUBY

    run env HOME="$clean_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-ruby.sh"

    [ "$status" -eq 0 ]
    grep -Fq -- '--enable-new-dtags' "$formula"
    grep -Fq 'touch "lib/rubygems/defaults/operating_system.rb"' "$formula"

    local rotted_home="$BATS_TEST_TMPDIR/ruby-rotted-anchor-home"
    formula="$rotted_home/.local/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/r/ruby.rb"
    mkdir -p "$(dirname "$formula")"
    cat >"$formula" <<'RUBY'
class ChangedRuby < Formula
  def install
    paths << versioned_opt_prefix if OS.linux? && !versioned_formula?
    system "./configure", *new_args
  end
end
RUBY

    run env HOME="$rotted_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-ruby.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing to start source builds"* ]]
    grep -Fq 'paths << versioned_opt_prefix if OS.linux? && !versioned_formula?' "$formula"
    ! grep -Fq -- '--enable-new-dtags' "$formula"

    local no_restore_home="$BATS_TEST_TMPDIR/ruby-no-restoration-home"
    formula="$no_restore_home/.local/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/r/ruby.rb"
    mkdir -p "$(dirname "$formula")"
    cat >"$formula" <<'RUBY'
class ChangedRuby < Formula
  def install
    paths << versioned_opt_prefix if OS.linux? && !versioned_formula?
    system "./configure", *args
    system "make", "install"
  end
end
RUBY

    run env HOME="$no_restore_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-ruby.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"RubyGems restoration"* ]]
    ! grep -Fq -- '--enable-new-dtags' "$formula"
    ! grep -Fq 'touch "lib/rubygems/defaults/operating_system.rb"' "$formula"

    local missing_home="$BATS_TEST_TMPDIR/ruby-missing-formula-home"
    mkdir -p "$missing_home/.local"

    run env HOME="$missing_home" DF_USE_PLAT=0 LC_ALL=C LANG=C \
        bash "$REPO/install/patch-homebrew-ruby.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"ruby.rb not found"* ]]
    [[ "$output" == *"refusing to start source builds"* ]]
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
    grep -q '_uv_cmd=("$_uv" tool install "$_pkg")' "$REPO/install/python.sh"
    ! grep -q '"${_uv_args\[@\]}"' "$REPO/install/python.sh"
}

@test "Python installer uses the PLAT-owned uv without relying on PATH" {
    grep -q '_uv="\$ARCH_BIN/uv"' "$REPO/install/python.sh"
    ! grep -Eq '^[[:space:]]*(run_logged )?uv (venv|pip|tool)' "$REPO/install/python.sh"
}

@test "Git SSH capability probe cannot inherit an open bootstrap stdin" {
    grep -q -- '-T "git@\$host" </dev/null >/dev/null 2>&1' "$REPO/install/_lib.sh"
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
