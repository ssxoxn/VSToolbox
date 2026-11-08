#!/usr/bin/env python3
"""Chèn VSToolbox.dylib vào 1 IPA đã giải mã (không dịch chuyển nội dung file).

Cách làm: ghi thêm 1 lệnh LC_LOAD_DYLIB vào phần header còn trống (slack) ngay
sau các load command hiện có, rồi cập nhật ncmds/sizeofcmds. Vì không đổi
file offset của bất kỳ section nào nên an toàn với binary đã giải mã (chained
fixups vẫn đúng).

  python tools/inject.py --ipa "in.ipa" --dylib tweak/dist/VSToolbox.dylib --out "out.ipa"

Sau đó ký lại bằng LCSign (hoặc Sideloadly/Esign).
"""
from __future__ import annotations

import argparse
import os
import plistlib
import struct
import sys
import time
import zipfile

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF

LC_SEGMENT_64 = 0x19
LC_LOAD_DYLIB = 0xC
LC_ID_DYLIB = 0xD

DYLIB_PATH = "@executable_path/Frameworks/VSToolbox.dylib"
DYLIB_NAME = "VSToolbox.dylib"


def align8(n: int) -> int:
    return (n + 7) & ~7


def cstr(buf: bytes, off: int) -> str:
    end = buf.index(b"\0", off)
    return buf[off:end].decode("utf-8", "replace")


def parse_macho(data: bytes) -> dict:
    magic = struct.unpack_from("<I", data, 0)[0]
    if magic != MH_MAGIC_64:
        raise SystemExit(
            f"Không phải Mach-O 64-bit little-endian (magic 0x{magic:08X}). "
            f"File này có thể là fat binary hoặc đã bị mã hoá."
        )

    filetype = struct.unpack_from("<I", data, 12)[0]
    ncmds = struct.unpack_from("<I", data, 16)[0]
    sizeofcmds = struct.unpack_from("<I", data, 20)[0]

    p = 32
    header_size = 32
    dylibs: list[str] = []
    sections: list[tuple[str, str, int, int]] = []

    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, p)
        if cmdsize <= 0:
            raise SystemExit(f"load command hỏng tại 0x{p:X}")

        if cmd in (LC_LOAD_DYLIB, LC_ID_DYLIB):
            name_off = struct.unpack_from("<I", data, p + 8)[0]
            dylibs.append(cstr(data, p + name_off))
        elif cmd == LC_SEGMENT_64:
            segname = data[p + 8:p + 24].rstrip(b"\0").decode("utf-8", "replace")
            nsects = struct.unpack_from("<I", data, p + 64)[0]
            sp = p + 72
            for _s in range(nsects):
                sectname = data[sp:sp + 16].rstrip(b"\0").decode("utf-8", "replace")
                size = struct.unpack_from("<Q", data, sp + 40)[0]
                offset = struct.unpack_from("<I", data, sp + 48)[0]
                flags = struct.unpack_from("<I", data, sp + 64)[0]
                zerofill = (flags & 0xFF) == 0x01
                if offset > 0 and size > 0 and not zerofill:
                    sections.append((segname, sectname, offset, size))
                sp += 80
        p += cmdsize

    first_sect_off = min((s[2] for s in sections), default=0x4000)
    return {
        "filetype": filetype,
        "ncmds": ncmds,
        "sizeofcmds": sizeofcmds,
        "header_size": header_size,
        "header_end": header_size + sizeofcmds,
        "first_section_offset": first_sect_off,
        "dylibs": dylibs,
        "sections": sections,
    }


def build_load_command(path: str) -> bytes:
    raw = path.encode("utf-8") + b"\0"
    size = 24 + len(raw)
    padded = align8(size)
    body = struct.pack("<IIIIII", LC_LOAD_DYLIB, padded, 24, 2, 0x00010000, 0x00010000)
    body += raw
    body += b"\0" * (padded - size)
    return body


def inject_into_binary(data: bytes, path: str, force: bool) -> tuple[bytes, dict]:
    info = parse_macho(data)

    if path in info["dylibs"]:
        print(f"  ! {path} đã có sẵn trong load commands → chỉ thay file dylib")
        return data, info

    cmd = build_load_command(path)
    start = info["header_end"]
    end = start + len(cmd)

    print(f"  header: ncmds={info['ncmds']} sizeofcmds=0x{info['sizeofcmds']:X}")
    print(f"  slack:  0x{start:X} .. 0x{info['first_section_offset']:X} "
          f"({info['first_section_offset'] - start} bytes trống)")
    print(f"  cần:    {len(cmd)} bytes cho LC_LOAD_DYLIB")

    if end > info["first_section_offset"]:
        raise SystemExit("Không đủ chỗ trong header — không thể chèn mà không dịch file.")

    region = data[start:end]
    if any(region) and not force:
        raise SystemExit("Vùng header cần ghi không trống — dừng lại (dùng --force nếu chắc chắn).")

    new = bytearray(data)
    new[start:end] = cmd
    struct.pack_into("<I", new, 16, info["ncmds"] + 1)
    struct.pack_into("<I", new, 20, info["sizeofcmds"] + len(cmd))
    return bytes(new), info


