# Working rules — Word Office project

## 1. No code without go-ahead

Trước khi viết/sửa bất kỳ file code nào (Swift, protocol, implementation, DI wiring, test...),
phải trình bày kế hoạch/scope trước và **chờ user chốt** ("ok làm đi" / xác nhận rõ ràng).
Không tự ý implement chỉ vì task nghe hợp lý hay nằm trong roadmap đã có sẵn — kể cả khi
roadmap (CHANGELOG, PHASE_1_ARCHITECTURE.md, Phase0-Implementation-Logic*.md) đã mô tả rõ
scope, vẫn phải hỏi trước khi bắt tay viết.

**Ngoại lệ**: đọc code, tìm hiểu kiến trúc, tổng hợp trạng thái hiện tại — không cần hỏi trước
(đây là research, không phải thay đổi code).

## 2. File UI — luôn hỏi có làm HTML mockup trước không

Trước khi viết code UI thật (SwiftUI View), phải hỏi user có muốn làm HTML mockup preview
trước không. Chỉ triển khai code UI thật sau khi user chốt trên mockup (hoặc chốt bỏ qua
bước mockup nếu user chủ động nói vậy).

## 3. Nguồn xác định scope/feature MVP

**`Phase0-Implementation-Logic-v2.md` là nguồn CHÍNH** để biết MVP gồm những tính năng gì,
scope tới đâu, logic xử lý thế nào cho từng mục (11 hạng mục MVP + Phụ lục A/B ngoài MVP).
Trước khi implement bất kỳ tính năng nào, đọc lại đúng section liên quan trong file này.

`PHASE_1_ARCHITECTURE.md` chỉ dùng tham khảo **pattern kiến trúc** (MVVM/SOLID/DI/4-layer,
Store tách domain §3.1.1, SOLID mapping §3.2) — KHÔNG dùng để soi/bắt lỗi cấu trúc thư mục
chi tiết (path file, tên folder cụ thể) nếu nó không khớp `Phase0-Implementation-Logic-v2.md`.
Khi 2 file mâu thuẫn nhau về scope/feature, `Phase0-Implementation-Logic-v2.md` thắng.

## 4. Review liên tục — 2 agent cố định

Mọi code Swift mới/sửa đổi đều phải qua review bằng 2 skill sau, **liên tục theo từng đợt**
(không dồn tích cả buổi rồi review 1 lần cuối):

- **`/swiftui-expert-skill`** — cho code SwiftUI (View, `@Observable`, state management,
  animation, list identity...). Chỉ chạy được khi session có working directory nằm trong
  project (project-scoped skill) — nếu không gọi được từ đây, nhắc user chạy trong session
  đúng thư mục.
- **`/code-review`** — cho code logic/service/concurrency/protocol. Chạy được từ bất kỳ đâu
  (truyền path project vào `args`).

Review xong mới coi task là "done" — không tự báo hoàn thành khi chưa qua review tương ứng
với loại code vừa viết.

### 4.1 Portability skill giữa các máy (2026-09-02)

User có thể chuyển qua máy công ty để làm tiếp — dưới đây là skill nào đi theo được repo (qua
git/copy folder), skill nào không cần lo vì có sẵn mọi nơi, skill nào KHÔNG đi theo được:

- **Đi theo repo, đã vendor sẵn** (`.agents/skills/<tên>/`, khoá version ở `skills-lock.json`):
  `swiftui-expert-skill`, `ui-ux`. Chỉ hoạt động như "project-scoped skill" khi session mở đúng
  thư mục project này.
- **Có sẵn mọi máy chạy Claude Code** (built-in, không phải file cài riêng — không cần vendor):
  `/code-review`, `product-designer`, `ui-ux-pro-max`, `product-brainstorming`,
  `onboarding-optimization`. Đã kiểm tra `~/.claude/skills/<tên>/` trên máy hiện tại — thư mục
  rỗng (0 byte, không có `SKILL.md` cục bộ nào) → xác nhận đây là skill built-in của Claude
  Code, không phải third-party skill cài qua `npx skills add`.
- **KHÔNG đi theo được** — mọi thứ ở `/Users/vuvan/.claude/projects/-Users-vuvan/memory/`
  (memory tự động của Claude, gắn với máy hiện tại/tài khoản, không nằm trong repo). Trạng thái
  project thật đã ghi đủ trong `CHANGELOG.md`/`GUIDELINE.md` (2 file này đi theo repo) — coi đó
  là nguồn chính khi resume ở máy khác, không phụ thuộc memory.

## 5. Code phải đảm bảo tính kế thừa/mở rộng (OCP)

Theo đúng SOLID mapping ở `PHASE_1_ARCHITECTURE.md` §3.2 — cụ thể **OCP**: thêm format/tính
năng mới = tạo implementation mới conform protocol có sẵn (vd `HWPDocumentReading: DocumentReading`),
**KHÔNG sửa code cũ** (ViewModel, protocol, DI container) để nhét thêm case. Đổi SDK/backend
(Artifex → khác, GRDB → SwiftData...) = swap implementation, không đổi chỗ gọi.

Không có nghĩa là over-engineer/thêm abstraction thừa cho trường hợp chưa xảy ra — vẫn theo
nguyên tắc gốc trong `~/CLAUDE.md` (không thiết kế cho hypothetical requirement). Chỉ đảm bảo
đúng ranh giới protocol/DI đã có sẵn trong kiến trúc, không phá nó khi thêm code mới.

## 6. App này rất quan trọng — cẩn thận tối đa

Đây không phải app thử nghiệm/demo — làm cẩn thận, không đoán mò API/behavior khi không chắc
(tra cứu source thật hoặc hỏi user thay vì đoán — như vụ `ZIPFoundation`/`Task.detached` đã
gặp). Ưu tiên đúng hơn nhanh. Mọi thay đổi ảnh hưởng dữ liệu người dùng thật (vd ghi đè file
`.docx`) phải có safety-guard, không được âm thầm phá dữ liệu (đã áp dụng ở `DOCXCodec`).

---

*File này là rule bắt buộc cho project Word Office — đọc trước khi bắt đầu bất kỳ phiên làm
việc nào có liên quan tới việc viết code.*
