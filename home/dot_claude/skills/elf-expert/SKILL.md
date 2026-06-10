---
name: elf-expert
description: Provides expertise for inspecting, analyzing, and modifying ELF (Executable and Linkable Format) binaries and understanding the ELF format/ABI. Triggers when examining ELF headers, sections, segments, symbols, relocations, or dynamic data; inspecting binary hardening (NX, RELRO, PIE, canaries); using readelf/objdump/nm; modifying ELF files (strip, objcopy, patchelf); or writing/reviewing code that parses ELF data.
allowed-tools: Read Bash Grep Glob WebSearch
---
# Overview
This skill provides technical knowledge and expertise about the ELF (Executable and Linkable Format) standard and how to interact with ELF files. Tasks include answering questions about the ELF format/ABI, inspecting and dumping ELF structure (headers, sections, segments, symbols, relocations, dynamic data, notes), assessing binary hardening, modifying ELF files, and writing/modifying/analyzing code that parses ELF data.

## When to Use This Skill
- Inspecting or explaining ELF structure: headers, program headers (segments), section headers (sections), symbol tables, relocations, the dynamic section, and notes
- Answering questions about the ELF format and the System V ABI (and architecture psABI supplements)
- Determining a binary's type (relocatable `.o`, executable, PIE, shared object, core dump), machine, class (32/64-bit), and endianness
- Assessing binary hardening (NX, RELRO, PIE, stack canaries, FORTIFY, RPATH/RUNPATH)
- Resolving dynamic-linking questions: `DT_NEEDED` dependencies, `SONAME`, search paths, GOT/PLT, symbol versioning
- Using `readelf`, `objdump`, `nm`, `size`, `file`, `strings`, or `ldd` to extract information
- Modifying ELF files with `strip`, `objcopy`, `patchelf`, or `elfedit`
- Writing or reviewing code that parses or manipulates ELF data (pyelftools, LIEF, libelf, goblin, etc.)

## When NOT to Use This Skill
- **DWARF Debug Info**: For parsing or interpreting `.debug_*` sections specifically, use a DWARF-focused tool/skill (`dwarfdump`, `llvm-dwarfdump`). This skill covers locating and dumping those sections, not decoding DWARF semantics.
- **Other Binary Formats**: For PE/COFF (Windows) or Mach-O (macOS), use format-appropriate tools. `LIEF` and `llvm-objdump` are cross-format if a single tool is required.
- **Runtime / Dynamic Debugging**: Use dedicated debuggers (gdb, lldb) and tracers (strace, ltrace) for runtime behavior; this skill is for static, on-disk analysis.
- **Reverse Engineering / Deep Disassembly**: Use dedicated RE tools (Ghidra, IDA, Binary Ninja, radare2/rizin). Use `objdump` only for light disassembly and section dumps.
- **Compiler/Linker Configuration**: Issues with *how* a toolchain emits ELF (linker scripts, codegen flags) are toolchain-specific and not covered here.

# ELF Format Reference
For the structural reference — the dual linking/execution views, the ELF header, program headers (segments), section headers (sections), the symbol table, relocations, the dynamic section, notes, and how to disambiguate ET_DYN (PIE vs shared object) — see `{baseDir}/reference/format.md`.

# Authoritative Sources
When precise ELF facts are needed (constant values, struct layouts, relocation types), prefer these over recall:

1. **`/usr/include/elf.h`**: The glibc ELF header is ground truth for constant values (`ET_*`, `PT_*`, `SHT_*`, `STT_*`, `DT_*`, `R_<ARCH>_*`) and struct layouts (`Elf64_Ehdr`, `Elf64_Phdr`, etc.). It is on-disk and greppable — read it directly with `grep`/`Read` before guessing a value.
2. **System V gABI / `elf(5)`**: The generic ABI defines the format. The `man 5 elf` page summarizes structures and constants. Use web search for the System V Application Binary Interface (gABI) for canonical wording.
3. **Architecture psABI supplements**: Relocation types and calling conventions are per-architecture. x86-64: `gitlab.com/x86-psABIs/x86-64-ABI`; AArch64: `github.com/ARM-software/abi-aa`; RISC-V: `github.com/riscv-non-isa/riscv-elf-psabi-doc`.
4. **LLVM reference implementation**: `llvm/include/llvm/BinaryFormat/ELF.h` (enums/constants) and `llvm/lib/Object/ELF*` (parsing) are reliable references.

# Inspecting ELF Files
Start with the smallest tool that answers the question, escalating only as needed.

