# Writing, Modifying, or Reviewing Code That Interacts With ELF Data

You may be tasked with writing, modifying, or reviewing code that parses, analyzes, or rewrites ELF data.

## General Guidelines
- **Rely on Authoritative Sources**: For ground-truth constant values, struct layouts, and relocation types, read `/usr/include/elf.h` directly, consult the System V gABI / `elf(5)`, the architecture psABI, or `llvm/include/llvm/BinaryFormat/ELF.h`. Do not hardcode a constant from memory if it can be confirmed.
- **Using ELF Expertise**: Apply ELF-specific expertise to code that touches ELF data, but do NOT impose it on unrelated code.

## Writing Code
- **Prefer Python for Scripting**: For one-off analysis and filtering (e.g. "find all functions calling `system`", "list `DT_NEEDED` across a tree of binaries"), prefer Python with `pyelftools` unless another language is specified.
- **Leverage Existing Libraries**: Prefer a maintained library over a hand-rolled parser whenever one exists for the chosen language (see *Common ELF Libraries*). Reach for raw `struct`-unpacking only for teaching, minimal dependencies, or formats no library covers.
- **Handle Class and Endianness**: ELF files are 32- or 64-bit (`EI_CLASS`) and little- or big-endian (`EI_DATA`). Read these from `e_ident` first and size/byte-swap every field accordingly; never assume host class/endianness. Libraries that expose a class-agnostic API (e.g. libelf's `gelf_*`) are preferable for portable code.
- **Validate Before Trusting**: Check the magic (`0x7F 'E' 'L' 'F'`), then bounds-check every offset/size (`e_phoff`, `e_shoff`, `sh_offset+sh_size`, string-table indices) against the file size before dereferencing. ELF inputs are frequently adversarial.
- **Refer to Library Documentation**: Consult the library's docs (in-code and online) as needed rather than guessing API shapes.

## Modifying Code
- **Follow Existing Styles**: Match existing code style, formatting, and naming conventions.
- **Group Changes**: Make logically related edits together; separate unrelated changes into distinct steps.
- **Describe Changes**: Clearly state the purpose of each group of changes and what each individual change achieves.
- **Advise on Complex Changes**: Flag especially large or risky changes before making them — e.g. adding support for a new relocation type, a new architecture's encodings, or any code that rewrites section/segment tables (offset bookkeeping is error-prone).

## Reviewing Code
- **Only Suggest Changes**: Suggest changes or advise on refactors; do NOT modify the code.
- **Consider Edge Cases**: Look specifically for:
  - **Class/endianness assumptions** — code that only handles ELF64 little-endian.
  - **Object-type assumptions** — logic that assumes `ET_EXEC` and breaks on `ET_DYN` (PIE/shared) or `ET_REL` (no segments, section-relative `st_value`).
  - **Stripped binaries** — relying on `.symtab` when only `.dynsym` exists; assuming section headers are present at all.
  - **Extended indices** — `e_shnum`/`e_phnum`/`st_shndx` escape values (`SHN_XINDEX`, `PN_XNUM`, `SHN_LORESERVE`) where the real count lives elsewhere.
  - **Special symbols/sections** — `SHN_UNDEF`/`SHN_ABS`/`SHN_COMMON`, weak symbols, `STT_GNU_IFUNC`, `SHT_NOBITS` (`.bss` has no file bytes).
  - **String-table safety** — unterminated or out-of-range `st_name`/`sh_name` indices.
  - **Symbol versioning** — names carrying `@`/`@@` version suffixes when matching.
  - **Bounds/overflow** — unchecked offsets, integer overflow in `offset + size`, untrusted counts driving allocations.

# Common ELF Libraries
Prefer these when writing new code (if the chosen language has a compatible option).

| Library | Language | URL | Notes |
|---------|----------|-----|-------|
| `pyelftools` | Python | https://github.com/eliben/pyelftools | Pure-Python; parses ELF **and** DWARF. The default for scripting and filtering. Read-only. |
| `LIEF` | C++ / Python / Rust / C | https://github.com/lief-project/LIEF | Cross-format (ELF/PE/Mach-O/COFF). Can **parse and modify** (add/remove sections, rewrite symbols, change dynamic entries) and offers a common abstraction across formats. |
| `libelf` / `elfutils` | C | https://sourceware.org/elfutils | Classic libelf API; the `gelf_*` layer abstracts ELF32/ELF64 for portable C. Reference-grade. |
| `goblin` | Rust | https://github.com/m4b/goblin | Fast, cross-format, `no_std`-friendly parsing. |
| `object` | Rust | https://github.com/gimli-rs/object | Unified read/write across object formats; pairs with `gimli` for DWARF. |
| `debug/elf` | Go | https://pkg.go.dev/debug/elf | Standard-library, built-in. Read-only. |
| `LibObjectFile` | .NET | https://github.com/xoofx/LibObjectFile | ELF/PE/COFF read **and** write. |

Note: `libbfd` (binutils) underlies `objdump`/`objcopy` but is intentionally not a stable public API — prefer the libraries above for new code rather than linking `libbfd` directly.
