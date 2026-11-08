#!/usr/bin/env python3
"""Soi nhanh 1 IPA: bundle, Info.plist, kiến trúc, encryption, dylib, section.
Không cần toolchain, chỉ dùng thư viện chuẩn của Python.

  python tools/inspect_ipa.py "duong/dan/app.ipa"
"""
from __future__ import annotations

import plistlib
import struct
import sys
import zipfile

LC_NAMES = {
    0x1: "LC_SEGMENT", 0x2: "LC_SYMTAB", 0x3: "LC_SYMSEG", 0x4: "LC_THREAD",
    0x5: "LC_UNIXTHREAD", 0xB: "LC_DYSYMTAB", 0xC: "LC_LOAD_DYLIB",
    0xD: "LC_ID_DYLIB", 0xE: "LC_LOAD_DYLINKER", 0x19: "LC_SEGMENT_64",
    0x1D: "LC_CODE_SIGNATURE", 0x1E: "LC_SEGMENT_SPLIT_INFO",
    0x1F: "LC_REEXPORT_DYLIB", 0x21: "LC_ENCRYPTION_INFO",
    0x22: "LC_DYLD_INFO", 0x26: "LC_FUNCTION_STARTS", 0x29: "LC_DATA_IN_CODE",
    0x2B: "LC_DYLIB_CODE_SIGN_DRS", 0x2C: "LC_ENCRYPTION_INFO_64",
    0x2E: "LC_LINKER_OPTIMIZATION_HINT", 0x31: "LC_NOTE",
    0x32: "LC_BUILD_VERSION", 0x80000018: "LC_LOAD_WEAK_DYLIB",
    0x8000001C: "LC_RPATH", 0x8000001F: "LC_REEXPORT_DYLIB",
    0x80000022: "LC_DYLD_INFO_ONLY", 0x80000028: "LC_MAIN",
    0x80000033: "LC_DYLD_EXPORTS_TRIE", 0x80000034: "LC_DYLD_CHAINED_FIXUPS",
}


