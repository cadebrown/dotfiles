# Disassembly and Content Dumps With objdump

`objdump` complements `readelf`: where `readelf` reports structural metadata, `objdump` disassembles code and dumps raw section content. Use it when the question is "what do these instructions/bytes do?" rather than "how is this file structured?". For anything beyond light disassembly — control-flow recovery, decompilation, scripted analysis — use a dedicated RE tool (Ghidra, IDA, Binary Ninja, radare2/rizin).

## Implementations
- **GNU `objdump`** (binutils) — built on libbfd; the default.
- **`llvm-objdump`** — LLVM equivalent, mostly flag-compatible, often better at newer ISA extensions and cross-format work (ELF/PE/Mach-O). Disassembly syntax/formatting differs slightly.
- Cross-toolchain builds are prefixed (e.g. `riscv64-linux-gnu-objdump`); use the prefix matching the target ISA so the correct disassembler is selected.

`objdump --version` confirms the implementation; `objdump --help` lists options.

## Commonly Used Options
- `objdump -d <file>`: **Disassemble** executable sections only (`.text`, `.plt`, ...). The usual starting point.
- `objdump -D <file>`: Disassemble **all** sections, including data (noisy; use when inspecting non-code sections as instructions).
- `objdump -S <file>`: Disassemble with **interleaved source** (requires debug info / `-g` build).
- `objdump -l`: Annotate with **file/line numbers** (requires debug info). Combine with `-d`/`-S`.
- `objdump -t <file>` / `-T <file>`: Symbol table / **dynamic** symbol table.
- `objdump -r <file>` / `-R <file>`: Relocations / **dynamic** relocations.
- `objdump -h <file>`: Section headers (summary). `objdump -x <file>`: all headers + symbols. `objdump -p <file>`: private headers, including the dynamic section and `NEEDED` libraries (a safe, non-executing alternative to `ldd`).
- `objdump -s <file>`: Full **hex+ASCII content** of (all) sections. Pair with `-j` to target one.
- `objdump -j <section> ...`: Restrict the operation to a single section (e.g. `-d -j .plt`).
- `objdump --start-address=<addr> --stop-address=<addr> ...`: Limit disassembly to an address range.

### Disassembly-quality flags
- `objdump -M intel`: Use **Intel** syntax on x86/x86-64 (default is AT&T). (`llvm-objdump --x86-asm-syntax=intel`.)
- `objdump -C` / `--demangle`: Demangle C++/Rust symbol names.
- `objdump --no-show-raw-insn`: Hide opcode bytes for cleaner listings.
- `objdump -F`: Show **file offsets** alongside virtual addresses (useful when correlating with `readelf -S`).
- `objdump -w`: Wide output (don't truncate).

## Typical Recipes
```bash
# Disassemble a single function region cleanly, Intel syntax, demangled:
objdump -d -C -M intel --no-show-raw-insn <bin> | sed -n '/<main>:/,/ret/p'

# Inspect PLT stubs (how external calls trampoline through the GOT):
objdump -d -j .plt -M intel <bin>

# List dynamic dependencies WITHOUT executing the target (safer than ldd):
objdump -p <bin> | grep NEEDED

# Source-interleaved disassembly of a debug build:
objdump -d -S -l <bin-with-debug>
```

## Choosing readelf vs objdump
- Structure, metadata, hardening, dynamic info → **readelf** (`reference/readelf.md`).
- Instructions, source interleaving, raw section bytes → **objdump**.
- Both can dump symbols/relocations; prefer `readelf` for exhaustive, format-faithful metadata and `objdump` when you also want disassembly context in the same pass.
