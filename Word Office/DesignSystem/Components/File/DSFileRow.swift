import SwiftUI

/// Design doc §10.3 — thumbnail/icon · name · metadata · overflow.
struct DSFileRow: View {
    let ref: DocumentRef

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            DSDocumentTypeBadge(kind: ref.kind)
                .frame(width: DSSize.fileIcon, height: DSSize.fileIcon)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(ref.name)
                    .font(DSFont.headline)
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)

                Text(ref.modifiedAt, style: .relative)
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
