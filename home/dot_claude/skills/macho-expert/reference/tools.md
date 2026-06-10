# Tools Reference

Command-line recipes for inspecting and modifying Mach-O, with equivalents across the native Apple toolchain (`otool`/`nm`/`lipo`/…), LLVM (`llvm-*`), and GNU binutils. **Always confirm a tool is installed before using its exact flags**; if the native and LLVM tools are absent (typical on Linux), use `LIEF` (see `coding.md`).

On macOS, prefix native tools with `xcrun` if they aren't on `PATH` (e.g. `xcrun otool …`). For a **fat/universal** file, add `-arch <name>` to most inspectors to pick a slice (`otool`, `nm`, `size`), or split first with `lipo -thin`.

## Table of Contents
- [Identify](#identify)
- [Header & load commands](#header--load-commands)
- [Dependencies & install names](#dependencies--install-names)
- [Symbols](#symbols)
- [Dyld info / bindings / exports](#dyld-info--bindings--exports)
- [Section contents & disassembly](#section-contents--disassembly)
- [Code signature & entitlements](#code-signature--entitlements)
- [Sizes & strings](#sizes--strings)
- [Modifying](#modifying)
- [Demangling](#demangling)

## Identify

| Goal | Command |
|------|---------|
| One-line summary (thin/fat, bits, CPU, type) | `file <bin>` |
| List slices in a fat file | `lipo -info <bin>` (native/`llvm-lipo`); else `file <bin>` |
| Detailed per-slice arch info | `lipo -detailed_info <bin>` |

## Header & load commands

| Goal | otool (native) | llvm-objdump | GNU objdump |
|------|----------------|--------------|-------------|
| Mach header (flags incl. `MH_PIE`) | `otool -h <bin>` | `llvm-objdump --macho -h <bin>` | `objdump -f <bin>` (limited) |
| All load commands | `otool -l <bin>` | `llvm-objdump --macho -l <bin>` / `--all-headers` | — (use LIEF) |
| Just segments/sections | `otool -l <bin>` (read `LC_SEGMENT_64`) | `llvm-objdump --macho --section-headers <bin>` | `objdump -h <bin>` |

`otool -l` is the workhorse for the full load-command stream. To find one command type, pipe through `grep -A` (e.g. `otool -l bin | grep -A4 LC_ENCRYPTION`).

## Dependencies & install names

| Goal | Command |
|------|---------|
| Dependencies (`LC_LOAD_DYLIB` list) | `otool -L <bin>` (or `llvm-objdump --macho -L`) |
| Install name of a dylib (`LC_ID_DYLIB`) | `otool -D <dylib>` |
| `LC_RPATH` entries | `otool -l <bin> | grep -A2 LC_RPATH` |

## Symbols

| Goal | nm (native/llvm-nm) | GNU nm |
|------|---------------------|--------|
| All symbols | `nm <bin>` | `nm <bin>` |
| Undefined (imports) only | `nm -u <bin>` | `nm -u <bin>` |
| Defined external (exports) | `nm -gU <bin>` | `nm --defined-only -g <bin>` |
| With addresses, sorted | `nm -n <bin>` | `nm -n <bin>` |
| Indirect symbol table (stubs) | `otool -I <bin>` | — |

Pipe through a demangler for readable names (see below). Hardening heuristics live here too: `nm <bin> | grep stack_chk` (canaries), `nm <bin> | grep objc_release` (ARC).

## Dyld info / bindings / exports

| Goal | Command |
|------|---------|
| Modern: rebases/binds/fixups/exports | `dyld_info -fixups -exports <bin>` (recent macOS) |
| Classic: dyld opcode streams | `otool -bind -lazy_bind -rebase -export <bin>` (flag names vary by version) |
| Exported symbols | `dyld_info -exports <bin>` or `nm -gU <bin>` |
| Which scheme is in use | `otool -l <bin> | grep -E 'LC_DYLD_INFO|LC_DYLD_CHAINED_FIXUPS'` |

## Section contents & disassembly

| Goal | otool | llvm-objdump | GNU objdump |
|------|-------|--------------|-------------|
| Hex dump a section | `otool -s __TEXT __cstring <bin>` | `llvm-objdump --macho -s --section=__TEXT,__cstring <bin>` | `objdump -s -j __TEXT.__cstring <bin>` |
| Disassemble `__text` | `otool -tV <bin>` | `llvm-objdump -d --macho <bin>` | `objdump -d <bin>` |
| Objective-C metadata | `otool -ov <bin>` | `llvm-objdump --macho --objc-meta-data <bin>` | — |

For anything past light disassembly, use Ghidra/IDA/Hopper/rizin instead.

## Code signature & entitlements

macOS only (these read the live signature):

| Goal | Command |
|------|---------|
| Signing identity + CodeDirectory flags (hardened runtime, etc.) | `codesign -dvvv <bin>` |
| Entitlements (XML) | `codesign -d --entitlements :- <bin>` |
| Verify signature validity | `codesign --verify --verbose <bin>` |
| Requirements | `codesign -d -r- <bin>` |

Off-macOS, locate `LC_CODE_SIGNATURE` (`otool -l` / LIEF) and parse the `SuperBlob` with LIEF (`binary.code_signature`).

## Sizes & strings

| Goal | Command |
|------|---------|
| Per-segment/section sizes | `size -m <bin>` (native) / `llvm-size -m <bin>` |
| Printable strings | `strings -a <bin>` (consider `-arch` / slice first) |

## Modifying

Re-sign after **any** content change (`codesign -s - --force <bin>` for ad-hoc), or the file won't load under enforcement.

| Goal | Command |
|------|---------|
| Extract one arch from a fat file | `lipo <fat> -thin arm64 -output <thin>` |
| Remove an arch | `lipo <fat> -remove x86_64 -output <out>` |
| Build a universal binary | `lipo -create a.thin b.thin -output <fat>` |
| Change a dylib's own install name | `install_name_tool -id @rpath/Foo.dylib <dylib>` |
| Repoint a dependency path | `install_name_tool -change old.dylib new.dylib <bin>` |
| Add / delete an rpath | `install_name_tool -add_rpath @loader_path/../Frameworks <bin>` / `-delete_rpath <path> <bin>` |
| Strip debug symbols | `strip -S <bin>` |
| Strip local symbols | `strip -x <bin>` |
| Read/set platform & min-OS | `vtool -show <bin>` / `vtool -set-build-version …` |
| Re-sign (ad-hoc) | `codesign -s - --force <bin>` |

## Demangling

| Source | Command |
|--------|---------|
| C++ | `… | c++filt` (or `llvm-cxxfilt`) |
| Swift | `… | swift-demangle` (or `xcrun swift-demangle`) |
