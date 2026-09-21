# GroupDocs.Editor — Test Fidelity Harness

Web harness đơn giản để test round-trip fidelity của GroupDocs.Editor Cloud API
(docx/xlsx/pptx → HTML editable → convert lại về format gốc). Không đụng gì tới
project "Word Office" thật — hoàn toàn độc lập.

## Setup

1. Đăng ký free trial tại https://dashboard.groupdocs.cloud (150 API call/tháng, không cần thẻ)
2. Vào mục "Applications" → lấy **Client ID** + **Client Secret**
3. Copy `.env.example` thành `.env`, điền 2 giá trị đó vào
4. `npm install`
5. `npm start` → mở http://localhost:5177

## Cách test

1. Chọn 1 file thật (docx/xlsx/pptx — ưu tiên pptx có chart/table/animation vì đây là rủi ro
   fidelity lớn nhất đã note trong memory)
2. Bấm "Load & Edit" → nội dung hiện trong iframe, click vào để sửa trực tiếp
3. Bấm "Save" → tự động download file kết quả (đã convert lại về .docx/.xlsx/.pptx)
4. Mở file vừa download bằng Word/Excel/PowerPoint (hoặc Pages/Numbers/Keynote) thật để
   so sánh với file gốc — đây là bước quan trọng nhất, không tin vào việc hiển thị đúng
   trong browser vì đó chỉ là bước trung gian (HTML), không phải bước quyết định fidelity.

## Lưu ý

- Endpoint/schema trong `server.js` được tổng hợp từ tài liệu chính thức
  (`docs.groupdocs.cloud/editor/...`), đã đối chiếu qua 3 nguồn độc lập nhưng **chưa test
  live** — nếu GroupDocs trả lỗi khác với kỳ vọng, log lỗi sẽ hiện trực tiếp trong ô status
  trên UI (kèm status code + response body gốc) để biết chính xác cần sửa gì.
- File test tạm được lưu ở folder `sdk-test/` trong GroupDocs Cloud Storage của bạn — không
  ảnh hưởng gì tới máy hay project thật.
