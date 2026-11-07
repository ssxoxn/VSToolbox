# PLAN — VSToolbox (dylib hỗ trợ nhập code / nhập ảnh cho Video Star)

> Tweak cá nhân, chỉ phục vụ thao tác nhập liệu (code, ảnh). Không can thiệp IAP, license,
> watermark hay bất kỳ cơ chế bản quyền nào của app.

---

## 1. Hiện trạng IPA đã soi

| Mục | Giá trị |
|---|---|
| Bundle ID | `com.frontierdesign.videostar` |
| Phiên bản | 15.0.3 (build 1847) |
| Min iOS | 17.2 |
| Executable | `Payload/Video Star.app/Video Star` — arm64 (thin), 25.2 MB |
| Mã hoá | `cryptid = 0` → **đã giải mã**, chèn dylib được |
| Load commands | 116 cmd, `sizeofcmds = 0x31F8` |
| Slack header | `0x4000 - 0x3218 = 0xDE8` (~3.5 KB) → đủ chỗ chèn LC_LOAD_DYLIB không cần dịch file |
| rpath sẵn có | `@executable_path/Frameworks` ✔ |
| ObjC | 2.747 class + 31 category |

⚠️ **Lưu ý:** IPA này đã bị chỉnh sẵn, có 5 dylib lạ trong `Frameworks/`:
`VSPlusUltra.dylib`, `VSFix1..4.dylib` (đã có load command tương ứng).
Mình **không sửa, không nâng cấp, không phục hồi** các dylib đó. Nếu muốn môi trường sạch để
test, nên dùng IPA tải từ App Store rồi tự ký.

---

## 2. Cấu trúc tweak

```
VSToolbox.dylib
├── UI
│   ├── VSButtonWindow      cửa sổ overlay riêng (level = alert+1), nút tròn kéo được, nhớ vị trí
│   ├── VSPanelVC           bảng chức năng (UIStackView / UITableView)
│   └── VSToast             HUD tiến trình + thông báo
├── Services
│   ├── VSContext           tìm VC đang hiển thị, tìm MultiLayerWiz* / VideoReviewEditVC
│   ├── VSCodeStore         lịch sử code (JSON trong Documents), max N bản ghi
│   ├── VSLayerService      liệt kê layer, phân loại, gán ảnh hàng loạt
│   ├── VSImagePicker       PHPicker multi-select
│   └── VSState             lưu/khôi phục trạng thái layer trước khi thao tác
└── Hooks
    ├── VSHookCodes         bắt code ở mọi class có `importedData:code:`
    ├── VSHookQR            QRCodeManager (lưu QR, path cache)
    └── VSHookLayers        MultiLayerWizEffectVC + MultiLayerEngine (chỉ đọc ở Phase 1)
```

Nút nổi: 44×44, alpha 0.85, kéo tự do, chạm = mở panel, panel mở dạng popover/sheet
của **window riêng** nên không phá UI app.

---

## 3. Hook map (đã xác minh trong binary)

### 3.1 Code / QR

| Việc | Class | Selector | Type |
|---|---|---|---|
| Bắt code vừa nhập | 13 class (VideoPreviewVC, MultiLayerWizEffectVC, ColorLabView, …) | `-importedData:code:` | `v32@0:8@16@24` |
| Lưu code vào thư viện | `QRCodeManager` | `-saveCodeToPlist:desc:` | `v32@0:8@16@24` |
| Kiểm tra code hợp lệ | nhiều class | `-validCode:` | `B24@0:8@16` |
| Lấy tiền tố code | nhiều class | `-codePrefix` | `@16@0:8` |
| Tạo QR cho code | `QRCodeManager` | `-makeQRCodeImage:desc:icon:` | `@40@0:8@16@24@32` |
| Đọc QR | `QRCodeManager` | `-readQRCode:` | `@24@0:8@16` |
| Import QR | `QRCodeManager` | `-startQRImport`, `-importQR` | `v16@0:8` |
| Thư viện QR | `_TtC10Video_Star22QRLibraryNavController` | `-initWithQrType:`, `-codeSelected` | |
| Danh sách QR | `_TtC10Video_Star11QRLibCollVC`, `_TtC10Video_Star14QRLibUserQRsVC` | `collectionView:didSelectItemAtIndexPath:` | |

