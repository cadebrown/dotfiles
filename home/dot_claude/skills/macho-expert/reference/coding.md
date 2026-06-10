# Working With Mach-O in Code

Guidance for writing, modifying, and reviewing code that parses or manipulates Mach-O — both library-backed and from-scratch.

## Pick a library before hand-rolling

Hand-written Mach-O parsers are easy to get subtly wrong (fat byte-order, `cmdsize` advancement, 32/64 struct selection, LINKEDIT offset math). Prefer a maintained library unless the task is specifically to *write* a parser:

| Library | Language | Notes |
|---------|----------|-------|
| **LIEF** | Python / C++ / Rust | Most capable cross-platform; full read **and** write (add/remove load commands, rebuild). Handles fat binaries and code signatures. `pip install lief`. Recommended default off-macOS. |
| **macholib** | Python | Lightweight, pure-Python read/limited-write; long used by py2app. `pip install macholib`. |
| **goblin** | Rust | Fast multi-format (Mach-O/ELF/PE) parser. |
| `debug/macho` | Go | Standard library; clean read-only API. |
| LLVM `object` | C++ | `llvm::object::MachOObjectFile`; authoritative semantics. |
| `<mach-o/loader.h>` + mmap | C | Apple's own structs; for native tools or when you must match the SDK exactly. |

## Ready-to-run triage script (LIEF)

`{baseDir}/scripts/macho_triage.py` is a validated, dependency-light script that prints identity, load-command highlights, dependencies/rpaths, the fixup scheme, encryption/signature status, and symbol-based hardening signals — iterating every slice of a fat binary.

```bash
pip install lief            # if not already present
python3 {baseDir}/scripts/macho_triage.py <file> [arch-substring]
```

Use it as a first pass, or as a template to extend (it shows the correct LIEF idioms: `lief.MachO.parse()` returns a `FatBinary` you iterate for slices; the install name comes from the `LC_ID_DYLIB` command, not a top-level attribute; load-command types are matched via `lief.MachO.LoadCommand.TYPE`). LIEF's API surface shifts between versions — if an attribute is missing, introspect with `dir(lief.MachO.Binary)` / `dir(lief.MachO.Header)` rather than assuming a name.

## Writing a from-scratch parser — the things that bite

If the task is to write a parser (no library), get these right:

1. **Read the magic first; it dictates layout and endianness.**
   - `0xFEEDFACF` / `0xFEEDFACE` → thin 64/32-bit, host-endian struct fields.
   - the `CIGAM` byte-swaps → opposite endianness (swap every multi-byte field).
   - `0xCAFEBABE` / `0xCAFEBABF` → **fat** wrapper, and its `fat_header`/`fat_arch` fields are **big-endian** regardless of slice endianness. Parse the wrapper, then recurse into each slice at its `offset`.
2. **Walk load commands by `cmdsize`, not by struct size.** Read `cmd`/`cmdsize`, switch on `cmd`, then advance the cursor by exactly `cmdsize`. A command's body may be larger than the fixed struct (trailing strings, inline sections). Bound the walk by both `ncmds` and `sizeofcmds`, and reject `cmdsize == 0` or overruns.
3. **Sections live inside the segment command.** After a `segment_command_64`, read `nsects` × `section_64` from the bytes immediately following — they are *not* separate load commands.
4. **String references are offsets.** Dylib names, rpaths, and dylinker paths are `lc_str` unions giving a byte offset from the start of *their own* load command; read until NUL, staying within `cmdsize`.
5. **`__LINKEDIT` is offset-addressed.** `LC_SYMTAB`, `LC_DYLD_INFO*`, `LC_DYLD_CHAINED_FIXUPS`, `LC_CODE_SIGNATURE`, etc. point into the file by absolute file offset; validate they fall within the file (and, for a slice, within that slice's range).
6. **Symbol entries are `nlist_64`.** `n_strx` indexes the string table from `LC_SYMTAB`; `n_type` encodes `N_STAB`/`N_TYPE`/`N_EXT` bits; `n_sect` is 1-based (`NO_SECT` = 0).
7. **Validate, don't trust.** Hostile or corrupt files lie about sizes/offsets. Bounds-check every offset+length against the mapped region before dereferencing.

## Code-review checklist

When reviewing someone's Mach-O code, look specifically for:
- Missing fat-wrapper handling, or assuming little-endian for the fat header.
- Advancing the load-command cursor by `sizeof(struct)` instead of `cmdsize`.
- Treating sections as load commands, or ignoring `nsects`.
- Unbounded reads from `n_strx` / `lc_str` offsets (no string-table bound check).
- Conflating the two fixup schemes (classic `LC_DYLD_INFO` vs. `LC_DYLD_CHAINED_FIXUPS`) — code should detect which is present.
- Editing bytes in place without invalidating/refreshing the code signature (the result won't load under enforcement).
- 32-bit assumptions (`mach_header` vs `mach_header_64`, `nlist` vs `nlist_64`) on a 64-bit file, or vice versa.
