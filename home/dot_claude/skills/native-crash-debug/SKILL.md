---
name: native-crash-debug
description: >
  Apply when debugging a crash, segfault, or bad-access in a compiled binary —
  C, C++, Objective-C, or any native library. Covers systematic isolation,
  backtrace-first methodology, dynamic linker diagnosis on macOS (dyld) and
  Linux (ld.so), and Mach-O / ELF binary inspection. Invoke explicitly with
  /native-crash-debug or when a segfault, SIGABRT, EXC_BAD_ACCESS, or
  missing-symbol crash is the presenting symptom.
---

# Native Crash Debugging

**Starting rule: don't hypothesize before you have a backtrace.**

The surface failure — a segfault, a bad-access, an abort — is not the bug.
It is a symptom. The bug is the cause. Every step before the backtrace is
isolation. Every step after it is evidence-gathering.

---

## Phase 1: Isolate before forming opinions

Strip the environment systematically. Each step eliminates a class of causes.

1. **Disable config**: run with no user configuration (`--no-config`, `--config /dev/null`,
   or equivalent). Rules out crashes caused by a user-supplied option or plugin.
2. **Disable non-essential subsystems**: replace output backends, network, UI, or
   audio/video sinks with null equivalents. Rules out backend-specific crashes.
3. **Substitute a trivial input**: replace the real file/stream with `/dev/null` or a
   known-good minimal fixture. Rules out input-specific crashes.
4. **Confirm library loading**: `DYLD_PRINT_LIBRARIES=1` (macOS) or `LD_DEBUG=libs`
   (Linux) shows which libraries actually load and from where.

If the crash survives all of these, it is structural, not environmental.
**Don't form a hypothesis until you've run at least the first two.**

---

## Phase 2: Get the backtrace — the right way

Use `lldb` (macOS) or `gdb` (Linux). Run the binary under the debugger rather
than attaching after the fact.

```
lldb --batch -s <script> -- <binary> <args>
```

Script:
```
run
bt 30
```

Key reads from the backtrace:

- **Frame #0 is `0x0`**: null function pointer call. The bug is a zero GOT entry,
  a null callback, or an unresolved symbol silently replaced with
  `missing_symbol_abort` (macOS) or a PLT trampoline to NULL.
- **Frame #0 is in a library you don't control**: the crash is in a dependency —
  but the *cause* is almost always in how your code called into it.
- **Only 1–2 frames from your binary above the crash**: the crash happened at the
  very first instruction of whatever was called, suggesting a bad/null function
  pointer rather than a logic error deep in the callee.

If `bt` shows only one frame and `pc = 0x0`, select frame 1 explicitly:
```
frame select 1
disassemble --frame --count 20
register read
```
The disassembly of frame 1 shows the `blr`/`call` instruction that jumped to null.
The register dump shows what value was in the register used for the indirect call.

---

## Phase 3: Diagnose the crash class from the address

Read the crash address literally. It tells you which bug class you're in.

| Crash address | Diagnosis |
|---|---|
| `0x0` | Null pointer call or dereference |
| Small non-zero (`0x8`, `0x10`, `0x18`, ...) | Null struct/object with a field offset |
| Address in `0x18xxxxxxxx` range (macOS) | Likely dyld / system territory — use `image lookup -a` |
| Address matches a known symbol ± small offset | Logic error inside that function |

Always resolve unknown addresses: `image lookup -a <address>` in lldb. An address
that looked like a system library turned out to be `dyld4::missing_symbol_abort` —
a definitive verdict, not a guess.

**ASLR:** addresses from `nm`, disassembly, or the binary's load commands are
compile-time values. At runtime, ASLR slides the binary by an arbitrary offset.
Reading memory at a static address in a live process will read the wrong location.
Always derive runtime addresses from the debugger (`image list` gives the load
address; add it to the file offset) or let the debugger resolve symbols directly.

---

## Phase 4: Dynamic linker diagnosis

"The library is loaded" and "the symbol was resolved from that library" are not
the same claim. A symbol can be bound to `missing_symbol_abort` (macOS) or a
PLT entry that traps (Linux) silently at load time, only failing when the function
is first called.

### macOS

```sh
DYLD_PRINT_BINDINGS=1 <binary> <args> 2>&1 | grep <symbol>
DYLD_PRINT_LIBRARIES=1 <binary> <args> 2>&1 | grep <libname>
```

