# ONLYOFFICE — Fidelity Test Harness

Test round-trip fidelity của ONLYOFFICE Document Server cho DOCX/XLSX/PPTX.
Độc lập hoàn toàn với project "Word Office" chính.

## Kiến trúc

```
Browser → index.html (Node.js :5178)
         → ONLYOFFICE editor JS (Document Server :8090)
         → api/file/:id (Node.js serve file gốc)
         → user chỉnh sửa
         → Ctrl+S → ONLYOFFICE POST /api/callback/:id
         → Download kết quả
```

Document Server chạy trong Docker, Node.js chạy ngoài host.

## Setup

### Bước 1 — Cài Docker Desktop
https://www.docker.com/products/docker-desktop/ (free, cài lần đầu ~5 phút)

### Bước 2 — Khởi động Document Server

```bash
cd "SDK-Integration-Test/02-onlyoffice"
docker compose up -d
```

Lần đầu pull image ~1GB, mất vài phút. Sau đó chờ Document Server sẵn sàng:

```bash
# Chờ cho đến khi thấy "Document Server is running"
docker compose logs -f onlyoffice | grep -i "running\|error"
```

Hoặc mở http://localhost:8090 — khi thấy trang ONLYOFFICE là OK.

### Bước 3 — Chạy Node.js harness

```bash
npm install
npm start
# mở http://localhost:5178
```

## Cách test

1. Chọn file (docx/xlsx/pptx — ưu tiên file có ảnh/chart/animation)
2. Bấm "Open & Edit" → ONLYOFFICE editor hiện ra
3. Sửa gì đó trong document
4. Bấm **Ctrl+S** (hoặc Cmd+S) để save
5. Khi "Download Result" sáng lên → bấm download
6. Mở file kết quả bằng Word/Excel/PowerPoint thật → so sánh với file gốc

## Lưu ý

- File gốc không bao giờ bị thay đổi — chỉ làm việc với bản copy
- Upload folder (`uploads/`) bị gitignore, không commit
- Nếu ONLYOFFICE không load được → chạy `docker compose logs onlyoffice` để xem lỗi
