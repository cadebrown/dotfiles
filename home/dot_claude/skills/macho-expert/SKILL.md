---
name: macho-expert
description: Provides expertise for inspecting, analyzing, and modifying Mach-O (Mach Object) binaries — the executable format used by macOS and iOS. Use this skill whenever a Mach-O file is involved, including examining headers, load commands, segments, sections, symbol tables, or code signatures; identifying fat/universal binaries and their slices; assessing binary hardening such as PIE, stack canaries, ARC, encryption, hardened runtime, and entitlements; using otool, nm, objdump, codesign, lipo, or dyld_info; modifying Mach-O files with lipo, install_name_tool, strip, or vtool; or writing and reviewing code that parses Mach-O data. Trigger even on casual phrasing like "what's in this .dylib", "is this Mac app 64-bit", "why won't this binary load", or "extract the arm64 slice", and whenever a file is identified as Mach-O, a .dylib, .bundle, or .framework, an iOS app binary, or a macOS executable.
allowed-tools: Read Bash Grep Glob WebSearch
---

# Overview

This skill provides technical knowledge and expertise about the Mach-O (Mach Object) file format used by Apple platforms (macOS, iOS, iPadOS, watchOS, tvOS), and how to interact with Mach-O files on disk. Tasks include answering questions about the format, inspecting and dumping Mach-O structure (header, load commands, segments, sections, symbol tables, dyld info, code signature), disambiguating thin vs. fat/universal binaries, assessing binary hardening, modifying Mach-O files, and writing/modifying/reviewing code that parses Mach-O data.

This is **static, on-disk analysis**. For runtime debugging use a debugger (lldb); for deep reverse engineering use a dedicated RE tool.

## When to Use This Skill

