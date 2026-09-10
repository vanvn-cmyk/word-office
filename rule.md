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

## 7. Luôn load `/swiftui-expert-skill` KHI viết code SwiftUI (không chỉ review)

Rule #4 đã yêu cầu review sau khi viết. Rule này bổ sung: **TRƯỚC hoặc TRONG lúc triển khai
code SwiftUI mới / sửa View / state / animation / layout hiện có**, phải LOAD `/swiftui-expert-skill`
để consult reference (`references/latest-apis.md`, `references/liquid-glass.md`,
`references/state-management.md`, `references/animation-basics.md`, v.v.) TRƯỚC khi quyết định
API/pattern. Áp dụng cho mọi file `.swift` trong `Views/`, `App/`, `DesignSystem/`, và ViewModel
nếu đụng state observable.

Lý do: skill chứa knowledge iOS 26+ API mới nhất, deprecated API, patterns HIG. Đã ship nhầm
`.interactiveSpring` vi phạm rule "no spring physics for UI chrome" và `.buttonBorderShape(.circle)`
không work trên iOS 26 toolbar auto-glass — đó là lý do skill phải load TRƯỚC khi quyết định
pattern, không phải fix sau qua review. Skill portable qua repo (`.agents/skills/swiftui-expert-skill/`,
xem rule #4.1).

Ngoại lệ: chỉ sửa 1 dòng thuần logic không đụng API SwiftUI/UIKit (VD `.disabled(x || y)`, đổi
tên biến) — không cần load. Đụng đến View builder, modifier, state, animation, layout, gesture,
accessibility, focus, sheet, navigation — LUÔN load.

## 8. Compact bottom sheet — cách tính height và tránh dead space

Áp dụng cho mọi `.sheet` dùng `.presentationDetents([.height(N)])` (ví dụ: `ImageConvertPickerSheet`, `ScanSourcePickerSheet`, bất kỳ sheet picker nhỏ nào).

### Quy tắc bắt buộc

**Không dùng `Spacer()` bên trong VStack của sheet** — `Spacer` luôn expand để lấp đầy phần còn lại của detent, tạo ra dead space trống ở cuối sheet (đúng bug xảy ra ở `ImageConvertPickerSheet` ngày 2026-09-10).

**Thay thế**: dùng fixed padding ở cuối VStack:
```swift
VStack(spacing: 0) {
    // ... nội dung sheet ...
}
.padding(.bottom, DSSpacing.md)   // ← fixed, không phải Spacer
.presentationDetents([.height(N)])
```

### Cách tính N (detent height)

Cộng lần lượt chiều cao các component, dùng token DSSpacing:

| Token | pt |
|-------|----|
| xxs   | 4  |
| xs    | 8  |
| sm    | 12 |
| md    | 16 |
| lg    | 20 |
| xl    | 24 |
| xxl   | 32 |

**Pattern chuẩn cho sheet có drag indicator + title + N rows:**

```
drag indicator = top_pad(sm=12) + height(4) + bottom_pad(md=16)  = 32pt
title row      = font_height(~20) + bottom_pad(md=16)            = 36pt
mỗi row        = vertical_pad(sm=12) × 2 + icon_size(36)         = 60pt
divider giữa rows                                                 ≈ 1pt
spacing xs=8 giữa mỗi child trong VStack (xs=8)                  = N×8pt
bottom padding                                                     = 16pt (md)
```

**Ví dụ thực tế** (`ImageConvertPickerSheet`, 2 rows):
```
32 + 36 + 60 + 8 + 1 + 8 + 60 + 16 = 221pt → dùng .height(224) (thêm 3pt buffer)
```

### Checklist trước khi ship một compact sheet

- [ ] Không có `Spacer()` / `Spacer(minLength:)` bên trong VStack chính
- [ ] Có `.padding(.bottom, DSSpacing.md)` cuối VStack
- [ ] `.presentationDetents([.height(N)])` với N tính theo công thức trên
- [ ] Đã chạy app thật hoặc simulator để xác nhận không còn dead space

---

*File này là rule bắt buộc cho project Word Office — đọc trước khi bắt đầu bất kỳ phiên làm
việc nào có liên quan tới việc viết code.*
