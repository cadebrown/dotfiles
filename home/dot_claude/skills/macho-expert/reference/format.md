# Mach-O Format Reference

The on-disk anatomy of a Mach-O file, top to bottom, and how the dynamic loader (dyld) consumes it.

## Table of Contents
- [The fat/universal wrapper (optional outer layer)](#the-fatuniversal-wrapper)
- [The Mach-O header](#the-mach-o-header)
- [The load-command stream](#the-load-command-stream)
- [Segments vs. sections](#segments-vs-sections)
- [The standard segments](#the-standard-segments)
- [LINKEDIT-resident tables](#linkedit-resident-tables)
- [How dyld loads a Mach-O](#how-dyld-loads-a-mach-o)
- [Byte order and 32 vs. 64-bit](#byte-order-and-32-vs-64-bit)

## The fat/universal wrapper

A "universal" (a.k.a. "fat") binary is **not** itself a Mach-O — it is a thin container that concatenates several complete Mach-O files ("slices"), one per architecture, so a single file runs on multiple CPUs. Layout:

- `struct fat_header`: `magic` (`FAT_MAGIC` `0xCAFEBABE`, or `FAT_MAGIC_64` `0xCAFEBABF`) **stored big-endian**, and `nfat_arch` (slice count).
- `nfat_arch` × `struct fat_arch[_64]`: each gives `cputype`, `cpusubtype`, `offset` (where that slice's Mach-O begins in the file), `size`, and `align`.

Consequences for analysis:
- `file` reports the wrapper and lists slices. Most tools accept `-arch <name>` to operate on one slice; `lipo -thin <arch>` extracts a slice to its own file.
- The magic is **byte-swapped relative to the host** (it is defined big-endian), which is how loaders tell a fat file apart from a thin little-endian Mach-O at offset 0.
- Don't confuse `FAT_MAGIC` (`CAFEBABE`) with Java class files, which share that 32-bit value — disambiguate by structure/context.

A thin file has no wrapper; the Mach-O header sits at offset 0.

## The Mach-O header

`struct mach_header_64` (the 32-bit `mach_header` drops `reserved`):

| Field | Meaning |
|-------|---------|
| `magic` | `MH_MAGIC_64` `0xFEEDFACF` (64-bit) or `MH_MAGIC` `0xFEEDFACE` (32-bit). The `*_CIGAM` variants are the byte-swapped (opposite-endian) forms. |
| `cputype` / `cpusubtype` | Target CPU, e.g. `CPU_TYPE_X86_64`, `CPU_TYPE_ARM64`; subtype distinguishes e.g. `arm64e` (pointer-auth) from `arm64`. |
| `filetype` | What the file *is* — see table below. |
| `ncmds` / `sizeofcmds` | Number of load commands and their total byte size. |
| `flags` | `MH_*` bit flags: `MH_PIE`, `MH_TWOLEVEL`, `MH_DYLDLINK`, `MH_NO_HEAP_EXECUTION`, `MH_WEAK_DEFINES`, `MH_BINDS_TO_WEAK`, etc. |

Common `filetype` values:

| Constant | File |
|----------|------|
| `MH_EXECUTE` | a runnable program |
| `MH_DYLIB` | a dynamic library (`.dylib`, or the binary inside a `.framework`) |
| `MH_BUNDLE` | a plug-in / loadable bundle (`.bundle`, many `.so` on macOS) |
| `MH_OBJECT` | a relocatable object (`.o`) |
| `MH_DYLINKER` | the dynamic linker itself (`dyld`) |
| `MH_CORE` | a core dump |
| `MH_DSYM` | a companion file holding debug info (inside `.dSYM`) |
| `MH_KEXT_BUNDLE` | a kernel extension |

## The load-command stream

Immediately after the header come `ncmds` **load commands**, packed back-to-back over `sizeofcmds` bytes. Every command starts with the same two fields:

- `cmd` — the `LC_*` type tag.
- `cmdsize` — the size of *this* command in bytes (8-byte aligned on 64-bit).

To walk them you read `cmd`/`cmdsize`, interpret the body according to `cmd`, then advance by `cmdsize` — repeating `ncmds` times. The stream is the table of contents for everything else: it declares the segments to map, the libraries to load, where the entry point is, where the symbol table and dyld info live, the code signature, the UUID, and the platform/version. The catalog of individual commands is in `load_commands.md`.

## Segments vs. sections

Mach-O has a **two-level** content model (distinct from ELF's parallel section/segment views):

- A **segment** (`LC_SEGMENT_64` → `struct segment_command_64`) is the unit the loader maps into memory. It has a name (`__TEXT`), a virtual address + size (`vmaddr`/`vmsize`), a file offset + size (`fileoff`/`filesize`), and memory protections (`initprot`/`maxprot`, e.g. `__TEXT` is `r-x`, `__DATA` is `rw-`).
- Each segment **contains zero or more sections** (`struct section_64`), described inline right after the segment command. A section has a name (`__text`), its parent segment name (`__TEXT`), an address, size, file offset, alignment, and a `flags`/type (e.g. `S_CSTRING_LITERALS`, `S_MOD_INIT_FUNC_POINTERS`, `S_SYMBOL_STUBS`).

Sections are named `SEGMENT,section`, e.g. `__TEXT,__text` (code), `__TEXT,__cstring` (C strings), `__DATA,__data`, `__DATA_CONST,__got`.

## The standard segments

| Segment | Typical protection | Holds |
|---------|--------------------|-------|
| `__PAGEZERO` | none (no access) | A large unmapped guard region at VA 0 to trap null derefs; no file content. |
| `__TEXT` | `r-x` | Code (`__text`), read-only literals (`__cstring`, `__const`), stubs, unwind info. |
| `__DATA_CONST` | `rw-` then made read-only | Pointers fixed up at load (GOT, const data), hardened against later writes. |
| `__DATA` | `rw-` | Mutable globals, lazy/non-lazy pointers, Objective-C metadata. |
| `__LINKEDIT` | `r--` | Loader metadata not mapped as code/data: symbol & string tables, dyld opcodes/fixups, exports, function starts, the code signature. |

## LINKEDIT-resident tables

`__LINKEDIT` is referenced by *file offset* through several load commands; the data itself is pooled at the end of the file:

- **Symbol table** — `LC_SYMTAB` points at an array of `struct nlist_64` plus a string table. `LC_DYSYMTAB` partitions those symbols into local / external-defined / undefined ranges and holds the indirect-symbol table (used by stubs).
- **Dyld fixups** — either the classic `LC_DYLD_INFO[_ONLY]` (compressed rebase/bind/weak-bind/lazy-bind/export *opcode* streams) **or**, on newer binaries, `LC_DYLD_CHAINED_FIXUPS` + `LC_DYLD_EXPORTS_TRIE`. A given file uses one scheme or the other; recognizing which is essential when reasoning about what dyld patches.
- **Function starts** — `LC_FUNCTION_STARTS`: a compressed list of function entry offsets (used by tools and the unwinder).
- **Code signature** — `LC_CODE_SIGNATURE`: a `SuperBlob` (CodeDirectory with per-page hashes, requirements, entitlements, CMS signature) covering the rest of the file.

## How dyld loads a Mach-O

1. If fat, dyld selects the slice whose `cputype/cpusubtype` matches the host and seeks to that offset.
2. It reads the header and walks the load commands.
3. For each `LC_SEGMENT_64` it `mmap`s `[fileoff, fileoff+filesize)` at `vmaddr` (slid by the ASLR slide for PIE images) with `initprot`; `__PAGEZERO` is left unmapped.
4. It records dependencies from `LC_LOAD_DYLIB`/`LC_LOAD_WEAK_DYLIB`/`LC_REEXPORT_DYLIB`, resolving `@rpath`/`@executable_path`/`@loader_path` against `LC_RPATH` entries, and loads them (often from the **dyld shared cache** rather than disk).
5. It applies fixups (rebases for the slide, binds for imports) from the dyld-info/chained-fixups data; with `__DATA_CONST`, those pages are then re-protected read-only.
6. It runs initializers (`LC_*` init sections / module init), then transfers control to the entry point named by `LC_MAIN` (`entryoff`) — or, on older binaries, the thread state in `LC_UNIXTHREAD`.

The code signature is validated by the kernel as pages fault in; an invalidated signature (e.g. after editing bytes without re-signing) causes a load failure under enforcement.

## Byte order and 32 vs. 64-bit

- **Magic disambiguates everything.** `FEEDFACF`/`FEEDFACE` = thin Mach-O (64/32-bit); their `CIGAM` byte-swaps = opposite endianness; `CAFEBABE`/`CAFEBABF` (big-endian) = fat wrapper. A parser must read the magic first and pick struct layout + byte order accordingly.
- Modern Apple targets are little-endian (`x86_64`, `arm64`). Big-endian Mach-O exists historically (PowerPC); handle it in robust parsers but don't expect it in current files.
- 64-bit uses `mach_header_64`, `segment_command_64` (`LC_SEGMENT_64`), `section_64`, `nlist_64`; the 32-bit structs are the analogous narrower forms (`LC_SEGMENT`, `section`, `nlist`).
