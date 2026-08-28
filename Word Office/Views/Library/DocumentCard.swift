import SwiftUI

/// One row in the Library list — type badge · name/status/modified · optional reminder chip.
/// Stateless leaf; parent wires navigation via `onTap`.
struct DocumentCard: View {
    let entry: LibraryEntry
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: DSSpacing.sm) {
                DSDocumentTypeBadge(kind: entry.document.kind)
                    .frame(width: DSSize.fileIcon, height: DSSize.fileIcon)

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(entry.document.name)
                        .font(DSFont.headline)
                        .foregroundStyle(Color.dsTextPrimary)
                        .lineLimit(1)

                    HStack(spacing: DSSpacing.xs) {
                        StatusPill(status: entry.metadata.status)
                        Text(entry.document.modifiedAt, style: .relative)
                            .font(DSFont.footnote)
                            .foregroundStyle(Color.dsTextSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: DSSpacing.xs)

                if let remindAt = entry.metadata.remindAt {
                    ReminderChip(date: remindAt)
                }
            }
            .padding(.vertical, DSSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [entry.document.name, entry.metadata.status.displayName]
        if entry.metadata.remindAt != nil {
            parts.append("has reminder")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Sub-components

private struct StatusPill: View {
    let status: DocumentStatus

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: status.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(status.displayName)
                .font(DSFont.caption)
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, 2)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch status {
        case .draft:    Color.dsStatusWarning
        case .reviewed: Color.dsTextSecondary
        case .signed:   Color.dsStatusSuccess
        case .sent:     Color.dsBrandPrimary
        }
    }

    private var background: Color {
        switch status {
        case .draft:    Color.dsStatusWarningBackground
        case .reviewed: Color.dsSurfaceSecondary
        case .signed:   Color.dsStatusSuccessBackground
        case .sent:     Color.dsBrandPrimarySubtle
        }
    }
}

private struct ReminderChip: View {
    let date: Date

    private var isDue: Bool { date <= Date() }

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: isDue ? "bell.badge.fill" : "bell")
                .font(.system(size: 10, weight: .semibold))
            Text(date, style: .relative)
                .font(DSFont.caption)
                .lineLimit(1)
        }
        .foregroundStyle(isDue ? Color.dsStatusWarning : Color.dsTextTertiary)
    }
}

// MARK: - Preview

private struct DocumentCardPreview: View {
    var body: some View {
        let now = Date()
        List {
            DocumentCard(entry: LibraryEntry(
                document: DocumentRef(
                    name: "Quarterly Report.docx",
                    url: URL(fileURLWithPath: "/tmp/Quarterly Report.docx"),
                    modifiedAt: now.addingTimeInterval(-3600),
                    kind: .docx
                ),
                metadata: DocumentMetadata(id: "1", status: .draft, lastOpenedAt: now, lastModifiedAt: now),
                downloadState: .local
            ))
            DocumentCard(entry: LibraryEntry(
                document: DocumentRef(
                    name: "Contract.pdf",
                    url: URL(fileURLWithPath: "/tmp/Contract.pdf"),
                    modifiedAt: now.addingTimeInterval(-86400),
                    kind: .pdf
                ),
                metadata: DocumentMetadata(
                    id: "2",
                    status: .signed,
                    lastOpenedAt: now,
                    lastModifiedAt: now,
                    remindAt: now.addingTimeInterval(-1800)
                ),
                downloadState: .local
            ))
            DocumentCard(entry: LibraryEntry(
                document: DocumentRef(
                    name: "Budget.xlsx",
                    url: URL(fileURLWithPath: "/tmp/Budget.xlsx"),
                    modifiedAt: now.addingTimeInterval(-172800),
                    kind: .xlsx
                ),
                metadata: DocumentMetadata(id: "3", status: .sent, lastOpenedAt: now, lastModifiedAt: now),
                downloadState: .local
            ))
        }
        .listStyle(.plain)
    }
}

#Preview {
    DocumentCardPreview()
}