- Inspecting or explaining Mach-O structure: the header, load commands (`LC_*`), segments (`__TEXT`, `__DATA`, `__LINKEDIT`, …), sections, the symbol table and string table, and the dyld/chained-fixup info.
- Identifying a file's filetype (executable, dylib, bundle, object, core, dSYM companion), CPU type/subtype (x86_64, arm64, arm64e), and whether it is **thin** (single-arch Mach-O) or **fat/universal** (a wrapper containing multiple slices).
- Resolving dynamic-linking questions: which dylibs a binary depends on (`LC_LOAD_DYLIB`), its install name (`LC_ID_DYLIB`), `@rpath`/`@executable_path`/`@loader_path` resolution, two-level namespaces, and the dyld shared cache.
- Assessing binary hardening: PIE, stack canaries, ARC, `__RESTRICT`, encryption (`LC_ENCRYPTION_INFO`), the hardened runtime, code-signing status, and entitlements.
- Inspecting code signatures and entitlements (`codesign`, embedded `LC_CODE_SIGNATURE`).
- Using `otool`, `nm`, `objdump`/`llvm-objdump`, `dyld_info`, `lipo`, `size`, `strings`, `c++filt`/`swift-demangle` to extract information.
- Modifying Mach-O files with `lipo` (split/merge slices), `install_name_tool` (rewrite install names / rpaths), `strip`, `vtool`, or `codesign` (re-sign).
- Writing or reviewing code that parses or manipulates Mach-O data (LIEF, macholib, `goblin`, `object`, Apple's `<mach-o/loader.h>`).

## When NOT to Use This Skill

- **Other binary formats**: For ELF (Linux) use an ELF-focused tool/skill; for PE/COFF (Windows) use a PE tool. `LIEF` and `llvm-objdump` are cross-format if a single tool is required.
- **Runtime / dynamic debugging**: Use `lldb` (and `dtrace`/`fs_usage`/Instruments) for runtime behavior; this skill is for the on-disk file.
- **Deep reverse engineering / decompilation**: Use Ghidra, IDA, Hopper, or Binary Ninja. Use `otool -tV` / `objdump -d` only for light disassembly and dumps.
- **DWARF debug info**: Decoding `.dSYM`/DWARF semantics is a separate concern (`dwarfdump`, `llvm-dwarfdump`). This skill covers locating the segments and the `LC_UUID` linkage, not decoding DWARF.
- **Generating/signing for distribution policy**: Notarization workflow, provisioning profiles, and App Store rules are toolchain/policy topics, not file-format analysis (though inspecting the resulting signature/entitlements *is* in scope).

# Mach-O Format Reference

For the structural reference — the (optional) fat header and slices, the Mach-O header, the load-command stream, segments vs. sections, the LINKEDIT-resident tables (symbols, dyld info / chained fixups, exports, code signature), and how the loader consumes them — see `{baseDir}/reference/format.md`.

For the catalog of load commands (`LC_SEGMENT_64`, `LC_LOAD_DYLIB`, `LC_MAIN`, `LC_DYLD_INFO_ONLY`, `LC_DYLD_CHAINED_FIXUPS`, `LC_CODE_SIGNATURE`, `LC_UUID`, `LC_BUILD_VERSION`, `LC_ENCRYPTION_INFO_64`, etc.) — what each one carries and why it matters — see `{baseDir}/reference/load_commands.md`.

# Authoritative Sources

When precise Mach-O facts are needed (constant values, struct layouts, magic numbers), prefer these over recall:

1. **Apple SDK headers** (ground truth for constants and struct layouts): `<mach-o/loader.h>` (header, segments, every `LC_*` and `struct *_command`), `<mach-o/fat.h>` (`FAT_MAGIC`/`FAT_MAGIC_64`, `fat_header`, `fat_arch`), `<mach-o/nlist.h>` (`struct nlist_64`, `N_*` symbol types), `<mach/machine.h>` (`CPU_TYPE_*`, `CPU_SUBTYPE_*`). On a Mac these live under the active SDK (`xcrun --show-sdk-path`); they are also mirrored in Apple's open-source `dyld` and `xnu` (`cctools`) releases. Read the header rather than guessing a value.
2. **`man` pages**: `Mach-O(5)`, `otool(1)`, `nm(1)`, `lipo(1)`, `install_name_tool(1)`, `codesign(1)`, `dyld(1)`.
3. **LLVM reference implementation**: `llvm/include/llvm/BinaryFormat/MachO.h` (enums/constants) and `llvm/lib/Object/MachOObjectFile.cpp` (parsing) — reliable, cross-checked, and available on Linux.
4. **Apple dyld source**: the `dyld` project (loader semantics, chained fixups, shared cache) and `cctools` (the canonical `otool`/`nm`/`lipo` implementations).

# Inspecting Mach-O Files

Start with the smallest tool that answers the question, escalating only as needed.

## Quick Identification

Use `file <binary>` for a one-line summary — it reports magic, 64/32-bit, CPU type, filetype, and crucially whether the file is a **fat/universal** wrapper and how many slices it has. This is the first command for almost any Mach-O task, because a fat file changes how every later tool must be invoked (most accept `-arch <name>` to select a slice).

## Tool Availability Matters

Mach-O tooling is split across three groups, and what's installed depends on the environment:

- **Native Apple toolchain** (`otool`, `nm`, `lipo`, `install_name_tool`, `codesign`, `vtool`, `dyld_info`, `pagestuff`): present on macOS (with Xcode / Command Line Tools), usually invoked via `xcrun`. The richest option — `otool` and `codesign` are the canonical inspectors. Use these whenever the user is on a Mac.
- **LLVM tools** (`llvm-objdump`, `llvm-nm`, `llvm-otool`, `llvm-lipo`): cross-platform; `llvm-objdump --macho` mirrors most of `otool`. Install via the `llvm` package when on Linux.
- **GNU binutils** (`objdump`, `nm`, `strings`, `size`): often the only thing present on a non-Apple box. GNU `objdump`/`nm` *can* read Mach-O and handle thin-file light disassembly and symbol dumps, but lack Mach-O-specific niceties (load-command pretty-printing, code-signature parsing, fat handling). Adequate for quick looks; not authoritative.

**When the native and LLVM tools are both absent (common on Linux), prefer `LIEF`** (Python/C++, `pip install lief`) for any structural work — it parses headers, all load commands, symbols, dyld info, and signatures, handles fat binaries, and is the most reliable cross-platform route. See the coding reference below.

Always confirm a tool exists before recommending its exact invocation; fall back along the chain above when it doesn't, and tell the user which tools they'd need to install for the richer output.

## otool / llvm-objdump (primary structural dumper)

`otool` (or `llvm-objdump --macho`) is the canonical Mach-O dumper: header (`-h`), load commands (`-l`), specific commands like dylibs (`-L`) and the install name (`-D`), section contents (`-s`), and light disassembly (`-tV`). For the command catalog and equivalents across `otool` / `llvm-objdump` / `objdump`, see `{baseDir}/reference/tools.md`.

## nm / dyld_info / codesign (symbols, bindings, signature)

- **`nm`** (or `llvm-nm`): symbol table — defined/undefined/external symbols. Pipe C++ through `c++filt` and Swift through `swift-demangle`.
- **`dyld_info`** (modern macOS) or `otool`'s dyld flags: rebase/bind/lazy-bind/export opcodes and chained fixups — i.e., what dyld will patch at load.
- **`codesign -dvvv --entitlements :-`**: code-signing identity, hardened-runtime flags, and entitlements (macOS only). On other platforms, parse the `LC_CODE_SIGNATURE` blob with LIEF.

See `{baseDir}/reference/tools.md` for exact flags and cross-tool equivalents.

# Security Hardening Inspection

A frequent Mach-O task is assessing exploit-mitigation and packaging hardening. Each property is detectable from static data — from header flags, the presence/contents of specific load commands, or symbol references.

| Property | What to inspect | Indicates ENABLED / present when |
|----------|-----------------|----------------------------------|
| **PIE** (ASLR for the main executable) | Mach-O header flags (`otool -h`) | `MH_PIE` flag is set. Modern executables set it by default; its absence in a recent executable is notable. |
| **Stack canaries** | Symbols (`nm`) | References to `___stack_chk_fail` / `___stack_chk_guard` are present. |
| **ARC** (Automatic Reference Counting) | Symbols (`nm`) | Objective-C runtime calls like `_objc_release`, `_objc_retainAutoreleasedReturnValue` are present (heuristic). |
| **No heap exec / NX** | Inherent | Apple platforms enforce W^X; there is no per-binary opt-out flag to read. Note the platform guarantee rather than a bit. |
| **Encryption** (FairPlay, iOS) | `LC_ENCRYPTION_INFO[_64]` (`otool -l`) | Load command present with `cryptid != 0` → the named file range is encrypted on disk (App Store iOS binaries). `cryptid == 0` → not encrypted. |
| **Hardened runtime** (macOS) | Code signature flags (`codesign -dvvv`) | The `runtime` flag appears in `CodeDirectory` flags. Pairs with entitlements that selectively re-open capabilities. |
| **Restricted / `__RESTRICT`** | Sections (`otool -l`) | A `__RESTRICT,__restrict` section or the `MH_NO_HEAP_EXECUTION`/`SG_PROTECTED_VERSION_1` markers; restricted binaries ignore `DYLD_*` env injection. |
| **Code signature** | `LC_CODE_SIGNATURE` (`otool -l`) + `codesign -dvvv` | Load command present and a valid `CodeDirectory`; check whether it's ad-hoc, Developer ID, or App Store, and whether it's a deep/secure-timestamped signature. |
| **Library validation / entitlements** | Entitlements (`codesign --entitlements :-`) | Inspect for `com.apple.security.*` keys (sandbox, library-validation, `get-task-allow` = debuggable, JIT, etc.). `get-task-allow=true` on a shipping build is a red flag. |

If `codesign`/`otool` aren't available (non-macOS), derive the load-command-based rows from `LIEF` (it exposes header flags, `LC_ENCRYPTION_INFO`, and the code-signature blob) and the symbol-based rows from `nm`/`llvm-nm`.

# Modifying Mach-O Files

For changing Mach-O contents, prefer purpose-built tools over hand-editing bytes (which corrupts offsets, the `__LINKEDIT` layout, and invalidates the signature):

- **`lipo`** (or `llvm-lipo`): split a fat binary into thin slices (`-thin <arch> -output …`), extract/remove an arch, or create a universal binary from thins (`-create`). The first tool to reach for when a task targets one architecture inside a universal file.
- **`install_name_tool`**: rewrite a dylib's install name (`-id`), change a recorded dependency path (`-change old new`), or add/delete/rewrite `LC_RPATH` entries (`-add_rpath`/`-delete_rpath`/`-rpath`).
- **`strip`**: remove symbols/debug info (Mach-O variant; `-S` strips debug, `-x` local symbols).
- **`vtool`**: read or set platform/min-OS/SDK version load commands (`LC_BUILD_VERSION`).
- **Re-signing**: any content change invalidates `LC_CODE_SIGNATURE`. After modifying, re-sign with `codesign -s <identity> --force` (or ad-hoc `-s -`), or the binary will fail to load on a Mac with code-signing enforcement.

See `{baseDir}/reference/tools.md` for exact invocations. For programmatic structural edits, `LIEF` can add/remove load commands and rewrite the binary.

# Working With Code

This skill supports writing, modifying, and reviewing code that parses or manipulates Mach-O data — both from-scratch parsers (reading `mach_header_64`, walking `ncmds` load commands by `cmdsize`, handling fat wrappers and byte order) and library-backed code (LIEF, macholib, goblin, the Go `debug/macho` package, Apple's `<mach-o/loader.h>`). See `{baseDir}/reference/coding.md`, which includes a ready-to-run LIEF triage script.

# Choosing Your Approach

```
┌─ Need a one-line identification (thin/fat, 32/64-bit, CPU, filetype)?
│   └─ Use `file <binary>`   (do this first — it tells you if you must select a slice)
├─ File is fat/universal and you care about one arch?
│   └─ Use `lipo -info` / `lipo -thin <arch>`; pass `-arch <arch>` to later tools
├─ Need to explain or recall the Mach-O format/load commands?
│   └─ See {baseDir}/reference/format.md and {baseDir}/reference/load_commands.md;
│      verify values against <mach-o/loader.h> or LLVM's MachO.h
├─ Need to assess hardening (PIE/canary/ARC/encryption/hardened-runtime/signature)?
│   └─ Use the Security Hardening table above + otool/codesign (or LIEF if on non-macOS)
├─ Need Mach-O structure (header/load commands/segments/sections/dylibs/dyld info)?
│   └─ Use `otool -hl…` or `llvm-objdump --macho`; on bare Linux use LIEF
│      ({baseDir}/reference/tools.md)
├─ Need symbols / bindings / exports?
│   └─ Use `nm` (+ c++filt/swift-demangle) and `dyld_info` ({baseDir}/reference/tools.md)
├─ Need code-signature / entitlements detail?
│   └─ Use `codesign -dvvv --entitlements :-` (macOS) or parse LC_CODE_SIGNATURE via LIEF
├─ Need disassembly or raw section content?
│   └─ Use `otool -tV` / `objdump -d`; for deep RE use Ghidra/IDA/Hopper/rizin
├─ Need to modify a Mach-O (lipo/install_name_tool/strip/vtool)?
│   └─ See {baseDir}/reference/tools.md — and re-sign afterward
└─ Need to write, modify, or review code that parses/manipulates Mach-O data?
    └─ See {baseDir}/reference/coding.md
```
