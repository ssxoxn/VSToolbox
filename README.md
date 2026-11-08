# VSToolbox 🌸

Tweak cá nhân cho **Video Star 15.0.3** (`com.frontierdesign.videostar`), thêm một nút nổi
nhỏ mở bảng công cụ tiếng Việt, màu hồng:

- **Nhập ảnh / video hàng loạt** vào các lớp media của preset, dùng **picker gốc của app**
  (giống hệt thao tác thêm ảnh bình thường) — chọn tất cả lớp hoặc tự chọn từng lớp.
- **Nhập code thủ công** và lưu 2 code gần đây nhất, chạm để copy.
- Banner tiến trình có nút **Bỏ qua / Dừng** ngay trên màn hình picker.

> Chỉ phục vụ thao tác nhập liệu cá nhân. Không can thiệp IAP, license, watermark hay
> bất kỳ cơ chế bản quyền nào của app. **Không sửa, không xóa các dylib có sẵn trong IPA nguồn**
> (VSPlusUltra, VSFix1-4, CydiaSubstrate).

---

## 1. Cấu trúc

```
tweak/
  VSToolbox.h     khai báo chung
  VSCore.mm       màu, helper, lịch sử code, quét lớp, phiên nhập hàng loạt (polling)
  VSUI.mm         nút nổi, panel, banner, toast
  Tweak.mm        constructor (chỉ cài UI, không dùng Logos, không swizzle)
  Makefile        build ra dist/VSToolbox.dylib
tools/
  inject.py       chèn LC_LOAD_DYLIB vào IPA (không dịch file)
  inspect_ipa.py  soi bundle / mã hoá / dylib
  classdump.py    dump class/selector từ Mach-O
.github/workflows/build.yml   build trên GitHub Actions
```

**Quan trọng:** Tweak này **không dùng `method_setImplementation`**, không swizzle method nào
của app. Do đó có thể chạy song song với VSPlusUltra.dylib, VSFix1-4.dylib và CydiaSubstrate
đã có sẵn trong IPA nguồn mà không gây crash.

## 2. Build

### Cách A — GitHub Actions (khuyến nghị, không cần cài gì)

1. Đưa thư mục này lên một repo GitHub.
2. Tab **Actions** → `build-vstoolbox` → **Run workflow**.
3. Tải artifact **VSToolbox-dylib** (chứa `VSToolbox.dylib`).

Workflow tự cài Theos + toolchain LLVM + iPhoneOS 16.5 SDK, build, rồi kiểm tra dylib
không còn phụ thuộc substrate.

### Cách B — WSL2 / Linux

```bash
sudo apt install build-essential fakeroot rsync curl perl zip git libxml2 libtinfo6
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/install-theos/master/install-theos)"
# cài toolchain + SDK theo hướng dẫn của Theos, sau đó:
cd tweak && make dylib
# -> tweak/dist/VSToolbox.dylib
```

## 3. Chèn vào IPA

```bash
python tools/inject.py \
  --ipa "Video Star Ultra (15.0.3) 2.ipa" \
  --dylib tweak/dist/VSToolbox.dylib \
  --out "Video Star + VSToolbox.ipa"
```

Script sẽ:

- thêm `LC_LOAD_DYLIB @executable_path/Frameworks/VSToolbox.dylib` vào **phần header còn
  trống** (IPA này dư `0xDE8` byte),
- cập nhật `ncmds` / `sizeofcmds`,
- copy dylib vào `Payload/Video Star.app/Frameworks/`,
- **không dịch chuyển byte nào** của binary → an toàn với binary đã giải mã.

Nếu vùng header không đủ chỗ hoặc không trống, script dừng lại (không có `--force` thì
không ghi đè).

## 4. Ký & cài

1. Mở IPA đầu ra bằng **LCSign** và ký bằng chứng chỉ doanh nghiệp của bạn.
2. Cài lên iPhone 15 (iOS 17.6.1).
3. Mở Video Star → thấy nút **🌸** nổi ở cạnh phải màn hình.

## 5. Dùng trong app

1. Mở một preset / dự án có nhiều lớp (**Multi Layer**).
2. Chạm 🌸 → panel:
   - **Ảnh — Tự động nhập tất cả lớp**: chọn 1 ảnh duy nhất → tự gán vào toàn bộ các lớp ảnh.
   - **Chọn lớp để nhập ảnh**: bật/tắt từng lớp rồi bấm **Bắt đầu** → gán 1 ảnh vào các lớp đã chọn.
3. Với mỗi lớp: chọn ảnh/video trong picker → app gán nội dung → tweak tự chuyển sang lớp
   tiếp theo và mở picker lại.
4. Banner trên cùng hiện `Nhập ảnh • lớp 5 (2/7)` kèm **Bỏ qua** và **Dừng** — bấm được
   ngay cả khi đang mở picker.
5. Code: mục **Code gần đây** (tối đa 2) → chạm để copy. Nếu muốn thêm code mới, dùng
   mục **Nhập code thủ công** → gõ code → bấm **Lưu**.

### Lớp nào được coi là "media"?

Được chọn khi **không** phải: lớp trống (`isNullLayer`), lớp văn bản (`textDictionary`),
lớp 3D (`is3DLayer`), lớp overlay / GIF / zap / particle / drawing.

### Tuỳ chọn "Ưu tiên thay nội dung lớp đang chọn"

- **Bật (mặc định)**: gọi luồng *thay nội dung* của app cho lớp đang chọn
  (`selectLayerNum:flash:` + `pickNewContent`). Nếu app không mở picker, tweak tự fallback
  sang `showPhotoPicker`.
- **Tắt**: luôn dùng nút thêm ảnh mặc định (`showPhotoPicker`).

## 6. Giới hạn đã biết

- Tweak dựa trên selector nội bộ của bản 15.0.3; app update có thể đổi tên → luôn có
  `respondsToSelector:` + fallback, nhưng vẫn nên build lại và test.
- **Không tự động bắt code từ app** (để tránh xung đột với VSPlusUltra). Code chỉ được lưu
  khi người dùng nhập thủ công qua mục "Nhập code thủ công".
- Không hỗ trợ preset có hơn 41 lớp (quét 0..40).
- Thứ tự nhập = thứ tự lớp tăng dần.
- Bulk import dùng polling (kiểm tra mỗi 0.5 giây layer đã có nội dung chưa), timeout 15 giây
  cho mỗi lớp. Nếu người dùng hủy picker, tweak sẽ bỏ qua lớp đó sau 15 giây.
- IPA nguồn đã có sẵn `VSPlusUltra.dylib` và `VSFix1..4.dylib`; tweak này **không** đụng tới
  chúng.

## 7. Gỡ lỗi

- Log: Xcode → **Window → Devices and Simulators → Open Console**, lọc `VSToolbox`.
- Nếu nút 🌸 không hiện: kiểm tra log có dòng `UI đã cài` chưa; nếu chưa, app có thể chưa
  tạo `UIWindowScene` (thử mở app lại).
- Nếu nhập hàng loạt không tự chuyển lớp: tweak sẽ log `poll timeout cho lớp ...` sau 15 giây.
  Có thể người dùng đã hủy picker — bấm **Bỏ qua** trên banner để chuyển lớp tiếp.

## 8. Ghi chú pháp lý / an toàn

- Chỉ dùng cho máy và tài khoản của bạn.
- Không phân phối lại IPA đã ký hoặc dylib kèm app thương mại.
- Không có mã liên quan đến IAP, license, watermark, DRM.
