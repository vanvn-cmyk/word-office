import SwiftUI

/// Design doc §10.3 — thumbnail/icon · name · metadata · overflow.
struct DSFileRow: View {
    let ref: DocumentRef

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            DocumentKindIcon(kind: ref.kind)
                .frame(width: DSSize.fileIcon, height: DSSize.fileIcon)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(ref.name)
                    .font(DSFont.headline)
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)

                // `format: .relative(presentation: .named)` renders ONCE at
                // display time using natural language — "yesterday", "6 days
                // ago", "now". Deliberately not `style: .relative`, which is
                // SwiftUI's live-updating DateStyle: it re-renders every
                // second while below the minute (so a just-created file
                // shows "0 secs, 1 sec, 2 secs, …" ticking up in real time)
                // and outputs a compound-duration format like "6 days,
                // 3 hrs" without an "ago" suffix, which reads as a countdown
                // rather than an age.
                Text(ref.modifiedAt, format: .relative(presentation: .named))
                    .font(DSFont.subheadline)
                    .foregroundStyle(Color.dsTextSecondary)
            }

            Spacer(minLength: DSSpacing.xs)
        }
        .padding(.vertical, DSSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        DSFileRow(ref: .init(
            name: "Q4 Report.docx",
            url: URL(fileURLWithPath: "/tmp/Q4 Report.docx"),
            modifiedAt: Date().addingTimeInterval(-3600),
            kind: .docx
        ))
        DSFileRow(ref: .init(
            name: "Budget.xlsx",
            url: URL(fileURLWithPath: "/tmp/Budget.xlsx"),
            modifiedAt: Date().addingTimeInterval(-86400),
            kind: .xlsx
        ))
    }
}
