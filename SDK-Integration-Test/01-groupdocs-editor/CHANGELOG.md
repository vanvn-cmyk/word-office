# Changelog — GroupDocs.Editor integration test

Theo dõi riêng quá trình test GroupDocs.Editor Cloud API (ứng viên engine đầu tiên cho
Word/Excel/PowerPoint edit thật). Tách khỏi CHANGELOG.md của app "Word Office" chính vì đây
chỉ là harness test độc lập, chưa đụng Swift/Xcode. Entry mới nhất ở trên cùng.

---

## 2026-09-10 — Session 1: setup + fix API upload + phát hiện bug xlsx

### Mục tiêu
Đánh giá GroupDocs.Editor Cloud API — ứng viên ưu tiên #1 vì self-serve, không cần dựng
server, phủ đủ docx/xlsx/pptx với effort thấp nhất trong các phương án đã research
(so với ONLYOFFICE self-host / offline-WASM, Syncfusion thiếu PPT).

### Đã làm
- Build harness Node.js + Express (`server.js`) + UI đơn giản (`public/index.html`):
  chọn file → upload → convert sang HTML editable → sửa trực tiếp trong iframe → save →
  convert lại về file gốc → download.
- Đăng ký GroupDocs Cloud free trial (150 call/tháng), tạo Internal Storage + Application,
  lấy Client ID/Secret, lưu vào `.env` (gitignored, không commit).
- **Fix quan trọng — endpoint upload sai theo docs công khai**: docs GroupDocs ghi
  `POST` + raw octet-stream, nhưng thực tế gọi live API trả `405` (POST không được phép).
  Đổi sang `PUT` vẫn lỗi `500 "Synchronous operations are disallowed..."` — cuối cùng xác
  định đúng: **`PUT` + `multipart/form-data` với field tên `File`** mới chạy được
  (`200 {"uploaded":[...],"errors":[]}`). Đã verify bằng curl trước khi sửa code.
- Test file **docx** (CV thật) — round-trip load→edit→save chạy được sau khi fix upload.

### Bug phát hiện — GroupDocs bug, không phải lỗi code mình
- File **xlsx** (`remote_tv_funnel.xlsx`) có dùng **Data Bar** (conditional formatting của
  Excel) → `editor/load` trả `500 internalError`: lỗi parse HTML nội bộ của GroupDocs
  (`mso-databar` markup bị lẫn quote `'`/`"` làm parser của họ crash). Chưa rõ đây là lỗi
  riêng với Data Bar hay lan rộng ra các conditional formatting khác (icon set, color scale,
  pivot table...).

### Quyết định
- **Chưa build fallback view-only** cho trường hợp load fail (cần thêm 1 engine convert
  riêng, chưa biết tần suất thật để justify effort đó — tránh over-engineer sớm).
- Chỉ implement baseline an toàn trong harness: (1) file gốc user không bao giờ bị đụng —
  mọi xử lý chỉ trên bản copy upload lên cloud; (2) error message tiếng Anh, dễ hiểu, kèm
  phần "Technical details" thu gọn chứa raw error — thay vì dump JSON thô làm nội dung chính.

### Chưa làm / để mai
- [ ] Test thêm 2-3 file xlsx khác (có/không Data Bar, có pivot table/merged cell) để biết
      bug này hiếm hay phổ biến.
- [ ] Test 1 file **pptx thật có animation/chart** — đây là rủi ro fidelity #1 đã flag từ đầu,
      chưa test.
- [ ] Nếu GroupDocs qua được cả 2 test trên → cân nhắc spike thật vào Xcode project (cần
      xin go-ahead riêng theo rule.md của app chính).
- [ ] Nếu không qua → chuyển hướng Syncfusion (thiếu PPT) hoặc ONLYOFFICE self-host.
- [ ] Report bug Data Bar cho GroupDocs support (kèm file mẫu) — chưa làm.

### Cách resume
```
cd "SDK-Integration-Test/01-groupdocs-editor"
npm start
# mở http://localhost:5177
```
Client ID/Secret đã có sẵn trong `.env`, không cần đăng ký lại.