def parse_macho(buf: bytes, base: int = 0, label: str = "") -> None:
    magic = struct.unpack_from("<I", buf, base)[0]
    if magic not in (0xFEEDFACE, 0xFEEDFACF):
        print(f"    {label} magic la 0x{magic:08X} (khong phai Mach-O LE)")
        return
    is64 = magic == 0xFEEDFACF
    hdr_size = 32 if is64 else 28
    (cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags) = struct.unpack_from(
        "<iiIIII", buf, base + 4)
    arch = {0x0100000C: "arm64", 0x0C: "armv7", 0x01000007: "x86_64"}.get(cputype, hex(cputype))
    print(f"    {label} {arch} sub=0x{cpusubtype & 0xFFFFFFFF:08X} "
          f"filetype={filetype} ncmds={ncmds} sizeofcmds=0x{sizeofcmds:X}")

    p = base + hdr_size
    crypt = None
    exports = []
    sections = []
    slack_end = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", buf, p)
        name = LC_NAMES.get(cmd, f"0x{cmd:08X}")
        if cmd in (0xC, 0xD, 0x1F, 0x80000018, 0x8000001F):
            off = struct.unpack_from("<I", buf, p + 8)[0]
            s = buf[p + off: buf.index(b"\0", p + off)].decode("utf-8", "replace")
            exports.append((name, s))
        elif cmd == 0x8000001C:
            off = struct.unpack_from("<I", buf, p + 8)[0]
            exports.append((name, buf[p + off: buf.index(b"\0", p + off)].decode("utf-8", "replace")))
        elif cmd in (0x21, 0x2C):
            cryptoff, cryptsize, cryptid = struct.unpack_from("<III", buf, p + 8)
            crypt = (cryptid, cryptoff, cryptsize)
        elif cmd in (0x19, 0x1):
            segname = buf[p + 8:p + 24].rstrip(b"\0").decode()
            if cmd == 0x19:
                fileoff, filesize = struct.unpack_from("<QQ", buf, p + 40)
                nsects = struct.unpack_from("<I", buf, p + 64)[0]
                sp = p + 72
                sec_size = 80
            else:
                fileoff, filesize = struct.unpack_from("<II", buf, p + 32)
                nsects = struct.unpack_from("<I", buf, p + 48)[0]
                sp = p + 56
                sec_size = 68
            print(f"      seg {segname:<12} fileoff=0x{fileoff:X} filesize=0x{filesize:X} nsects={nsects}")
            for _i in range(nsects):
                sect = buf[sp:sp + 16].rstrip(b"\0").decode()
                if cmd == 0x19:
                    soff, ssize = struct.unpack_from("<QI", buf, sp + 32)
                    soff = struct.unpack_from("<I", buf, sp + 32)[0]
                    ssize = struct.unpack_from("<Q", buf, sp + 40)[0]
                else:
                    soff, ssize = struct.unpack_from("<II", buf, sp + 32)
                sections.append((segname, sect, soff, ssize))
                sp += sec_size
        p += cmdsize

    print("      dylibs/rpaths:")
    for n, s in exports:
        print(f"        {n:<20} {s}")
    if crypt:
        cid, co, cs = crypt
        print(f"      encryption: cryptid={cid} cryptoff=0x{co:X} cryptsize=0x{cs:X} "
              f"-> {'DA MA HOA (FairPlay)' if cid else 'da giai ma / khong ma hoa'}")

    want = {"__objc_classname", "__objc_methname", "__cstring", "__swift5_types",
            "__swift5_proto", "__objc_classrefs", "__objc_selrefs", "__text"}
    print("      sections quan tam:")
    for seg, sect, off, size in sections:
        if sect in want:
            print(f"        {seg},{sect:<20} off=0x{off:X} size=0x{size:X}")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    ipa = sys.argv[1]
    with zipfile.ZipFile(ipa) as z:
        names = z.namelist()
        apps = sorted({n.split("/")[1] for n in names if n.startswith("Payload/") and ".app/" in n})
        if not apps:
            print("Khong tim thay Payload/*.app")
            return 1
        app = apps[0]
        root = f"Payload/{app}/"
        print(f"IPA: {ipa}")
        print(f"App bundle: {root}  ({len(names)} entries)")

        info = plistlib.loads(z.read(root + "Info.plist"))
        print("\nInfo.plist:")
        for k in ("CFBundleIdentifier", "CFBundleExecutable", "CFBundleShortVersionString",
                  "CFBundleVersion", "MinimumOSVersion", "CFBundleDisplayName",
                  "UISupportedDevices", "DTXcodeBuild"):
            if k in info:
                v = info[k]
                print(f"  {k}: {v if not isinstance(v, list) else (v if len(v) < 6 else f'{len(v)} items')}")
        print("  UIDeviceFamily:", info.get("UIDeviceFamily"))
        print("  UIRequiredDeviceCapabilities:", info.get("UIRequiredDeviceCapabilities"))

        exe = info["CFBundleExecutable"]
        exe_path = root + exe
        data = z.read(exe_path)
        print(f"\nExecutable: {exe_path}  ({len(data):,} bytes)")

        magic = struct.unpack_from(">I", data, 0)[0]
        if magic in (0xCAFEBABE, 0xCAFEBABF):
            n = struct.unpack_from(">I", data, 4)[0]
            is64 = magic == 0xCAFEBABF
            print(f"  fat binary, {n} arch(s)")
            p = 8
            for i in range(n):
                if is64:
                    ct, st, off, size, align, _r = struct.unpack_from(">iiQQII", data, p)
                    p += 32
                else:
                    ct, st, off, size, align = struct.unpack_from(">iiIII", data, p)
                    p += 20
                print(f"  slice {i}: cputype=0x{ct:08X} offset=0x{off:X} size=0x{size:X} align=2^{align}")
                parse_macho(data[off:off + size], 0, f"slice{i}:")
        else:
            parse_macho(data, 0, "thin:")

        fw = sorted({n for n in names if n.startswith(root + "Frameworks/") and n.endswith(".framework/")})
        print(f"\nFrameworks ({len(fw)}):")
        for f in fw[:40]:
            print("  " + f.rsplit("/", 2)[-2])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
