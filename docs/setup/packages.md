# Packages

Each package layer has a declarative text file and an idempotent install script.
All scripts skip already-installed items and are safe to re-run.

| Layer | File | Script | Platform |
|---|---|---|---|
| System packages | `packages/Brewfile` | `install/homebrew.sh` / `install/linux-packages.sh` | macOS (bottles) / Linux (compiled in manylinux container) |
| Global npm | `packages/npm.txt` | `install/npm.sh` | All |
| Rust tools | `packages/cargo.txt` | `install/rust.sh` | All |
| Python packages | `packages/pip.txt` | `install/python.sh` | All |
| Claude plugins | `packages/claude-plugins.txt` | `install/claude.sh` | All |

## Adding a package

Follow this priority order:

1. **npm** — if the program is an npm package, add it to `packages/npm.txt`:
   ```
   @scope/package-name
   ```

2. **cargo** — if it's a Rust crate, add it to `packages/cargo.txt`:
   ```
   crate-name
   ```

3. **Homebrew** — if it's in Homebrew (works on macOS natively, compiled from source on Linux), add it to `packages/Brewfile`:
   ```ruby
   brew "tool-name"
   ```
   Wrap in `if OS.mac?` if it's macOS-only (casks, GUI apps, macOS services).

4. **Special script** — if it requires custom install steps, look at an existing script in `install/` for patterns and follow them. Add an `INSTALL_*` flag to `bootstrap.sh`.

5. **Ask** — if none of the above fits cleanly, ask before inventing a new mechanism.

## Why this split

- **Homebrew** — handles the bulk of CLI tools on both platforms. macOS gets precompiled bottles; Linux installs inside a `manylinux_2_28` container (most packages also pour as bottles, Homebrew bundles its own glibc).
- **npm / cargo** — language-ecosystem tools that publish to npm/crates.io install faster and more reliably via their native registries than through Homebrew.
- **pip.txt in a venv** — a single activated venv for interactive/scripting use. Project-specific envs are handled by `uv` separately.
- **Claude plugins** — `claude plugin install` has its own registry; these aren't npm or Homebrew packages.

## Updating packages

Re-run the relevant script after editing the file:

```sh
# System packages
brew bundle --file=~/dotfiles/packages/Brewfile   # macOS
# (Linux: re-run bootstrap or linux-packages.sh)

# npm globals
bash ~/dotfiles/install/npm.sh

# Cargo tools
bash ~/dotfiles/install/rust.sh

# Python venv
bash ~/dotfiles/install/python.sh
```