→ Vì `importedData:code:` xuất hiện ở nhiều class, tweak sẽ **quét runtime** bằng
`objc_getClassList` + `class_getInstanceMethod`, swizzle mọi class phản hồi selector này.
Cách này không phụ thuộc tên class và tự thích nghi khi app update.

### 3.2 Multi-layer (lớp ảnh)

| Việc | Class | Selector | Type |
|---|---|---|---|
| Lấy engine | `MultiLayerWizEffectVC` | `-getMultiLayerEngine` | `@16@0:8` |
| Lấy layer theo số | `MultiLayerEngine` | `-layerAtLayerNum:` | `@24@0:8Q16` |
| Danh sách layer có nội dung | `MultiLayerEngine` | `-layersWithContent` / `-multiLayerLayersWithContent` | `@16@0:8` |
| Số layer đang bật | `MultiLayerEngine` | `-numActiveLayers` | `q16@0:8` |
| Loại layer | `MultiLayerEngine` | `-layerTypeForLayer:` | `i24@0:8Q16` |
| **Gán ảnh vào layer** | `MultiLayerEngine` | `-setupImage:layerNum:layerType:clearMask:` | `@40@0:8@16Q24i32B36` |
| Gán video | `MultiLayerEngine` | `-setupVideoLayer:forLayer:withInitialVolume:multiCheck:` | `@40@0:8@16Q24f32B36` |
| Tạo layer trống | `MultiLayerEngine` | `-maybeAddLayerAtLayerNum:` | `@24@0:8Q16` |
| Composite lại | `MultiLayerEngine` | `-compositeLayersAtCurrentFrame:`, `-syncCompositeLayersAtFrame:` | |
| Model layer | `MultiLayerLayer` | `-layerType` (int), `-isNullLayer`, `-origAssetInfo`, `-textDictionary`, `-layerNumber`, `-is3DLayer` | |
| UI chọn ảnh có sẵn | `MultiLayerWizEffectVC` | `-showPhotoPicker`, `-pickedWithClipPickerResponse:` | |
| Tạo layer ảnh | `MultiLayerWizEffectVC` | `-makePhotoLayer:` | `v24@0:8@16` |
| Tạo layer theo loại | `MultiLayerWizEffectVC` | `-makeColorLayer`, `-makeNullLayer`, `-makeOverlayLayer`, `-makeTextualImageLayer:textStyle:`, `-makeVideoLayer:frameTimes:volume:`, `-makeGIFLayer:doSave:`, `-makeZapLayer`, `-make3DObjectLayer:`, `-makeParticleLayer` | |
| Commit layer | `MultiLayerWizEffectVC` | `-confirmAddingLayer:object:object2:object3:` | `v48@0:8:16@24@32@40` |
| Chọn layer | `MultiLayerWizEffectVC` | `-selectLayerNum:flash:`, `-setButtonLayerNum:selected:` | |
| Layer đang chọn | `MultiLayerWizEffectVC` | `-lastSelectedLayerNum`, `-borderedLayerNum` | |
| Placeholder của preset | `MultiLayerWizEffectVC` | `-placeHolderForType:`, `-placeHolderForType:layerNum:` | |
| Nạp preset/code | `MultiLayerWizEffectVC` | `-importNewPreset:keyFrameAction:qrDurationInFrames:`, `-importOldPreset:` | |
| Refresh sau khi sửa | `MultiLayerWizEffectVC` | `-engineResync`, `-refreshDisplay`, `-updatePreview`, `-renderPreView` | |

### 3.3 Trạng thái / undo

| Việc | Class | Selector |
|---|---|---|
| Snapshot state | `MultiLayerWizEffectVC` | `-saveState`, `-stateData` |
| Khôi phục | `MultiLayerWizEffectVC` | `-restoreSavedState:`, `-maybeLoadState` |
| Dự án hiện tại | `MultiLayerWizEffectVC` | `-project`, `-getSceneIndex` |

---

## 4. UI / UX

