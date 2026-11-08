#!/usr/bin/env python3
"""Chèn VSToolbox.dylib vào IPA **KHÔNG đụng vào main executable**.

Vấn đề: trên IPA gốc (Video Star 15.0.3 mod ipacrack), Pro của VSPlusUltra phụ
thuộc chuỗi weak-load trong main executable. Thêm/bớt/sửa load command của main
executable khiến VSPlusUltra không nạp hook IAP → mất Pro (đã kiểm chứng A/B).

Giải pháp (mặc định): chèn LC_LOAD_DYLIB "@executable_path/Frameworks/
VSToolbox.dylib" vào **VSFix4.dylib** (carrier, trong Frameworks của IPA) —
main executable đã weak-load thẳng VSFix4, nên khi VSFix4 được nạp,
VSToolbox được nạp theo. Main executable giữ nguyên từng byte → Pro giữ nguyên.

  python tools/inject.py --ipa in.ipa --dylib tweak/dist/VSToolbox.dylib --out out.ipa
  python tools/inject.py --ipa in.ipa --dylib ... --out ... --legacy-main  # kiểu cũ (nguy hiểm)
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
MH_MAGIC_32 = 0xFEEDFACE
FAT_MAGIC_BE = 0xCAFEBABE  # fat 32-bit (fat_arch 20 bytes)

LC_SEGMENT_64 = 0x19
LC_LOAD_DYLIB = 0xC
LC_ID_DYLIB = 0xD

CPU_ARM64 = 0x0100000C
CPU_ARM64E = 0x0100000D

DYLIB_NAME = "VSToolbox.dylib"
DYLIB_PATH = "@executable_path/Frameworks/" + DYLIB_NAME
CARRIER_DEFAULT = "VSFix4.dylib"


def align8(n: int) -> int:
    return (n + 7) & ~7


def cstr(buf: bytes, off: int) -> str:
    end = buf.find(b"\0", off)
    if end < 0:
        end = len(buf)
    return buf[off:end].decode("utf-8", "replace")


# =====================================================================
# Bảng slice của fat binary
# =====================================================================

def arch_table(data: bytes) -> list[tuple[int, int, int, int]]:
    """Trả [(cputype, offset, size, align)] của toàn slice trong fat (file gốc)."""
    fat = struct.unpack_from(">I", data, 0)[0]
    if fat != FAT_MAGIC_BE:
        return []
    nfat = struct.unpack_from(">I", data, 4)[0]
    archs = []
    p = 8
    for _ in range(nfat):
        cputype, cpusub, offset, size, align = struct.unpack_from(">IIIII", data, p)
        archs.append((cputype, offset, size, align))
        p += 20
    return archs


def parse_macho64(buf: bytes) -> dict | None:
    """Parse 1 slice 64-bit chỉ đọc. None nếu không phải macho64."""
    if len(buf) < 32 or struct.unpack_from("<I", buf, 0)[0] != MH_MAGIC_64:
        return None
    filetype = struct.unpack_from("<I", buf, 12)[0]
    cputype = struct.unpack_from("<I", buf, 4)[0]
    ncmds = struct.unpack_from("<I", buf, 16)[0]
    sizeofcmds = struct.unpack_from("<I", buf, 20)[0]
    hdr_end = 32 + sizeofcmds
    dylibs: list[str] = []
    first_sect = None
    p = 32
    ok = True
    for _i in range(ncmds):
        if p + 8 > hdr_end:
            ok = False
            break
        cmd, cmdsize = struct.unpack_from("<II", buf, p)
        if cmdsize < 8:
            ok = False
            break
        if cmd in (LC_LOAD_DYLIB, LC_ID_DYLIB):
            name_off = struct.unpack_from("<I", buf, p + 8)[0]
            dylibs.append(cstr(buf, p + name_off))
        elif cmd == LC_SEGMENT_64:
            nsects = struct.unpack_from("<I", buf, p + 64)[0]
            sp = p + 72
            for _s in range(nsects):
                size = struct.unpack_from("<Q", buf, sp + 40)[0]
                off = struct.unpack_from("<I", buf, sp + 48)[0]
                flags = struct.unpack_from("<I", buf, sp + 64)[0]
                zerofill = (flags & 0xFF) == 0x01
                if off > 0 and size > 0 and not zerofill:
                    if first_sect is None or off < first_sect:
                        first_sect = off
                sp += 80
        p += cmdsize
    if not ok:
        return None
    slack = (first_sect - hdr_end) if first_sect else None
    return {
        "cputype": cputype, "filetype": filetype, "ncmds": ncmds,
        "sizeofcmds": sizeofcmds, "hdr_end": hdr_end,
        "first_sect": first_sect, "slack": slack, "dylibs": dylibs,
    }


# =====================================================================
# Chèn LC_LOAD_DYLIB vào 1 slice 64-bit (đổi trực tiếp bytearray của file)
# =====================================================================

DYLIB_TIMESTAMP = 2
DYLIB_VERSION = 0x00010000  # 1.0


def build_load_command(path: str) -> bytes:
    raw = path.encode("utf-8") + b"\0"
    size = 24 + len(raw)
    padded = align8(size)
    body = struct.pack("<IIIIII", LC_LOAD_DYLIB, padded, 24,
                       DYLIB_TIMESTAMP, DYLIB_VERSION, DYLIB_VERSION)
    body += raw
    body += b"\0" * (padded - size)
    return body


def inject_into_fat(data: bytes, carrier_label: str, dylib_path: str,
                    force: bool) -> tuple[bytes, int]:
    """Chèn LC vào mọi slice 64-bit của file fat. Trả (bytes mới, số slice đã sửa)."""
    data = bytearray(data)
    patched = 0

    for cputype, offset, size, _align in arch_table(data):
        if cputype not in (CPU_ARM64, CPU_ARM64E):
            print(f"  {carrier_label}: bỏ qua slice cpu=0x{cputype:X} "
                  f"(không phải arm64/arm64e)")
            continue
        buf = bytes(data[offset:offset + size])
        info = parse_macho64(buf)
        if info is None:
            # slice arm64 nhưng format lạ → bỏ an toàn
            print(f"  {carrier_label}: slice arm64 tại 0x{offset:X} parse thất bại → bỏ qua")
            continue
        if dylib_path in info["dylibs"]:
            print(f"  {carrier_label}: slice arm64 đã có {dylib_path} → không sửa")
            patched += 1
            continue

        cmd = build_load_command(dylib_path)
        start, end = info["hdr_end"], info["hdr_end"] + len(cmd)
        print(f"  {carrier_label}: slice cpu={'arm64e' if cputype == CPU_ARM64E else 'arm64'} "
              f"ncmds={info['ncmds']} sizeofcmds=0x{info['sizeofcmds']:X} "
              f"hdr_end=0x{info['hdr_end']:X} first_sect="
              f"{hex(info['first_sect']) if info['first_sect'] else '?'} "
              f"slack={hex(info['slack']) if info['slack'] else '?'}")
        print(f"        cần {len(cmd)} bytes, vùng ghi 0x{start:X}..0x{end:X}")

        if info["first_sect"] is None or end > info["first_sect"]:
            raise SystemExit(
                f"{carrier_label}: slice không đủ slack trong header — dừng.")
        region = bytes(data[offset + start:offset + end])
        if any(region) and not force:
            raise SystemExit(
                f"{carrier_label}: vùng ghi không trống — dừng (dùng --force).")

        data[offset + start:offset + start + len(cmd)] = cmd
        struct.pack_into("<I", data, offset + 16, info["ncmds"] + 1)
        struct.pack_into("<I", data, offset + 20, info["sizeofcmds"] + len(cmd))
        patched += 1

        # verify ngay sau khi sửa
        check = parse_macho64(bytes(data[offset:offset + size]))
        if not check or dylib_path not in check["dylibs"]:
            raise SystemExit(f"{carrier_label}: verify slice thất bại sau khi ghi.")
        print(f"        ✓ ({check['ncmds']} cmd, sizeofcmds=0x{check['sizeofcmds']:X})")

    if patched == 0:
        raise SystemExit(f"{carrier_label}: không patch được slice nào.")
    return bytes(data), patched


def inject_into_single(data: bytes, label: str, dylib_path: str,
                       force: bool) -> tuple[bytes, int]:
    """Chèn LC vào macho64 đơn-lát (không fat)."""
    info = parse_macho64(data)
    if info is None:
        raise SystemExit(f"{label}: không phải Mach-O 64-bit.")
    if dylib_path in info["dylibs"]:
        return data, 1
    cmd = build_load_command(dylib_path)
    start, end = info["hdr_end"], info["hdr_end"] + len(cmd)
    print(f"  {label}: ncmds={info['ncmds']} sizeofcmds=0x{info['sizeofcmds']:X} "
          f"hdr_end=0x{info['hdr_end']:X} "
          f"first_sect={hex(info['first_sect']) if info['first_sect'] else '?'} "
          f"slack={hex(info['slack']) if info['slack'] else '?'}")
    if info["first_sect"] is None or end > info["first_sect"]:
        raise SystemExit(f"{label}: không đủ slack trong header — dừng.")
    region = data[start:end]
    if any(region) and not force:
        raise SystemExit(f"{label}: vùng ghi không trống — dừng (dùng --force).")
    new = bytearray(data)
    new[start:end] = cmd
    struct.pack_into("<I", new, 16, info["ncmds"] + 1)
    struct.pack_into("<I", new, 20, info["sizeofcmds"] + len(cmd))
    check = parse_macho64(bytes(new))
    if not check or dylib_path not in check["dylibs"]:
        raise SystemExit(f"{label}: verify thất bại sau ghi.")
    print(f"        ✓ ({check['ncmds']} cmd, sizeofcmds=0x{check['sizeofcmds']:X})")
    return bytes(new), 1


# =====================================================================
# Chèn vào main executable (kiểu cũ — chỉ dùng khi carrier không chạy)
# =====================================================================

def patch_main_executable(data: bytes, dylib_path: str, force: bool) -> bytes:
    info = parse_macho64(data)
    if info is None:
        raise SystemExit("main executable: không phải Mach-O 64-bit.")
    if dylib_path in info["dylibs"]:
        print("  !! main exec đã có LC → giữ nguyên")
        return data
    out, _ = inject_into_single(data, "main executable", dylib_path, force)
    return out


# =====================================================================
# IPA plumbing
# =====================================================================

def main() -> int:
    ap = argparse.ArgumentParser(
        description="Chèn VSToolbox.dylib vào IPA (mặc định: qua VSFix4, không đụng main exec)")
    ap.add_argument("--ipa", required=True, help="IPA nguồn (giải mã sẵn)")
    ap.add_argument("--dylib", required=True, help="VSToolbox.dylib cần chèn")
    ap.add_argument("--out", required=True, help="IPA đầu ra")
    ap.add_argument("--carrier", default=CARRIER_DEFAULT,
                    help=f"dylib trong Frameworks làm carrier (mặc định {CARRIER_DEFAULT})")
    ap.add_argument("--legacy-main", action="store_true",
                    help="[DANGER] chèn LC vào main executable (kiểu cũ — làm mất Pro)")
    ap.add_argument("--probe-only", action="store_true",
                    help="chỉ copy VSToolbox.dylib vào Frameworks, KHÔNG patch "
                         "load command gì cả (phép thử cô lập nguyên nhân)")
    ap.add_argument("--force", action="store_true",
                    help="vẫn ghi nếu vùng header không trống")
    args = ap.parse_args()

    if not os.path.isfile(args.ipa):
        raise SystemExit(f"không thấy IPA: {args.ipa}")
    if not os.path.isfile(args.dylib):
        raise SystemExit(f"không thấy dylib: {args.dylib}")

    print("== dylib ==")
    dylib_data = open(args.dylib, "rb").read()
    dinfo = parse_macho64(dylib_data)
    if dinfo is None and arch_table(dylib_data):
        print("  dylib là fat binary — hợp lệ")
    elif dinfo is None:
        raise SystemExit("dylib không phải Mach-O 64 (cả fat lẫn đơn-lát).")
    if "substrate" in args.dylib.lower():
        print("  ! tên dylib chứa 'substrate' (kiểm tra lại build)")

    with zipfile.ZipFile(args.ipa) as zin:
        names = zin.namelist()
        apps = sorted({n.split("/")[1] for n in names
                       if n.startswith("Payload/") and ".app/" in n})
        if not apps:
            raise SystemExit("IPA không có Payload/*.app")
        app = apps[0]
        root = f"Payload/{app}/"
        info = plistlib.loads(zin.read(root + "Info.plist"))
        exe_path = root + info["CFBundleExecutable"]
        if exe_path not in names:
            raise SystemExit(f"không thấy executable {exe_path}")

        print(f"\n== IPA ==\n  bundle: {info.get('CFBundleIdentifier')} "
              f"v{info.get('CFBundleShortVersionString')} ({info.get('CFBundleVersion')})")

        dylib_zip_path = root + "Frameworks/" + DYLIB_NAME
        orig_exe = zin.read(exe_path)
        exe_hashes = (len(orig_exe), hash(orig_exe))

        if b"VSToolbox" in orig_exe:
            raise SystemExit(
                "IPA này đã chèn VSToolbox từ LẦN TRƯỚC (LC cũ còn trong main exec).\n"
                "  → Bắt buộc dùng IPA GỐC chưa inject lẻ nào. LC_LOAD_DYLIB cũ này\n"
                "  chính là nguyên nhân mất Pro — không thể tái sử dụng IPA cũ.")

        carrier_data: bytes | None = None
        new_carrier: bytes | None = None
        carrier_zip_path = root + "Frameworks/" + args.carrier
        probe_only = getattr(args, "probe_only", False)
        if carrier_zip_path not in names:
            carrier_zip_path = None
            if not args.legacy_main:
                raise SystemExit(
                    f"không thấy carrier Frameworks/{args.carrier} trong IPA; "
                    f"dùng --legacy-main để chèn vào main executable.")
        else:
            carrier_data = zin.read(carrier_zip_path)
            print(f"\n== carrier ==\n  {carrier_zip_path} "
                  f"({len(carrier_data):,} bytes)")
            if probe_only:
                print("  --probe-only: KHÔNG patch carrier (dylib chỉ nằm trong "
                      "Frameworks, không được nạp — dùng để cô lập nguyên nhân)")
            elif not args.legacy_main:
                new_carrier, n = inject_into_fat(carrier_data, args.carrier,
                                                 DYLIB_PATH, args.force)
                if DYLIB_PATH not in build_show_depend(new_carrier):
                    raise SystemExit("verify cuối: không thấy LC vừa chèn.")
                print(f"  đã chèn vào {n} slice")

        # main executable: nếu legacy-main thì chèn, nếu không → để nguyên byte
        if args.legacy_main:
            new_exe = patch_main_executable(orig_exe, DYLIB_PATH, args.force)
        else:
            new_exe = orig_exe

        if exe_hashes[0] != len(new_exe) or exe_hashes[1] != hash(new_exe):
            raise SystemExit("main exec bị sửa khi không mong muốn — huỷ.")

        tmp_out = args.out + ".part"
        with zipfile.ZipFile(tmp_out, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as zout:
            for item in zin.infolist():
                if item.filename == exe_path:
                    zout.writestr(item, new_exe)
                elif carrier_zip_path and item.filename == carrier_zip_path:
                    # ghi carrier đã patch (nếu legacy → giữ nguyên bản gốc)
                    zout.writestr(item,
                                  new_carrier if new_carrier is not None
                                  else carrier_data)
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
    if args.legacy_main:
        print("  (legacy) chèn LC vào main executable")
    elif probe_only:
        print("  main executable + carrier: GIỮ NGUYÊN byte (chỉ copy dylib)")
        print("  → dylib CHƯA được nạp. Cài bản này: nếu Pro vẫn chết thì thủ "
              "phạm là CHÍNH VIỆC dylib tồn tại trong Frameworks (rất lạ); nếu "
              "Pro sống thì thủ phạm là LC đã chèn vào main exec ở các lần cũ.")
    else:
        print(f"  main executable: GIỮ NGUYÊN byte ({len(new_exe):,} bytes "
              f"— giống IPA gốc)")
        print(f"  carrier: {args.carrier} → VSToolbox.dylib qua @executable_path")
    print(f"  dylib:   {dylib_zip_path} ({len(dylib_data):,} bytes)")
    print("\nBước tiếp theo: ký lại bằng LCSign rồi cài lên máy.")
    return 0


def build_show_depend(fat: bytes) -> list[str]:
    """List dylib path của mọi slice 64-bit trong 1 file (fat hoặc đơn)."""
    archs = arch_table(fat)
    if archs:
        out: list[str] = []
        for _ct, off, size, _al in archs:
            info = parse_macho64(fat[off:off + size])
            if info:
                out.extend(info["dylibs"])
        return out
    info = parse_macho64(fat)
    return list(info["dylibs"]) if info else []


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    raise SystemExit(main())