## Quick Identification
Use `file <binary>` for a one-line summary (class, endianness, type, machine, dynamic/static, stripped, interpreter) before deeper inspection.

## readelf (primary)
`readelf` is the canonical structural dumper for ELF: headers, segments, sections, symbols, relocations, dynamic entries, and notes. Use it for nearly all read-only ELF inspection. See `{baseDir}/reference/readelf.md` (also covers `llvm-readelf`/`llvm-readobj`, `eu-readelf`, and the companion tools `nm`, `size`, `ldd`, `strings`, `c++filt`).

## objdump (disassembly and content dumps)
Use `objdump` when the task needs disassembly, source interleaving, or raw section content rather than structural metadata. See `{baseDir}/reference/objdump.md`. For anything beyond light disassembly, route to a dedicated RE tool (see *When NOT to Use*).

# Security Hardening Inspection
A frequent ELF task is assessing exploit-mitigation hardening (the `checksec` workflow). Each property is detectable from static ELF data, primarily via `readelf`. Detection commands are in `{baseDir}/reference/readelf.md`.

| Mitigation | What to inspect | Indicates ENABLED when |
|------------|-----------------|------------------------|
| **NX** (non-exec stack) | `PT_GNU_STACK` segment flags (`readelf -l`) | Flags are `RW` (no `E`/exec). `RWE` = disabled. A missing `PT_GNU_STACK` historically implies an executable stack. |
| **PIE** | ELF type (`readelf -h`) + dynamic flags (`readelf -d`) | Type is `DYN` **and** `DF_1_PIE` is set / `PT_INTERP` present. `EXEC` = no PIE. (A plain `DYN` without `PIE` flag + no interpreter is a shared library, not a PIE.) |
| **RELRO** | `PT_GNU_RELRO` (`readelf -l`) + `BIND_NOW` (`readelf -d`) | `PT_GNU_RELRO` present = *partial*. Present **and** `DT_BIND_NOW`/`DF_BIND_NOW`/`DF_1_NOW` = *full* RELRO. None = disabled. |
| **Stack canary** | Symbols (`readelf -s` / `--dyn-syms`) | References to `__stack_chk_fail` / `__stack_chk_guard` are present. |
| **FORTIFY_SOURCE** | Symbols (`readelf --dyn-syms`) | Fortified `*_chk` variants present (`__printf_chk`, `__memcpy_chk`, etc.). |
| **RPATH / RUNPATH** | Dynamic entries (`readelf -d`) | `DT_RUNPATH` (modern) or `DT_RPATH` (deprecated) present — **security-relevant**; flag insecure/relative search paths. |

For a one-shot report, `checksec --file=<binary>` (if installed) summarizes these; otherwise derive them from the `readelf` commands above.

# Modifying ELF Files
For changing ELF contents — stripping symbols/debug info, adding/removing/dumping sections, splitting debug info (`--only-keep-debug` + `--add-gnu-debuglink`), and adjusting dynamic metadata (interpreter, `RPATH`/`RUNPATH`, `DT_NEEDED`, `SONAME`) with `patchelf` — see `{baseDir}/reference/modification.md`. Prefer purpose-built tools (or `LIEF` for programmatic structural edits) over hand-editing bytes, which easily corrupts offsets.

# Working With Code
This skill supports writing, modifying, and reviewing code that parses or manipulates ELF data — both from-scratch parsers and library-backed code (pyelftools, LIEF, libelf/elfutils, goblin, `object`, `debug/elf`, LibObjectFile). See `{baseDir}/reference/coding.md`.

# Choosing Your Approach
```
┌─ Need a one-line identification (class/type/machine/stripped)?
│   └─ Use `file <binary>`
├─ Need to explain or recall the ELF format/ABI?
│   └─ See {baseDir}/reference/format.md; verify values against /usr/include/elf.h or the psABI
├─ Need to assess binary hardening (NX/RELRO/PIE/canary/FORTIFY/RPATH)?
│   └─ Use the Security Hardening table above + `readelf` ({baseDir}/reference/readelf.md)
├─ Need ELF structure (headers/segments/sections/symbols/relocs/dynamic/notes)?
│   └─ Use `readelf` ({baseDir}/reference/readelf.md)
├─ Need disassembly or raw section content?
│   └─ Use `objdump` ({baseDir}/reference/objdump.md); for deep RE use Ghidra/IDA/rizin
├─ Need to modify an ELF (strip/objcopy/patchelf/elfedit)?
│   └─ See {baseDir}/reference/modification.md
└─ Need to write, modify, or review code that parses/manipulates ELF data?
    └─ See {baseDir}/reference/coding.md
```
