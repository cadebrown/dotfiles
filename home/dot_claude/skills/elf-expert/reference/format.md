# The ELF Format

ELF (Executable and Linkable Format) is the standard object file format on Linux and most Unix-like systems. A single ELF file is described by two complementary views:

- **Linking view** — described by the **section header table**; used by the linker (`ld`). Sections (`.text`, `.data`, `.symtab`, ...) carry fine-grained content and metadata.
- **Execution view** — described by the **program header table**; used by the loader/`ld.so` at runtime. Segments (`PT_LOAD`, `PT_DYNAMIC`, ...) group bytes into mappable units.

Both tables describe the same bytes from different angles. Relocatable objects (`.o`) generally have only sections; executables and shared objects have both (segments are mandatory to run). A fully stripped binary may have a minimal/absent section header table while remaining runnable via its segments.

## ELF Header (`Elf64_Ehdr`)
The first bytes of the file. Locate the section/program header tables and identify the file. Key fields:

| Field | Meaning |
|-------|---------|
| `e_ident[EI_MAG0..3]` | Magic `0x7F 'E' 'L' 'F'`. |
| `e_ident[EI_CLASS]` | `ELFCLASS32` (1) / `ELFCLASS64` (2). Determines 32- vs 64-bit struct widths. |
| `e_ident[EI_DATA]` | `ELFDATA2LSB` (little-endian) / `ELFDATA2MSB` (big-endian). |
| `e_ident[EI_OSABI]` | OS/ABI (`ELFOSABI_SYSV` 0, `ELFOSABI_LINUX` 3, `ELFOSABI_GNU`, ...). |
| `e_type` | `ET_REL` (1, relocatable), `ET_EXEC` (2, executable), `ET_DYN` (3, shared object / PIE), `ET_CORE` (4, core dump). |
| `e_machine` | Target ISA (see below). |
| `e_entry` | Virtual address of the entry point (0 if none). |
| `e_phoff` / `e_shoff` | File offsets of the program / section header tables. |
| `e_phnum` / `e_shnum` | Entry counts (escape values when `>= PN_XNUM`/0xffff — real count is in section 0). |
| `e_shstrndx` | Section index of the section-name string table (`.shstrtab`). |

Common `e_machine`: `EM_X86_64` (62), `EM_386` (3), `EM_AARCH64` (183), `EM_ARM` (40), `EM_RISCV` (243), `EM_PPC64` (21), `EM_MIPS` (8), `EM_S390` (22).

## Program Headers / Segments (`Elf64_Phdr`)
Each describes a segment: a file range (`p_offset`/`p_filesz`) mapped to a virtual range (`p_vaddr`/`p_memsz`) with permissions (`p_flags`: `PF_R`=4, `PF_W`=2, `PF_X`=1).

| Type | Purpose |
|------|---------|
| `PT_LOAD` | A loadable segment mapped into memory. `p_memsz > p_filesz` implies zero-fill (`.bss`). |
| `PT_DYNAMIC` | Points at the `.dynamic` array; how `ld.so` finds linking info. |
| `PT_INTERP` | Path to the dynamic linker/interpreter (e.g. `/lib64/ld-linux-x86-64.so.2`). Present ⇒ dynamically linked executable/PIE. |
| `PT_PHDR` | Location/size of the program header table itself. |
| `PT_NOTE` | Auxiliary notes (build-id, ABI tag, GNU properties). |
| `PT_TLS` | Thread-local storage template. |
| `PT_GNU_EH_FRAME` | Sorted index for `.eh_frame` (stack unwinding). |
| `PT_GNU_STACK` | Carries stack permissions; flags w/o `PF_X` ⇒ **NX** stack. |
| `PT_GNU_RELRO` | Region made read-only after relocation ⇒ **RELRO**. |
| `PT_GNU_PROPERTY` | `.note.gnu.property` (CET/IBT, BTI, shadow stack markers). |

## Section Headers / Sections (`Elf64_Shdr`)
Each section has a type (`sh_type`), flags (`sh_flags`), virtual address (`sh_addr`), file offset/size, and `sh_link`/`sh_info` cross-references. Common section types: `SHT_PROGBITS` (program data), `SHT_NOBITS` (`.bss`, occupies no file space), `SHT_SYMTAB`/`SHT_DYNSYM` (symbol tables), `SHT_STRTAB` (strings), `SHT_RELA`/`SHT_REL` (relocations), `SHT_DYNAMIC`, `SHT_NOTE`, `SHT_NULL`. Common flags: `SHF_ALLOC` (occupies memory at runtime), `SHF_WRITE`, `SHF_EXECINSTR`, `SHF_TLS`.

Frequently encountered sections:

