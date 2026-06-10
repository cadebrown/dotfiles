# Inspecting ELF Files With readelf

`readelf` is the canonical structural dumper for ELF. It parses headers, segments, sections, symbols, relocations, dynamic entries, and notes without disassembling. It does not depend on libbfd, so it reads even malformed/unusual files that other tools reject. Use it for nearly all read-only ELF inspection.

## Implementations
- **GNU `readelf`** (binutils) — the default; options below use its long forms.
- **`llvm-readelf`** — LLVM's drop-in with GNU-compatible flags; `llvm-readobj` is the same engine with a more structured (LLVM-style) output and `--elf-output-style=GNU` to match.
- **`eu-readelf`** (elfutils) — alternate implementation; broadly similar flags.
- Cross-toolchain builds are prefixed (e.g. `aarch64-linux-gnu-readelf`) — use the prefix matching the target architecture when available.

Use `readelf --version` to confirm the implementation and `readelf --help` for the full option list.

## Commonly Used Options
- `readelf -h <file>`: ELF **header** — class (32/64), endianness, OS/ABI, type (`REL`/`EXEC`/`DYN`/`CORE`), machine, entry point, table offsets. The first call for any unknown binary.
- `readelf -l <file>`: **Program headers / segments** plus the section-to-segment mapping. Use for load layout, `PT_INTERP`, `PT_GNU_STACK`/`PT_GNU_RELRO` (hardening), and TLS.
- `readelf -S <file>`: **Section headers** — names, types, addresses, offsets, sizes, flags. Use to inventory sections and spot what was stripped.
- `readelf -s <file>`: **Symbol tables** (`.symtab` and `.dynsym`). Use `--dyn-syms` to restrict to the dynamic table (the only one present in stripped binaries).
- `readelf -d <file>`: **Dynamic section** — `DT_NEEDED`, `SONAME`, `RPATH`/`RUNPATH`, flags (`BIND_NOW`, `PIE`). Core of dynamic-linking and hardening questions.
- `readelf -r <file>`: **Relocations** (all relocation sections). Add nothing else for a full dump; combine with `grep` to filter by type or symbol.
- `readelf -n <file>`: **Notes** — build-id, ABI tag, GNU property (CET/BTI). Use to fingerprint a build or match split debug info.
- `readelf -V <file>`: **Version info** — symbol versioning (`.gnu.version*`), version definitions and needs.
- `readelf -A <file>`: **Architecture-specific** info (e.g. ARM attributes, MIPS ABI flags).
- `readelf -x <section> <file>`: **Hex dump** of a section's bytes (name or index).
- `readelf -p <section> <file>`: **String dump** of a section (e.g. `-p .comment`, `-p .interp`).
- `readelf -e <file>`: Equivalent to `-h -l -S` (all headers).
- `readelf -a <file>`: Dump (almost) everything. Verbose — prefer targeted flags, then widen.

### Output-quality flags
- `readelf -W` / `--wide`: Do not truncate lines to 80 columns. **Use almost always** — default wrapping mangles tables.
- `readelf -C` / `--demangle`: Demangle C++/Rust symbol names in output (or pipe through `c++filt`).

## Hardening Detection (checksec workflow)
Each mitigation is derivable from the dumps above. Add `-W` to all.

```bash
# NX: examine GNU_STACK segment flags. "RW " = NX on; "RWE" = NX off; absent historically = exec stack.
readelf -lW <bin> | grep GNU_STACK

# PIE: ELF type DYN + PIE flag (vs EXEC = no PIE; DYN w/o PIE flag + no interp = shared lib).
readelf -hW <bin> | grep Type
readelf -dW <bin> | grep -E 'FLAGS_1|PIE'

# RELRO: GNU_RELRO present = partial; present AND BIND_NOW/NOW = full; neither = none.
readelf -lW <bin> | grep GNU_RELRO
readelf -dW <bin> | grep -E 'BIND_NOW|FLAGS'

# Stack canary: references to the stack-protector runtime.
readelf -sW <bin> | grep -E '__stack_chk_(fail|guard)'

# FORTIFY_SOURCE: fortified *_chk function variants.
readelf --dyn-syms -W <bin> | grep -E '_chk@|_chk$'

# RPATH / RUNPATH: insecure or relative library search paths (security-relevant).
readelf -dW <bin> | grep -E 'RPATH|RUNPATH'
```

If `checksec` is installed, `checksec --file=<bin>` (or `--format=json`) reports all of the above at once; the commands here reproduce it from first principles.

## Companion Tools
Small, focused utilities that complement `readelf`:

| Tool | Use |
|------|-----|
| `file <bin>` | One-line identification (class, endianness, type, machine, static/dynamic, interpreter, stripped). Best first glance. |
| `size <bin>` | Sizes of `.text`/`.data`/`.bss` (and total). `size -A` lists every section. |
| `nm <bin>` | List symbols with addresses and type letters. `nm -D` = dynamic symbols; `nm -C` = demangle; `nm --defined-only`/`-u` (undefined only); `nm -S` adds sizes. |
| `ldd <bin>` | Resolve shared-library dependencies. **Caution:** `ldd` may execute the target on some systems — for untrusted binaries use `readelf -d | grep NEEDED` (and `objdump -p`) instead. |
| `strings <bin>` | Extract printable strings. `strings -a` scans the whole file; `-t x` prints offsets; `-n <len>` sets minimum length. |
| `c++filt` | Demangle C++/Rust names from any text stream (pipe `readelf`/`nm`/`objdump` output through it). |

## Notes
- For DWARF (`.debug_*`) sections, `readelf --debug-dump=<section>` dumps them, but a dedicated DWARF tool (`llvm-dwarfdump`/`dwarfdump`) decodes the semantics far better — route DWARF questions there.
- When output is confusing, re-run with `-W`; most "broken" tables are just wrapped.
