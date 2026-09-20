# Session 14 Delta — riêng để merge sang máy công ty

**Đây KHÔNG phải bản project đầy đủ.** Chỉ chứa các file MỚI/SỬA trong Session 14
(2026-09-09, làm trên máy cá nhân) — path bên trong giữ nguyên đúng vị trí gốc trong project,
để bạn (hoặc Claude bên máy công ty) so sánh/merge tay từng file vào bản project thật đang có
ở máy công ty (bản đó có feature khác không nằm ở đây, KHÔNG được ghi đè tuỳ tiện).

## Có gì trong này

```
Word Office.xcodeproj/project.pbxproj     ← ⚠️ RỦI RO CAO, xem mục cảnh báo bên dưới
Word Office/Views/Settings/SettingsView.swift        ← ⚠️ RỦI RO CAO, xem bên dưới
Word Office/Views/Settings/RatingDialogView.swift    ← file MỚI hoàn toàn, an toàn copy thẳng
Word Office/Views/Paywall/PaywallView.swift          ← file MỚI hoàn toàn, an toàn copy thẳng
Word Office/Views/Library/LibraryView.swift          ← sửa nhẹ (2 chỗ, xem bên dưới)
Word Office/Views/Root/RootView.swift                ← sửa nhẹ (2 chỗ, xem bên dưới)
Word Office/Views/Tabs/ToolsTabView.swift            ← sửa nhẹ, đã revert lại gần như nguyên bản
Word Office/Assets.xcassets/SettingsPremiumBanner.imageset/   ← asset MỚI
Word Office/Assets.xcassets/PaywallHeroIllustration.imageset/ ← asset MỚI
Word Office/Assets.xcassets/IconOfficeSupplies.imageset/      ← asset MỚI (hiện KHÔNG dùng ở đâu)
Word Office/Assets.xcassets/IconPencilCase.imageset/          ← asset MỚI (đang active ở tab bar)

CHANGELOG-personal-machine.md   ← toàn bộ CHANGELOG.md của máy cá nhân, để đọc mục "Session 14"
GUIDELINE-personal-machine.md   ← toàn bộ GUIDELINE.md của máy cá nhân, để đọc "Where we left off"
```

## ⚠️ 2 file rủi ro xung đột cao nhất — ĐỪNG ghi đè trực tiếp

1. **`Word Office.xcodeproj/project.pbxproj`**
   Bản này có thêm 1 Unit Test target ("Word OfficeTests") không tồn tại trước đó. Nếu máy
   công ty đã tự thêm file/target mới nào khác trong `.pbxproj` của họ (rất dễ xảy ra vì đây
   là dạng file dễ đụng), **ghi đè thẳng file này sẽ xoá mất các thay đổi đó**. Cách an toàn:
   mở project trên Xcode ở máy công ty, tự thêm target "Word OfficeTests" bằng tay qua UI
   Xcode (File → New → Target → Unit Testing Bundle, trỏ vào 4 file có sẵn trong
   `Word OfficeTests/`), thay vì copy đè file `.pbxproj` này.

2. **`Word Office/Views/Settings/SettingsView.swift`**
   Bạn nói máy công ty đang có "theme code khác" — file này chứa cả section "Appearance"
   (Theme picker), nên rất có khả năng đụng đúng chỗ máy công ty đang sửa. **Đừng copy đè**
   — mở file này cạnh bản máy công ty, diff bằng mắt (hoặc nhờ Claude bên đó), merge tay.
   Những gì file này có mà bản cũ không có: banner Premium ở đầu, icon cho từng row, section
   "General" (Share app/Rate app/Privacy Policy/Terms of Service — trước đó tách "Legal"
   riêng), sheet mở `RatingDialogView` + `PaywallView`.

## Các file còn lại — tương đối an toàn

- `RatingDialogView.swift`, `PaywallView.swift` — file hoàn toàn mới, không tồn tại ở máy
  công ty trước đó → copy thẳng vào đúng path là được.
- `LibraryView.swift` — chỉ thêm: 1 dòng `@State private var isPaywallPresented`, đổi
  action của `premiumButton` thành `isPaywallPresented = true`, thêm 1 modifier
  `.sheet(isPresented: $isPaywallPresented) { PaywallView() }`. Nếu máy công ty không sửa
  gì gần khu vực này, copy đè an toàn — nhưng vẫn nên diff nhanh cho chắc.
- `RootView.swift` — chỉ đổi 1 dòng gọi `tabBarButton(.tools, ...)` (thêm icon custom) +
  thêm nhánh `if isCustomAsset` trong hàm `tabBarButton`. Diff nhanh trước khi ghi đè.
- `ToolsTabView.swift` — cuối session đã revert gần hết về bản gốc, hiện không còn khác biệt
  đáng kể so với trước Session 14 (thử rồi bỏ icon custom cho Fill Form). An toàn không cần
  copy file này nếu ngại — không có tính năng mới nào phụ thuộc vào nó.

## Merge xong thì làm gì tiếp

1. Đọc `GUIDELINE-personal-machine.md` mục "⭐ Where we left off" → "Session 14" để biết
   **việc dở dang cần làm tiếp trước tiên**: bug khoảng trống (dead space) ở hero Paywall.
2. Đọc `CHANGELOG-personal-machine.md` mục "Session 14" để biết đầy đủ lý do từng quyết định
   (tại sao đổi màu, tại sao bỏ style X...) — tránh làm lại y hệt lỗi đã tự sửa trong session.
3. Sau khi merge xong, nên **thêm 1 mục vào CHANGELOG/GUIDELINE thật của máy công ty** ghi rõ
   "đã merge Session 14 từ máy cá nhân, ngày ..." để 2 bên không bị lệch lịch sử nữa.
