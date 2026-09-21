# Changelog — ONLYOFFICE integration test

---

## 2026-09-10 — Session 1: build harness

### Lý do chuyển sang ONLYOFFICE
GroupDocs.Editor Cloud bị loại sau test pptx: images không load, visual layout mất hoàn toàn.
Report phân tích IPA của đối thủ (OfficeWord_Logic_Processing.md) xác nhận ONLYOFFICE +
x2t.wasm là stack khả thi — chạy on-device, không cần server, fidelity tốt hơn GroupDocs.

### Đã làm
- Build harness Node.js + Express + ONLYOFFICE Document Server (Docker)
- Upload file → Node.js lưu local → ONLYOFFICE fetch qua `/api/file/:id`
- Save (Ctrl+S) → ONLYOFFICE POST `/api/callback/:id` → Node.js download và lưu edited file
- Poll `/api/status/:id` → UI unlock "Download Result" khi file sẵn sàng
- Error handling: Document Server không chạy → hiện hướng dẫn rõ ràng
- URL rewriting trong callback: thay hostname Docker bằng `localhost:DOCS_PORT`

### Chưa làm / cần test
- [ ] Cài Docker Desktop, chạy `docker compose up -d`, verify Document Server OK
- [ ] Test docx có ảnh embedded
- [ ] Test xlsx có chart + merged cell
- [ ] Test pptx có animation + ảnh — đây là bài test quan trọng nhất (GroupDocs đã fail)
- [ ] So sánh file download với file gốc bằng Word/Excel/PowerPoint thật
- [ ] Nếu pass → nghiên cứu cách bundle ONLYOFFICE + x2t.wasm vào iOS app (không cần server)

### Cách resume
```bash
cd "SDK-Integration-Test/02-onlyoffice"
docker compose up -d   # khởi động Document Server (nếu chưa chạy)
npm start              # http://localhost:5178
```
