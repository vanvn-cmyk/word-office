import SwiftUI

/// Word (`.docx`) mock templates. See `DocumentTemplate.swift` for why this
/// is its own file.
extension TemplateCatalog {
    static let wordTemplates: [DocumentTemplate] = [
        DocumentTemplate(
            id: "docx.businessProposal",
            kind: .docx,
            title: "Business Proposal",
            accentColor: .dsBrandPrimary,
            thumbnail: .lines(hasAccentTitle: true)
        ),
        DocumentTemplate(
            id: "docx.invoice",
            kind: .docx,
            title: "Invoice",
            accentColor: .dsStatusSuccess,
            thumbnail: .lines(hasAccentTitle: false),
            contentShape: .invoiceLines
        ),
        DocumentTemplate(
            id: "docx.medicalReport",
            kind: .docx,
            title: "Medical Report",
            accentColor: .dsStatusError,
            thumbnail: .linesWithHighlight
        ),
        DocumentTemplate(
            id: "docx.medicalRecords",
            kind: .docx,
            title: "Medical Records",
            accentColor: .dsStatusError,
            thumbnail: .lines(hasAccentTitle: true)
        ),
        DocumentTemplate(
            id: "docx.projectDocument",
            kind: .docx,
            title: "Project Document",
            accentColor: .dsDocumentPresentation,
            thumbnail: .lines(hasAccentTitle: true)
        ),
        DocumentTemplate(
            id: "docx.coverLetter",
            kind: .docx,
            title: "Cover Letter",
            accentColor: .dsPremiumGoldStart,
            thumbnail: .lines(hasAccentTitle: false)
        ),
        DocumentTemplate(
            id: "docx.meetingNotes",
            kind: .docx,
            title: "Meeting Notes",
            accentColor: .dsDocumentSpreadsheet,
            thumbnail: .lines(hasAccentTitle: true),
            contentShape: .bulletList
        ),
    ]
}
