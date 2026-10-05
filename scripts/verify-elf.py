#!/usr/bin/env python3
import struct
import sys
from pathlib import Path

EM_ARM = 40
ET_EXEC = 2
ET_DYN = 3

if len(sys.argv) < 2:
    raise SystemExit("usage: verify-elf.py FILE...")

for name in sys.argv[1:]:
    p = Path(name)
    b = p.read_bytes()[:64]
    if len(b) < 20 or b[:4] != b"\x7fELF":
        raise SystemExit(f"ERROR: {p} is not ELF")
    elf_class = b[4]
    endian = b[5]
    if elf_class != 1:
        raise SystemExit(f"ERROR: {p}: expected ELF32, got class {elf_class}")
    if endian != 1:
        raise SystemExit(f"ERROR: {p}: expected little-endian ELF")
    e_type, e_machine = struct.unpack_from("<HH", b, 16)
    if e_machine != EM_ARM:
        raise SystemExit(f"ERROR: {p}: expected EM_ARM(40), got {e_machine}")
    if e_type not in (ET_EXEC, ET_DYN):
        raise SystemExit(f"ERROR: {p}: unexpected ELF e_type={e_type}")
    print(f"OK ELF: {p.name}: ELF32 little-endian ARM, e_type={e_type}")
