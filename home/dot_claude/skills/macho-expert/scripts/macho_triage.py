#!/usr/bin/env python3
"""Triage a Mach-O (or fat/universal) binary with LIEF: identity, load-command
highlights, dependencies, and quick hardening signals.

Usage:  macho_triage.py <file> [arch-substring]
Needs:  pip install lief
"""
import sys, lief

LC = lief.MachO.LoadCommand.TYPE


def _name(enum) -> str:
    return str(enum).split(".")[-1]


def summarize(b) -> None:
    h = b.header
    flags = ",".join(_name(f) for f in h.flags_list) or "(none)"
    print(f"  cpu={_name(h.cpu_type)} subtype={h.cpu_subtype} type={_name(h.file_type)}")
    print(f"  ncmds={h.nb_cmds} flags={flags}")
    print(f"  PIE={'yes' if b.is_pie else 'no'}  NX-heap={'yes' if b.has_nx_heap else 'no'}")

    if b.has_entrypoint:
        print(f"  entrypoint(file offset)={hex(b.entrypoint)}")

    # Install name lives in the LC_ID_DYLIB command (dylibs only).
    for c in b.commands:
        if c.command == LC.ID_DYLIB:
            print(f"  install name (LC_ID_DYLIB)={c.name}")
            break

    libs = [c.name for c in b.libraries]
    if libs:
        print(f"  dependencies ({len(libs)}):")
        for n in libs:
            print(f"    - {n}")
    for c in b.commands:
        if c.command == LC.RPATH:
            print(f"  LC_RPATH: {c.path}")

    cmds = {_name(c.command) for c in b.commands}
    if "DYLD_CHAINED_FIXUPS" in cmds:
        print("  fixups: chained (modern)")
    elif {"DYLD_INFO", "DYLD_INFO_ONLY"} & cmds:
        print("  fixups: classic dyld_info")

    if b.has_encryption_info and b.encryption_info.crypt_id != 0:
        ei = b.encryption_info
        print(f"  ENCRYPTED: cryptid={ei.crypt_id} off={hex(ei.crypt_offset)} size={ei.crypt_size}")
    print(f"  code signature: {'present' if b.has_code_signature else 'ABSENT'}")

    names = {s.name for s in b.symbols}
    canary = any("stack_chk" in n for n in names)
    arc = any(("objc_release" in n) or ("objc_retain" in n) for n in names)
    print(f"  stack canaries: {'likely' if canary else 'not seen'}; "
          f"ARC: {'likely' if arc else 'not seen'}")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    want = sys.argv[2].lower() if len(sys.argv) > 2 else None

    fat = lief.MachO.parse(path)          # FatBinary: 1 slice for thin, N for universal
    if fat is None:
        print(f"not a Mach-O: {path}")
        return 1

    print(f"{path}: {fat.size} slice(s)")
    for b in fat:
        arch = _name(b.header.cpu_type)
        if want and want not in arch.lower():
            continue
        print(f"\n=== slice: {arch} ===")
        summarize(b)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