| Section | Contents |
|---------|----------|
| `.text` | Executable code. |
| `.rodata` | Read-only constants. |
| `.data` / `.bss` | Initialized / zero-initialized writable data (`.bss` is `NOBITS`). |
| `.symtab` / `.strtab` | Full symbol table + its strings (removed by `strip`). |
| `.dynsym` / `.dynstr` | Dynamic symbol table + strings (needed at runtime; survives `strip`). |
| `.dynamic` | The dynamic linking array (`Elf64_Dyn[]`). |
| `.got` / `.got.plt` | Global Offset Table (data / PLT-related entries). |
| `.plt` / `.plt.sec` | Procedure Linkage Table trampolines for lazy/eager binding. |
| `.rela.dyn` / `.rela.plt` | Dynamic relocations / PLT (GOT) relocations. |
| `.init` / `.fini`, `.init_array` / `.fini_array` | Constructor/destructor code and function-pointer arrays. |
| `.interp` | Interpreter path (mirrors `PT_INTERP`). |
| `.note.gnu.build-id`, `.note.ABI-tag`, `.note.gnu.property` | Notes (see below). |
| `.eh_frame` / `.eh_frame_hdr` | Exception/unwinding info. |
| `.comment` | Toolchain/version strings. |
| `.debug_*` | DWARF debug info (decode with a DWARF tool, not this skill). |

## Symbol Table (`Elf64_Sym`)
Entries in `.symtab` (complete) or `.dynsym` (dynamic-only). Key fields:

- `st_name` — index into the associated string table.
- `st_value` / `st_size` — address (or offset, in `ET_REL`) and size.
- `st_info` — packs **binding** (high nibble) and **type** (low nibble):
  - Binding: `STB_LOCAL` (0), `STB_GLOBAL` (1), `STB_WEAK` (2).
  - Type: `STT_NOTYPE`, `STT_OBJECT` (data), `STT_FUNC`, `STT_SECTION`, `STT_FILE`, `STT_TLS`, `STT_GNU_IFUNC`.
- `st_other` — **visibility**: `STV_DEFAULT`, `STV_HIDDEN`, `STV_PROTECTED`, `STV_INTERNAL`.
- `st_shndx` — section index, or special: `SHN_UNDEF` (0, imported/undefined), `SHN_ABS` (absolute), `SHN_COMMON`, `SHN_XINDEX` (real index in `SHT_SYMTAB_SHNDX`).

## Relocations (`Elf64_Rel` / `Elf64_Rela`)
Instructions for patching addresses. `RELA` carries an explicit addend (`r_addend`); `REL` stores the addend in-place at the target. `r_offset` is where to patch; `r_info` packs the symbol index and a **per-architecture** relocation type (`ELF64_R_SYM`/`ELF64_R_TYPE`). Look up exact types in the psABI or `elf.h`. Common x86-64 examples: `R_X86_64_64`, `R_X86_64_PC32`, `R_X86_64_GLOB_DAT` (GOT data), `R_X86_64_JUMP_SLOT` (PLT/GOT), `R_X86_64_RELATIVE` (base-relative, dominant in PIE), `R_X86_64_COPY`, `R_X86_64_IRELATIVE` (ifunc resolver).

## Dynamic Section (`Elf64_Dyn`)
A tag/value array driving dynamic linking. Important tags:

| Tag | Meaning |
|-----|---------|
| `DT_NEEDED` | A required shared library (`SONAME`); multiple entries allowed. |
| `DT_SONAME` | This object's canonical name. |
| `DT_RPATH` / `DT_RUNPATH` | Library search paths (`RPATH` deprecated; `RUNPATH` searched after `LD_LIBRARY_PATH`). |
| `DT_STRTAB` / `DT_SYMTAB` | Dynamic string / symbol tables. |
| `DT_PLTGOT`, `DT_JMPREL`, `DT_PLTRELSZ`, `DT_PLTREL` | PLT/GOT relocation info. |
| `DT_RELA`/`DT_REL` (+ `SZ`/`ENT`) | Dynamic relocation tables. |
| `DT_INIT`/`DT_FINI`, `DT_INIT_ARRAY`/`DT_FINI_ARRAY` | Init/fini hooks. |
| `DT_FLAGS` / `DT_FLAGS_1` | Behavior flags: `DF_BIND_NOW`, `DF_1_NOW` (eager binding ⇒ full RELRO), `DF_1_PIE` (this `DYN` is a PIE), `DF_1_NODELETE`, `DF_TEXTREL`. |
| `DT_DEBUG` | Debugger rendezvous (typically present in executables, not libraries). |

### GOT/PLT and lazy binding (brief)
External function calls jump through a `.plt` stub that reads its target from the `.got.plt`. With **lazy binding** (default), the first call routes through the resolver (`_dl_runtime_resolve`) which fills in the GOT entry; subsequent calls go direct. With `BIND_NOW`/full RELRO, all GOT entries are resolved at load time and the GOT is then made read-only — removing a classic overwrite target.

## Notes (`PT_NOTE` / `.note.*`)
Name/type/descriptor triples. Common ones: **build-id** (`.note.gnu.build-id`, a hash identifying the build — used to match separate debug files), **ABI tag** (`.note.ABI-tag`, minimum kernel/OS), and **GNU property** (`.note.gnu.property`, CET IBT/shadow-stack and AArch64 BTI/PAC markers).

## Disambiguating `ET_DYN`: PIE vs Shared Object
Both position-independent **executables** and **shared libraries** are `ET_DYN`. Distinguish them by:
- **`DF_1_PIE`** set in `DT_FLAGS_1` ⇒ PIE (the reliable modern signal).
- **`PT_INTERP` / `.interp` present** ⇒ meant to be executed directly ⇒ PIE.
- A `DT_SONAME` and no interpreter ⇒ shared library.
- `file` reports `pie executable` vs `shared object` accordingly.
