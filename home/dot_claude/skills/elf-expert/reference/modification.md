# Modifying ELF Files

ELF files can be modified in place or copied with transformations. Prefer purpose-built tools — they keep the section/segment tables, offsets, and string tables consistent. Hand-editing bytes (or naive in-place size changes) easily corrupts a binary because offsets throughout the file are interdependent. For programmatic or structural edits (inserting sections/segments, rewriting symbols), use a library such as `LIEF` (see `reference/coding.md`).

## strip (remove symbols / debug info)
Shrinks binaries and removes metadata. Operates in place by default.
- `strip --strip-all <file>`: Remove all symbols and relocation info (most aggressive for executables).
- `strip --strip-debug <file>`: Remove only `.debug_*`/debug symbols; keep the symbol table.
- `strip --strip-unneeded <file>`: Remove symbols not needed for relocation processing (common for `.so`/`.o`).
- `strip --keep-symbol=<name> ...` / `--strip-symbol=<name>`: Selective keep/remove.
- `strip -o <out> <in>`: Write to a new file instead of editing in place.

## objcopy (copy with transformations)
The general-purpose ELF surgeon — copies an object applying edits. Common uses:
- **Strip into a separate file:** `objcopy --strip-debug` / `--strip-all` (like `strip`, but always producing an output copy).
- **Section management:**
  - `objcopy --remove-section=<name> <in> <out>`
  - `objcopy --add-section <name>=<file> --set-section-flags <name>=<flags> <in> <out>`
  - `objcopy --dump-section <name>=<outfile> <in>`: Extract a section's bytes to a file.
  - `objcopy --rename-section <old>=<new> <in> <out>`
- **Symbol management:** `--redefine-sym <old>=<new>`, `--globalize-symbol`, `--localize-symbol`, `--weaken`.
- **Format/representation conversion:** `objcopy -O binary <in> <out.bin>` (flat binary, e.g. for firmware); `-O ihex`, `-O srec`; `-I`/`-O` to set input/output target explicitly.

## Split Debug Info (standard workflow)
Keep a small stripped binary for distribution and a separate file with debug info, linked by build-id/debuglink:
```bash
# 1. Extract debug info to a sidecar file.
objcopy --only-keep-debug program program.debug
# 2. Strip the original.
objcopy --strip-debug program           # or: strip --strip-debug program
# 3. Link the stripped binary to its sidecar (so debuggers find it automatically).
objcopy --add-gnu-debuglink=program.debug program
```
Debuggers locate `program.debug` via the `.gnu_debuglink` section or the build-id (`.note.gnu.build-id`).

## patchelf (adjust dynamic metadata without recompiling)
Edits the dynamic linking metadata of executables and shared objects in place. Ideal for relocating binaries, fixing dependencies, or repackaging.
- `patchelf --set-interpreter /path/to/ld.so <file>`: Change the program interpreter (`PT_INTERP`).
- `patchelf --set-rpath <paths> <file>` / `--remove-rpath` / `--shrink-rpath`: Manage `RUNPATH`/`RPATH`.
- `patchelf --add-needed <lib>` / `--remove-needed <lib>` / `--replace-needed <old> <new>`: Manage `DT_NEEDED` entries.
- `patchelf --set-soname <name>`: Change `DT_SONAME` of a shared object.
- `patchelf --print-interpreter` / `--print-rpath` / `--print-needed` / `--print-soname`: Read current values.
- Prefer `--force-rpath` / `--no-default-lib` only when you understand the search-order implications.

## elfedit (tweak ELF header fields)
Small binutils tool for header-level edits without rebuilding:
- `elfedit --output-osabi=<abi> <file>`: Change `EI_OSABI` (e.g. to `Linux`/`none`) — sometimes needed for cross-distro/static binary compatibility.
- `elfedit --output-mach=<machine>` / `--output-type=<type>`: Adjust machine/type fields.
- `elfedit --enable-x86-feature=<feat>` / `--disable-x86-feature=<feat>`: Toggle CET/IBT feature bits.

## Cautions
- Changing a section's size in place is unsafe with most tools; offsets after it shift. Use `objcopy`/`patchelf` (which rebuild the file) or `LIEF`.
- Stripping a shared library too aggressively can break `dlopen`/symbol resolution — `--strip-unneeded` is usually the right level for `.so` files; keep `.dynsym`.
- After any modification, re-verify with `readelf -hlSd <file>` (and run/test if executable). Confirm `DT_NEEDED`, interpreter, and segment permissions are intact.

## Availability
`strip`, `objcopy`, `elfedit`, `readelf`, `objdump` ship in **binutils** (`apt install binutils`). `patchelf` is a separate package (`apt install patchelf`, `pip install patchelf`, or `nix-env -iA nixpkgs.patchelf`). LLVM provides `llvm-strip`/`llvm-objcopy` drop-ins.