**Nút nổi** (luôn hiện khi app active, ẩn khi app vào background):
- Chạm → panel.
- Kéo → đổi vị trí, lưu `NSUserDefaults`.
- Chạm 2 lần → thu gọn/mở.

**Panel chính:**

```
┌──────────────────────────────┐
│  VSToolbox            ✕      │
├──────────────────────────────┤
│  📷  Nhập ảnh cho lớp…       │  → chọn layer (danh sách) hoặc "Tất cả lớp ảnh"
│  🖼  Nhập ảnh toàn bộ        │  → multi-select ảnh, gán tuần tự
│  🔢  Chọn lớp theo số        │  → grid 1..40, có badge loại layer
│  ──────────────────────────  │
│  🕘  Code gần đây           │  → list, tap = copy, long-press = áp dụng
│  📋  Dán code từ clipboard  │  → tự phát hiện prefix
│  🔳  QR của code gần nhất   │  → lưu vào Photos
│  ──────────────────────────  │
│  🧹  Xoá nội dung lớp       │
│  ♻️  Hoàn tác thao tác gần  │
│  ⚙️  Cài đặt                │
└──────────────────────────────┘
```

**Luồng "Nhập ảnh toàn bộ":**
1. Quét layer 1..40 qua `layerAtLayerNum:`.
2. Lọc: `layerType == photo` **và** `origAssetInfo == nil` (slot trống/placeholder).
3. Hiện danh sách "sẽ gán vào lớp: 3, 5, 7, 9" để xác nhận.
4. Mở PHPicker (chọn nhiều ảnh).
5. Resize ảnh (ImageIO, cạnh dài ≤ 2048) → gọi `setupImage:layerNum:layerType:clearMask:NO`.
6. `engineResync` + `refreshDisplay`, hiện toast "Đã gán 4/4 lớp".
7. Lưu snapshot trước khi gán để có thể hoàn tác.

---

## 5. Roadmap

### Phase 0 — Build & xác minh (0.5–1 buổi)
- Dựng toolchain (GitHub Actions hoặc WSL2 + Theos).
- Build dylib rỗng, chèn load command, ký lại, cài, thấy banner "VSToolbox loaded".
- **Log bảng `layerType`**: mở preset có đủ loại layer, log `layerType` của từng ô
  → chốt hằng số enum (photo / text / overlay / null / color / gif / zap / 3D / particle).

### Phase 1 — Code (1 buổi) ⭐ ít rủi ro nhất
- Nút nổi + panel + toast.
- Swizzle `importedData:code:` toàn bộ class → lưu lịch sử (code, thời gian, class nguồn).
- Màn "Code gần đây": copy, áp dụng lại, xem QR, xoá từng mục.
- Hook `saveCodeToPlist:desc:` để bắt cả code lưu từ thư viện QR.
- Dán từ clipboard + kiểm tra `validCode:` trước khi áp dụng.

### Phase 2 — Nhập ảnh (2–3 buổi)
- Layer inspector (đọc): số, loại, có nội dung hay chưa, tên placeholder.
- Gán 1 lớp: chọn ảnh → `setupImage:...`.
- Gán toàn bộ lớp ảnh trống: multi-select, gán tuần tự/ngẫu nhiên.
- Snapshot/rollback trước khi gán.
- Xử lý lỗi: layer 3D/particle không nhận ảnh, layer đã có nội dung → hỏi ghi đè.

### Phase 3 — Mở rộng (tuỳ chọn)
- Profile ảnh theo số lớp (dùng lại cho preset khác).
- Auto-fit ảnh sau khi gán (scale/center theo `MultiLayerLayerParameters`).
- Gán video hàng loạt cho video layer (`setupVideoLayer:...`).
- Thư viện ảnh nhanh: chọn từ album riêng, lưu "bộ ảnh" để tái dùng.
- Xuất/nhập lịch sử code ra JSON, chia sẻ.
- Nút "xoá nội dung tất cả lớp ảnh", "nhân đôi layer", "chọn layer theo loại".
- Badge đếm số layer trống ngay trên nút nổi.

---

## 6. Gợi ý tính năng thêm (chọn lọc)

