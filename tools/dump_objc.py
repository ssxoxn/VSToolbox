#!/usr/bin/env python3
"""Dump class/method name trong 1 Mach-O (doc thang tu section __objc_classname / __objc_methname).

  python tools/dump_objc.py <binary> --out-dir work
  python tools/dump_objc.py <binary> --classes "Layer|Code" --methods "import|photo"
"""
from __future__ import annotations

import argparse
import re
import struct
import sys

LC_SEGMENT_64 = 0x19
LC_SEGMENT = 0x1


def slices(data: bytes):
    magic = struct.unpack_from(">I", data, 0)[0]
    if magic in (0xCAFEBABE, 0xCAFEBABF):
        n = struct.unpack_from(">I", data, 4)[0]
        p = 8
        out = []
        for _ in range(n):
            if magic == 0xCAFEBABF:
                _ct, _st, off, size, _al, _r = struct.unpack_from(">iiQQII", data, p)
                p += 32
            else:
                _ct, _st, off, size, _al = struct.unpack_from(">iiIII", data, p)
                p += 20
            out.append(data[off:off + size])
        return out
    return [data]


def sections(buf: bytes):
    assert struct.unpack_from("<I", buf, 0)[0] == 0xFEEDFACF, "chi ho tro Mach-O 64-bit"
    _m, _ct, _st, _ft, ncmds, _sc, _fl, _rs = struct.unpack_from("<IiiIIIII", buf, 0)
    p = 32
    out = {}
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", buf, p)
        if cmd == LC_SEGMENT_64:
            seg = buf[p + 8:p + 24].rstrip(b"\0").decode()
            nsects = struct.unpack_from("<I", buf, p + 64)[0]
            sp = p + 72
            for _i in range(nsects):
                sect = buf[sp:sp + 16].rstrip(b"\0").decode()
                offset = struct.unpack_from("<I", buf, sp + 32)[0]
                size = struct.unpack_from("<Q", buf, sp + 40)[0]
                out[(seg, sect)] = (offset, size)
                sp += 80
        p += cmdsize
    return out


def cstrings(buf: bytes, sec) -> list[str]:
    off, size = sec
    raw = buf[off:off + size]
    return [s.decode("utf-8", "replace") for s in raw.split(b"\0") if s]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("binary")
    ap.add_argument("--out-dir", default="work")
    ap.add_argument("--classes", default=None, help="regex loc class")
    ap.add_argument("--methods", default=None, help="regex loc method")
    ap.add_argument("--cstrings", default=None, help="regex loc chuoi __cstring")
    args = ap.parse_args()

    data = open(args.binary, "rb").read()
    print(f"file={args.binary} ({len(data):,} bytes), {len(slices(data))} slice(s)")

    all_classes: list[str] = []
    all_methods: list[str] = []
    for i, sl in enumerate(slices(data)):
        secs = sections(sl)
        all_classes += cstrings(sl, secs[("__TEXT", "__objc_classname")])
        all_methods += cstrings(sl, secs[("__TEXT", "__objc_methname")])
        print(f"slice {i}: {len(all_classes)} class names, {len(all_methods)} method names")

    import os
    os.makedirs(args.out_dir, exist_ok=True)
    with open(os.path.join(args.out_dir, "classes.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(sorted(set(all_classes))))
    with open(os.path.join(args.out_dir, "methods.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(sorted(set(all_methods))))
    print(f"-> {args.out_dir}/classes.txt  {len(set(all_classes))} unique")
    print(f"-> {args.out_dir}/methods.txt  {len(set(all_methods))} unique")

    if args.classes:
        rx = re.compile(args.classes, re.I)
        hits = sorted({c for c in all_classes if rx.search(c)})
        print(f"\n== classes khop /{args.classes}/ ({len(hits)}) ==")
        for h in hits:
            print("  " + h)

    if args.methods:
        rx = re.compile(args.methods, re.I)
        hits = sorted({m for m in all_methods if rx.search(m)})
        print(f"\n== methods khop /{args.methods}/ ({len(hits)}) ==")
        for h in hits:
            print("  " + h)
    if args.cstrings:
        rx = re.compile(args.cstrings, re.I)
        seen = set()
        print(f"\n== __cstring khop /{args.cstrings}/ ==")
        for i, sl in enumerate(slices(data)):
            for s in cstrings(sl, sections(sl)[("__TEXT", "__cstring")]):
                if rx.search(s) and s not in seen:
                    seen.add(s)
                    print("  " + s)
        print(f"  ({len(seen)} chuoi)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
