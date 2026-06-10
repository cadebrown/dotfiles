# Load Command Catalog

The load commands that matter most when analyzing a Mach-O, grouped by purpose. Each entry: the `LC_*` tag, the struct it uses, and what it tells you. Verify exact constant values and field layouts against `<mach-o/loader.h>` (or LLVM's `MachO.h`) — this is a reading guide, not a substitute for the header.

A few tags carry the `LC_REQ_DYLD` high bit (`0x80000000`), meaning dyld must understand them or refuse to load (e.g. `LC_MAIN`, `LC_DYLD_INFO_ONLY`, `LC_DYLD_CHAINED_FIXUPS`, `LC_LOAD_WEAK_DYLIB`, `LC_RPATH`, `LC_REEXPORT_DYLIB`).

## Mapping & layout

| LC | Struct | Tells you |
|----|--------|-----------|
| `LC_SEGMENT_64` / `LC_SEGMENT` | `segment_command_64` | A region to map: name, VM addr/size, file off/size, `initprot`/`maxprot`, and the count of sections that follow inline. The backbone of the file. |
| `LC_UUID` | `uuid_command` | A unique 128-bit build ID. Links a binary to its `.dSYM` (must match) and to crash reports/symbolication. |
| `LC_BUILD_VERSION` | `build_version_command` | Target **platform** (macOS/iOS/tvOS/…/simulator/Catalyst), minimum OS, and SDK version, plus build tool versions. Replaces the older `LC_VERSION_MIN_*`. |
| `LC_VERSION_MIN_MACOSX` / `_IPHONEOS` / … | `version_min_command` | Legacy min-OS/SDK (pre-`LC_BUILD_VERSION` binaries). |
| `LC_SOURCE_VERSION` | `source_version_command` | The source version the binary was built from. |
| `LC_NOTE` | `note_command` | A named arbitrary data region (used for embedded metadata, e.g. in core files). |

## Entry point & threads

| LC | Struct | Tells you |
|----|--------|-----------|
| `LC_MAIN` | `entry_point_command` | The entry point as a **file offset** (`entryoff`) plus initial stack size. Modern executables. |
| `LC_UNIXTHREAD` | `thread_command` | Initial register/thread state including the entry PC. Older executables (and the mechanism `dyld` itself uses). If you see this instead of `LC_MAIN`, the binary is older or special. |

## Dynamic linking — dependencies & identity

| LC | Struct | Tells you |
|----|--------|-----------|
| `LC_LOAD_DYLIB` | `dylib_command` | A required dynamic library: its install path (often `@rpath/…`) and compatibility/current version. The list of these = the binary's direct dependencies (`otool -L`). |
| `LC_LOAD_WEAK_DYLIB` | `dylib_command` | A weakly-linked dependency: allowed to be missing at runtime (symbols resolve to null). |
| `LC_REEXPORT_DYLIB` | `dylib_command` | A dependency whose symbols this library re-exports as its own (umbrella frameworks). |
| `LC_LOAD_UPWARD_DYLIB` | `dylib_command` | An upward dependency, permitting a controlled dependency cycle. |
| `LC_ID_DYLIB` | `dylib_command` | **Only in a dylib**: the library's own install name — the path consumers will record. `install_name_tool -id` rewrites it. |
| `LC_LOAD_DYLINKER` | `dylinker_command` | Path to the dynamic linker (normally `/usr/lib/dyld`). |
| `LC_ID_DYLINKER` | `dylinker_command` | dyld's own identifying path (only in dyld). |
| `LC_RPATH` | `rpath_command` | One runtime search path used to resolve `@rpath/…` install names. Multiple `LC_RPATH`s form the search list; `install_name_tool -add_rpath/-delete_rpath` edits them. |
| `LC_SUB_FRAMEWORK` / `LC_SUB_UMBRELLA` / `LC_SUB_CLIENT` / `LC_SUB_LIBRARY` | various | Umbrella-framework relationships controlling who may link a sub-component. |

`@rpath`, `@executable_path`, and `@loader_path` are the three special prefixes a recorded path may use; resolution of `@rpath` depends on the `LC_RPATH` list, while the other two are relative to the main executable and the loading binary respectively.

## Dynamic linking — fixups, symbols, exports

A file uses **either** the classic compressed info **or** the newer chained fixups — recognizing which is key.

| LC | Struct | Tells you |
|----|--------|-----------|
| `LC_DYLD_INFO_ONLY` (or `LC_DYLD_INFO`) | `dyld_info_command` | Classic scheme: offsets/sizes of the rebase, bind, weak-bind, lazy-bind, and export opcode streams in `__LINKEDIT`. `_ONLY` means dyld can rely on it exclusively. |
| `LC_DYLD_CHAINED_FIXUPS` | `linkedit_data_command` | Modern scheme: chained-fixup header describing rebases/binds as in-place pointer chains. Newer OS versions. |
| `LC_DYLD_EXPORTS_TRIE` | `linkedit_data_command` | Modern exported-symbol trie (pairs with chained fixups). |
| `LC_SYMTAB` | `symtab_command` | The symbol table: offset/count of `nlist_64` entries and the string table. Foundation for `nm`. |
| `LC_DYSYMTAB` | `dysymtab_command` | Index ranges splitting symbols into local / external-defined / undefined, plus the indirect symbol table backing stubs and the table of contents for libraries. |
| `LC_TWOLEVEL_HINTS` | `twolevel_hints_command` | Hints for the two-level namespace (which dylib defines each undefined symbol). |
| `LC_FUNCTION_STARTS` | `linkedit_data_command` | Compressed list of function entry offsets. |
| `LC_DATA_IN_CODE` | `linkedit_data_command` | Ranges inside `__text` that are data (jump tables, constants) — so disassemblers don't mis-decode them. |

## Security & signing

| LC | Struct | Tells you |
|----|--------|-----------|
| `LC_CODE_SIGNATURE` | `linkedit_data_command` | Offset/size of the embedded signature `SuperBlob` (CodeDirectory + requirements + entitlements + CMS). Its presence means the file is (or was) signed; validate with `codesign`. |
| `LC_ENCRYPTION_INFO_64` / `LC_ENCRYPTION_INFO` | `encryption_info_command_64` | FairPlay encryption descriptor: `cryptoff`/`cryptsize`/`cryptid`. `cryptid != 0` ⇒ that file range is encrypted (App Store iOS binaries); you cannot statically read the encrypted code without a decrypted dump. |
| `LC_SEGMENT_SPLIT_INFO` | `linkedit_data_command` | Info enabling the shared-cache builder to split/relocate segments. |
| `LC_LINKER_OPTION` | `linker_option_command` | Auto-linking hints embedded by the compiler (`-l`/`-framework`) — present in objects. |

## Quick reasoning rules

- **No `LC_MAIN` and no `LC_UNIXTHREAD`** ⇒ not a standalone executable (it's a dylib/bundle/object). A dylib has `LC_ID_DYLIB` instead.
- **`LC_DYLD_CHAINED_FIXUPS` present** ⇒ modern binary; reason about chained fixups, not lazy/non-lazy pointer binding.
- **`LC_ENCRYPTION_INFO*` with `cryptid != 0`** ⇒ encrypted iOS App Store binary; static code analysis needs a decrypted copy.
- **No `LC_CODE_SIGNATURE`** ⇒ unsigned; it will be killed on enforced platforms (or run only ad-hoc/locally).
- **`LC_BUILD_VERSION` platform = `*SIMULATOR`** ⇒ a simulator build, not a device/Mac build.