Anomaly pattern:
```
<binary/bind#N> -> 0x18xxxxxxxx <<none>/_symbol>     # wrong: resolves to dyld or unknown
<libfoo/bind#M> -> 0x1xxxxxxxxx <libbar/_symbol>     # right: resolves to the expected library
```

If the same symbol resolves differently for your binary than for its dependencies,
the bind table records the wrong library ordinal — a **version-skew bug** (see below).

When a symbol looks suspicious, don't grep only for your binary — capture the full
`DYLD_PRINT_BINDINGS` output and look at how other libraries in the same process
bind the same symbol. A correct resolution next to a wrong one makes the anomaly
immediately visible; in isolation, a suspicious address is just a number.

Use `image lookup -a <address>` to name any suspicious address.

### Linux

```sh
LD_DEBUG=bindings <binary> <args> 2>&1 | grep <symbol>
ldd <binary>                   # check loaded libraries and any "not found"
readelf -d <binary> | grep NEEDED   # check declared dependencies
nm -D <binary> | grep <symbol> # check if symbol is undefined (U) or defined
```

---

## Phase 5: Inspect the binary directly when tools fail

High-level tools give partial views. When they don't surface the issue, go one
layer down and read the binary metadata directly.

### macOS Mach-O

A Mach-O binary has three separate bind tables: regular (resolved at load time),
lazy (resolved on first call), and weak. High-level tools like `otool -bind_info`
may only surface a subset. If a symbol appears absent from the bind info, check
all three — the offsets and sizes for each are in the `LC_DYLD_INFO_ONLY` load
command.

The **lazy bind table** records which library ordinal each symbol is expected from:

```python
# parse LC_DYLD_INFO_ONLY lazy_bind_off/lazy_bind_size from the binary
# decode bind opcodes to extract: symbol name → library ordinal
```

If a symbol is attributed to ordinal N, check what library N is:
the load commands list all dylibs in order, matching ordinals.

If a symbol is attributed to library A but should come from library B, this is a
linker artifact: either the build-time version of A re-exported that symbol (and
the current version does not), or the link order was wrong and the linker attributed
it to whichever library it encountered first.

### Linux ELF

```sh
readelf -r <binary>         # relocation table: symbol → library
objdump -d <binary> | grep plt   # PLT stubs
nm -D <dependency.so> | grep <symbol>   # does the library actually export it?
```

---

## Phase 6: Version-skew as a bug class

**Pattern:** Binary built against library version X. Library updated to X+N.
A symbol that X re-exported (or defined) is no longer present in X+N. The binary's
bind table still expects it from the old library. Runtime resolution fails silently;
the first call crashes.

**Diagnosis checklist:**

1. `otool -L <binary>` (macOS) or `ldd <binary>` (Linux): what version was the
   binary built against?
2. Compare against what's installed: `ls /path/to/lib*`
3. `nm <installed_lib.dylib/.so> | grep <symbol>`: does the current library
   actually export the symbol?
4. `nm <installed_lib> | grep "I _symbol"` (macOS): is the symbol a re-export
   (indirect)? Re-exports can appear and disappear across minor versions.

**Fix:** Rebuild the binary against the current library. If the binary came from
a package manager, upgrade or force-reinstall the package — don't patch the
binary or the library in place.

---

## Don't anchor on the obvious suspect

Whatever is most visually striking in the invocation — an unusual filename, a
suspicious flag, an unexpected input format — is usually not the cause of a
structural crash. Shell-escaping bugs produce "file not found" or argument
errors. Format bugs produce decoder errors. A segfault that survives config
stripping and trivial input substitution is structural. Treat surface features
as leads to rule out, not conclusions to reach for.

---

## Toolbox reference

| Task | macOS | Linux |
|---|---|---|
| Backtrace | `lldb --batch -o run -o bt -- <binary>` | `gdb -batch -ex run -ex bt --args <binary>` |
| Resolve address | `image lookup -a <addr>` (in lldb) | `addr2line -e <binary> <addr>` |
| Library loading | `DYLD_PRINT_LIBRARIES=1` | `LD_DEBUG=libs` |
| Symbol binding | `DYLD_PRINT_BINDINGS=1` | `LD_DEBUG=bindings` |
| Binary deps | `otool -L <binary>` | `ldd <binary>` |
| Symbol present? | `nm <lib.dylib> \| grep <sym>` | `nm -D <lib.so> \| grep <sym>` |
| Bind table | parse `LC_DYLD_INFO_ONLY` opcodes | `readelf -r <binary>` |
| Install name | `otool -D <lib.dylib>` | `readelf -d <lib.so> \| grep SONAME` |