def inspect_dylib(path: str) -> dict:
    with open(path, "rb") as f:
        data = f.read()
    try:
        info = parse_macho(data)
    except SystemExit as e:
        raise SystemExit(f"{path}: {e}")
    if info["filetype"] != 0x6:
        print(f"  ! filetype={info['filetype']} (dylib chuẩn là 6)")
    return info


def main() -> int:
    ap = argparse.ArgumentParser(description="Chèn VSToolbox.dylib vào IPA")
    ap.add_argument("--ipa", required=True, help="IPA nguồn (đã giải mã)")
    ap.add_argument("--dylib", required=True, help="VSToolbox.dylib cần chèn")
    ap.add_argument("--out", required=True, help="IPA đầu ra")
    ap.add_argument("--force", action="store_true", help="vẫn ghi nếu vùng header không trống")
    args = ap.parse_args()

    if not os.path.isfile(args.ipa):
        raise SystemExit(f"không thấy IPA: {args.ipa}")
    if not os.path.isfile(args.dylib):
        raise SystemExit(f"không thấy dylib: {args.dylib}")

    print("== dylib ==")
    dinfo = inspect_dylib(args.dylib)
    print(f"  load commands: {len(dinfo['dylibs'])}")
    for d in dinfo["dylibs"]:
        print(f"    {d}")
    bad = [d for d in dinfo["dylibs"] if "substrate" in d.lower()]
    if bad:
        raise SystemExit("Dylib còn phụ thuộc substrate — build sai (phải là tweak không Logos).")

    with zipfile.ZipFile(args.ipa) as zin:
        names = zin.namelist()
        apps = sorted({n.split("/")[1] for n in names
                       if n.startswith("Payload/") and ".app/" in n})
        if not apps:
            raise SystemExit("IPA không có Payload/*.app")
        app = apps[0]
        root = f"Payload/{app}/"
        info = plistlib.loads(zin.read(root + "Info.plist"))
        exe = info["CFBundleExecutable"]
        exe_path = root + exe
        if exe_path not in names:
            raise SystemExit(f"không thấy executable {exe_path}")

        print(f"\n== IPA ==\n  bundle: {info.get('CFBundleIdentifier')} "
              f"v{info.get('CFBundleShortVersionString')} ({info.get('CFBundleVersion')})")
        print(f"  exe:    {exe_path}")

        exe_data = zin.read(exe_path)
        new_exe, parsed = inject_into_binary(exe_data, DYLIB_PATH, args.force)

        verify = parse_macho(new_exe)
        if DYLIB_PATH not in verify["dylibs"]:
            raise SystemExit("kiểm tra thất bại: không thấy LC_LOAD_DYLIB vừa chèn")
        print(f"  kiểm tra: OK — {verify['ncmds']} load command, "
              f"sizeofcmds=0x{verify['sizeofcmds']:X}")

        dylib_zip_path = root + "Frameworks/" + DYLIB_NAME
        dylib_data = open(args.dylib, "rb").read()

        tmp_out = args.out + ".part"
        with zipfile.ZipFile(tmp_out, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as zout:
            for item in zin.infolist():
                if item.filename == exe_path:
                    zout.writestr(item, new_exe)
                elif item.filename == dylib_zip_path:
                    continue
                else:
                    zout.writestr(item, zin.read(item.filename))

            zi = zipfile.ZipInfo(dylib_zip_path)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.date_time = time.localtime()[:6]
            zi.external_attr = (0o100644 << 16)
            zout.writestr(zi, dylib_data)

        os.replace(tmp_out, args.out)

    print(f"\n== xong ==\n  IPA mới: {args.out}")
    print(f"  đã chèn: {DYLIB_PATH}")
    print(f"  dylib:   {dylib_zip_path} ({len(dylib_data):,} bytes)")
    print("\nBước tiếp theo: ký lại IPA (LCSign) rồi cài lên máy.")
    return 0


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    raise SystemExit(main())
