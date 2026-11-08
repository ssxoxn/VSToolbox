#!/usr/bin/env python3
"""Doc ObjC class/method metadata trong Mach-O 64-bit (tuong tu class-dump, khong can toolchain).

  python tools/classdump.py work/VideoStar.bin --find-method "makePhotoLayer|importPhotoToEnd"
  python tools/classdump.py work/VideoStar.bin --class "MultiLayerEngine" --dump-methods
  python tools/classdump.py work/VideoStar.bin --find-class "Layer"
"""
from __future__ import annotations

import argparse
import re
import struct

LC_SEGMENT_64 = 0x19


class MachO:
    def __init__(self, data: bytes):
        self.d = data
        magic = struct.unpack_from("<I", data, 0)[0]
        if magic != 0xFEEDFACF:
            raise SystemExit("Chi ho tro Mach-O 64-bit (arm64).")
        self.ncmds = struct.unpack_from("<I", data, 16)[0]
        self.segments = []           # (name, vmaddr, vmsize, fileoff, filesize)
        self.sections = {}           # (seg, sect) -> (offset, size)
        p = 32
        for _ in range(self.ncmds):
            cmd, cmdsize = struct.unpack_from("<II", data, p)
            if cmd == LC_SEGMENT_64:
                name = data[p + 8:p + 24].rstrip(b"\0").decode(errors="replace")
                vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", data, p + 24)
                self.segments.append((name, vmaddr, vmsize, fileoff, filesize))
                nsects = struct.unpack_from("<I", data, p + 64)[0]
                sp = p + 72
                for _i in range(nsects):
                    sect = data[sp:sp + 16].rstrip(b"\0").decode(errors="replace")
                    off = struct.unpack_from("<I", data, sp + 32)[0]
                    size = struct.unpack_from("<Q", data, sp + 40)[0]
                    self.sections[(name, sect)] = (off, size)
                    sp += 80
            p += cmdsize
        self.image_base = next(vm for name, vm, _vs, _fo, _fs in self.segments if name == "__TEXT")
        self.selrefs = None
        for seg, sect in (("__DATA_CONST", "__objc_selrefs"), ("__DATA", "__objc_selrefs")):
            if (seg, sect) in self.sections:
                self.selrefs = self.section_va_range(seg, sect)

    def section_va_range(self, seg, sect):
        off, size = self.sections[(seg, sect)]
        for _n, vmaddr, _vs, fileoff, filesize in self.segments:
            if fileoff <= off < fileoff + filesize:
                return vmaddr + (off - fileoff), size
        return None

    def sel_name(self, va: int) -> str:
        """Selector co the la chuoi truc tiep, hoac 1 slot trong __objc_selrefs."""
        if self.selrefs:
            start, size = self.selrefs
            if start <= va < start + size:
                va = self.dptr(self.va2off(va))
        return self.cstr(va)

    def dptr(self, off: int) -> int:
        """Doc pointer co xu ly chained fixups (iOS 15+): target = image_base + (raw & 0xFFFFFFFFF)."""
        return self.image_base + (self.u64(off) & 0xFFFFFFFFF)

    def va2off(self, va: int) -> int:
        for _n, vmaddr, _vmsize, fileoff, filesize in self.segments:
            if vmaddr <= va < vmaddr + filesize:
                return va - vmaddr + fileoff
        raise ValueError(f"VA 0x{va:X} khong thuoc segment nao")

    def u32(self, off):
        return struct.unpack_from("<I", self.d, off)[0]

    def s32(self, off):
        return struct.unpack_from("<i", self.d, off)[0]

    def u64(self, off):
        return struct.unpack_from("<Q", self.d, off)[0]

    def cstr(self, va: int) -> str:
        off = self.va2off(va)
        end = self.d.index(b"\0", off)
        return self.d[off:end].decode("utf-8", "replace")

    def section_va(self, seg, sect) -> int:
        off, _size = self.sections[(seg, sect)]
        for _n, vmaddr, _vmsize, fileoff, _filesize in self.segments:
            if fileoff <= off < fileoff + 0x40000000:
                return vmaddr + (off - fileoff)
        raise ValueError("khong tim thay VA cua section")

    def method_names(self, list_va: int) -> list[str]:
        if not list_va:
            return []
        try:
            off = self.va2off(list_va)
        except ValueError:
            return []
        entsize_and_flags, count = self.u32(off), self.u32(off + 4)
        entsize = entsize_and_flags & 0xFFFC
        out = []
        p = off + 8
        if count > 8000:
            return []
        if entsize == 12:  # relative method list
            for i in range(count):
                entry_va = list_va + 8 + i * 12
                try:
                    out.append(self.sel_name(entry_va + self.s32(p)))
                except (ValueError, IndexError):
                    pass
                p += 12
        elif entsize == 24:  # absolute pointers
            for _ in range(count):
                try:
                    out.append(self.sel_name(self.dptr(p)))
                except (ValueError, IndexError):
                    pass
                p += 24
        return out

    def find_class(self, name: str):
        for seg, sect in (("__DATA_CONST", "__objc_classlist"), ("__DATA", "__objc_classlist")):
            if (seg, sect) not in self.sections:
                continue
            off, size = self.sections[(seg, sect)]
            for i in range(size // 8):
                try:
                    cls_off = self.va2off(self.dptr(off + i * 8))
                    ro = self.va2off(self.dptr(cls_off + 32) & ~0x7)
                    if self.cstr(self.dptr(ro + 24)) == name:
                        return cls_off, ro
                except (ValueError, IndexError, struct.error):
                    continue
        return None

    def categories(self):
        out = []
        for seg, sect in (("__DATA_CONST", "__objc_catlist"), ("__DATA", "__objc_catlist")):
            if (seg, sect) not in self.sections:
                continue
            off, size = self.sections[(seg, sect)]
            for i in range(size // 8):
                try:
                    cat = self.va2off(self.dptr(off + i * 8))
                    cls_off = self.va2off(self.dptr(cat + 8))
                    ro = self.va2off(self.dptr(cls_off + 32) & ~0x7)
                    cls_name = self.cstr(self.dptr(ro + 24))
                    inst = self.method_names(self.dptr(cat + 16))
                    clsm = self.method_names(self.dptr(cat + 24))
                    out.append((cls_name, inst + clsm))
                except (ValueError, IndexError, struct.error):
                    continue
        return out

    def method_pairs(self, list_va: int) -> list[tuple[str, str]]:
        """Tra ve (selector, type encoding)."""
        if not list_va:
            return []
        try:
            off = self.va2off(list_va)
        except ValueError:
            return []
        entsize_and_flags, count = self.u32(off), self.u32(off + 4)
        entsize = entsize_and_flags & 0xFFFC
        out = []
        p = off + 8
        if count > 8000:
            return []
        if entsize == 12:
            for i in range(count):
                entry_va = list_va + 8 + i * 12
                try:
                    out.append((self.sel_name(entry_va + self.s32(p)),
                                self.cstr(entry_va + 4 + self.s32(p + 4))))
                except (ValueError, IndexError):
                    pass
                p += 12
        elif entsize == 24:
            for _ in range(count):
                try:
                    out.append((self.sel_name(self.dptr(p)),
                                self.cstr(self.dptr(p + 8))))
                except (ValueError, IndexError):
                    pass
                p += 24
        return out

    def classes(self):
        out = []
        for seg, sect in (("__DATA_CONST", "__objc_classlist"), ("__DATA", "__objc_classlist")):
            if (seg, sect) not in self.sections:
                continue
            off, size = self.sections[(seg, sect)]
            for i in range(size // 8):
                try:
                    cls_off = self.va2off(self.dptr(off + i * 8))
                    ro_va = self.dptr(cls_off + 32) & ~0x7
                    ro = self.va2off(ro_va)
                    name = self.cstr(self.dptr(ro + 24))
                    methods = self.method_names(self.dptr(ro + 32))
                    sup = ""
                    try:
                        sup_cls_va = self.dptr(cls_off + 8) & ~0x7
                        if sup_cls_va:
                            sro = self.va2off(self.dptr(self.va2off(sup_cls_va) + 32) & ~0x7)
                            sup = self.cstr(self.dptr(sro + 24))
                    except (ValueError, IndexError, struct.error):
                        sup = "<external>"
                    out.append((name, sup, methods))
                except (ValueError, IndexError, struct.error):
                    continue
        return out


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    ap = argparse.ArgumentParser()
    ap.add_argument("binary")
    ap.add_argument("--find-method", default=None, help="regex: in ra class chua selector khop")
    ap.add_argument("--find-class", default=None, help="regex: loc ten class")
    ap.add_argument("--class", dest="exact_class", default=None, help="ten class chinh xac")
    ap.add_argument("--dump-methods", action="store_true")
    ap.add_argument("--out", default=None, help="ghi toan bo class -> method ra file")
    ap.add_argument("--types", action="store_true", help="in kem type encoding")
    args = ap.parse_args()

    m = MachO(open(args.binary, "rb").read())
    classes = m.classes()
    cats = m.categories()
    print(f"{len(classes)} ObjC class, {len(cats)} category")

    if args.out:
        with open(args.out, "w", encoding="utf-8", errors="replace") as f:
            for name, sup, methods in classes:
                f.write(f"{name} : {sup}\n")
                for s in methods:
                    f.write(f"  - {s}\n")
            for cname, methods in cats:
                f.write(f"/* category {cname} */\n")
                for s in methods:
                    f.write(f"  - {s}\n")
        print(f"-> {args.out}")
    if args.find_method:
        rx = re.compile(args.find_method, re.I)
        print(f"\n== class chua selector khop /{args.find_method}/ ==")
        hits = 0
        for name, sup, methods in classes:
            matched = [s for s in methods if rx.search(s)]
            if matched:
                hits += 1
                print(f"\n{name} : {sup}")
                for s in matched:
                    print("   - " + s)
        for cname, methods in cats:
            matched = [s for s in methods if rx.search(s)]
            if matched:
                hits += 1
                print(f"\n{cname} (category)")
                for s in matched:
                    print("   - " + s)
        print(f"\n({hits} class)")

    if args.find_class:
        rx = re.compile(args.find_class, re.I)
        print(f"\n== class khop /{args.find_class}/ ==")
        for name, sup, methods in classes:
            if rx.search(name):
                print(f"  {name} : {sup}  ({len(methods)} methods)")

    if args.exact_class:
        if args.types:
            found = m.find_class(args.exact_class)
            if not found:
                print("khong tim thay class " + args.exact_class)
                return 1
            _cls_off, ro = found
            print(f"\n{args.exact_class}  (types)")
            for sel, typ in m.method_pairs(m.dptr(ro + 32)):
                print(f"   {sel}   {typ}")
        for name, sup, methods in classes:
            if name == args.exact_class and not args.types:
                print(f"\n{name} : {sup}  ({len(methods)} methods)")
                for s in methods:
                    print("   - " + s)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