1. **Auto-fill theo preset**: nhớ "bộ ảnh" cho từng code → lần sau nhập code là tự gán lại.
2. **Paste & Apply**: copy code ở nơi khác, mở app, nút nổi hiện badge → 1 chạm áp dụng.
3. **QR nhanh**: từ code gần nhất tạo QR full-screen để quét sang máy khác.
4. **Layer map**: lưới 40 ô, ô nào có nội dung/trống/loại gì, chạm để chọn hoặc xoá.
5. **Batch video**: tương tự ảnh nhưng cho lớp video (dùng cho preset nhiều clip).
6. **Đếm & cảnh báo**: "preset này thiếu 3 slot ảnh" trước khi render.
7. **Chống mất dữ liệu**: snapshot tự động trước mọi thao tác hàng loạt + rollback 1 chạm.
8. **Import ảnh theo tên file** (nếu ảnh lấy từ Files): gán theo thứ tự alphabet.

---

## 7. Rủi ro & cách xử lý

| Rủi ro | Xử lý |
|---|---|
| Private API đổi theo version | Chỉ dùng selector đã xác minh; luôn `respondsToSelector:` + fallback; gom vào 1 lớp `VSCompat` |
| Sai enum `layerType` → gán nhầm | Phase 0 log thực tế; nếu vẫn sai thì dò bằng `isNullLayer` + `textDictionary` + `origAssetInfo` |
| Gán ảnh sai luồng → crash GL/engine | Gọi trên main thread, sau mỗi lần gán `engineResync` + delay 50ms trước `refreshDisplay` |
| Ảnh quá lớn → chậm/oom | Resize bằng ImageIO trước khi gán |
| Mất state khi thao tác hàng loạt | `saveState` + lưu `stateData` ra file trước khi gán |
| Ký lại | Bắt buộc: Sideloadly / Esign / AltStore / TrollFools (jailbreak) |
| IPA nguồn khác chưa giải mã | Cần IPA đã giải mã; nếu chưa, dùng công cụ sideload có sẵn tính năng inject |
| App update làm lệch offset | Script inject đọc load command động, không hardcode offset |

---

## 8. Build & test trên Windows

Windows không build iOS dylib native. Hai đường:

**A. GitHub Actions (khuyến nghị)** — workflow `build.yml`:
- cài Theos + toolchain + iPhoneOS SDK
- `make dylib` → artifact `.dylib`
- ưu điểm: không cần cài gì, build lặp lại dễ

**B. WSL2 + Theos** — cài Ubuntu, chạy `install-theos`, build local.

**Quy trình phát hành:**
1. Build `VSToolbox.dylib` (arm64 + arm64e).
2. `python tools/inject.py --ipa in.ipa --dylib VSToolbox.dylib --out out.ipa`
   - chèn `LC_LOAD_DYLIB @executable_path/Frameworks/VSToolbox.dylib`
   - copy dylib vào `Frameworks/`
   - dùng slack có sẵn, không dịch file → an toàn cho binary đã giải mã
3. Ký lại bằng Sideloadly/Esign (hoặc TrollFools nếu jailbreak).
4. Test matrix:
   - preset 1 / 3 / 9 lớp ảnh
   - preset có text + overlay + color (đảm bảo không gán nhầm)
   - preset đã có ảnh (test ghi đè)
   - iPad + iPhone, iOS 17.2+

---

## 9. Cần bạn chốt

1. **Thiết bị/iOS** đang dùng để test? (ảnh hưởng arm64e, API PHPicker)
2. **Ký app bằng gì**: Sideloadly / Esign / AltStore / TrollStore / jailbreak?
3. **Ảnh đầu vào** lấy từ đâu: Photos (multi-select) hay folder trong Files?
   Thứ tự gán: lần lượt theo layer number / theo thứ tự chọn / ngẫu nhiên?
4. Có cần gán cả **lớp video** không, hay chỉ lớp ảnh tĩnh?
5. **Code gần đây**: lưu bao nhiêu bản (10/50/không giới hạn)? Có cần đồng bộ ra file để backup?
6. Ngôn ngữ UI: tiếng Việt, tiếng Anh, hay cả hai?
