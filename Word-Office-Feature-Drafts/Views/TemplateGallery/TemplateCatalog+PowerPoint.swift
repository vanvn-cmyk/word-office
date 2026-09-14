import SwiftUI

/// PowerPoint (`.pptx`) mock templates. See `DocumentTemplate.swift` for
/// why this is its own file.
extension TemplateCatalog {
    static let powerPointTemplates: [DocumentTemplate] = [
        DocumentTemplate(
            id: "pptx.pitchDeck",
            kind: .pptx,
            title: "Pitch Deck",
            accentColor: .dsDocumentPresentation,
            thumbnail: .lines(hasAccentTitle: true)
        ),
        DocumentTemplate(
            id: "pptx.projectTimeline",
            kind: .pptx,
            title: "Project Timeline",
            accentColor: .dsBrandPrimary,
            thumbnail: .linesWithHighlight
        ),
        DocumentTemplate(
            id: "pptx.teamUpdate",
            kind: .pptx,
            title: "Team Update",
            accentColor: .dsPremiumGoldStart,
            thumbnail: .lines(hasAccentTitle: false)
        ),
        DocumentTemplate(
            id: "pptx.quarterlyReport",
            kind: .pptx,
            title: "Quarterly Report",
            accentColor: .dsStatusSuccess,
            thumbnail: .lines(hasAccentTitle: true)
        ),
        DocumentTemplate(
            id: "pptx.marketingPlan",
            kind: .pptx,
            title: "Marketing Plan",
            accentColor: .dsStatusError,
            thumbnail: .linesWithHighlight
        ),
        DocumentTemplate(
            id: "pptx.trainingDeck",
            kind: .pptx,
            title: "Training Deck",
            accentColor: .dsDocumentSpreadsheet,
            thumbnail: .lines(hasAccentTitle: true)
        ),
        DocumentTemplate(
            id: "pptx.meetingAgenda",
            kind: .pptx,
            title: "Meeting Agenda",
            accentColor: .dsStatusWarning,
            thumbnail: .lines(hasAccentTitle: false)
        ),
    ]
}
