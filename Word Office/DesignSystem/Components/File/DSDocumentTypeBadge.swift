import SwiftUI

/// Design doc §6.8 — document-type color only on file icons/badges.
struct DSDocumentTypeBadge: View {
    let kind: DocumentKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
                .fill(backgroundColor)

            Image(systemName: kind.systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(iconColor)
        }
    }

    private var backgroundColor: Color {
        switch kind {
        case .docx, .doc:                Color.dsDocumentWord.opacity(0.12)
        case .xlsx, .xls:                Color.dsDocumentSpreadsheet.opacity(0.12)
        case .pptx, .ppt:                Color.dsDocumentPresentation.opacity(0.12)
        case .pdf:                       Color.dsDocumentPDF.opacity(0.12)
        case .txt, .rtf, .markdown,
             .hwp, .hwpx:                Color.dsDocumentGeneric.opacity(0.12)
        }
    }

    private var iconColor: Color {
        switch kind {
        case .docx, .doc:                .dsDocumentWord
        case .xlsx, .xls:                .dsDocumentSpreadsheet
        case .pptx, .ppt:                .dsDocumentPresentation
        case .pdf:                       .dsDocumentPDF
        case .txt, .rtf, .markdown,
             .hwp, .hwpx:                .dsDocumentGeneric
        }
    }
}

#Preview {
    HStack(spacing: DSSpacing.md) {
        ForEach(DocumentKind.allCases.prefix(6), id: \.self) { kind in
            DSDocumentTypeBadge(kind: kind)
                .frame(width: DSSize.fileIcon, height: DSSize.fileIcon)
        }
    }
    .padding()
}
