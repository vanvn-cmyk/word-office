import Foundation
import Observation

@Observable
@MainActor
final class FeedbackViewModel {

    // MARK: - State

    var rating: Int = 0
    var selectedUseCases: Set<String> = []
    var selectedFrictions: Set<String> = []
    var selectedDocTypes: Set<String> = []
    var selectedMissing: Set<String> = []

    var canSubmit: Bool { rating > 0 }

    // MARK: - Options

    // Q2 — why they downloaded: reveals core use case & acquisition reason
    static let useCaseOptions: [String] = [
        "Edit docs on the go",
        "Sign & fill PDFs",
        "Convert or merge files",
        "Organize my documents",
        "Replace another app",
        "Someone recommended it",
        "Free / affordable option",
        "Just browsing"
    ]

    // Q3 — last frustration: surfaces what's actively breaking trust (pick up to 2)
    static let frictionOptions: [String] = [
        "File didn't open correctly",
        "Editing felt clunky",
        "Lost my edits / no autosave",
        "Couldn't find a feature",
        "App was too slow",
        "Formatting broke after editing",
        "Couldn't sync with cloud",
        "Feature I need is paywalled",
        "UI was hard to navigate"
    ]

    // Q4 — most-used feature: drives retention prioritization
    static let docTypeOptions: [String] = [
        "Word / DOCX editing",
        "Excel / spreadsheets",
        "PowerPoint / slides",
        "PDF sign & fill",
        "PDF convert & merge",
        "OCR & scan docs",
        "Compress files"
    ]

    // Q5 — advocacy driver: reveals what would unlock word-of-mouth growth
    static let missingOptions: [String] = [
        "Works offline perfectly",
        "Syncs with all my clouds",
        "Better PDF tools",
        "Much faster performance",
        "Better collaboration & sharing",
        "Simpler, cleaner UI",
        "Auto-save & version history",
        "More templates & styles"
    ]

    // MARK: - Actions

    func toggleUseCase(_ option: String) {
        if selectedUseCases.contains(option) {
            selectedUseCases.remove(option)
        } else {
            selectedUseCases.insert(option)
        }
    }

    func toggleFriction(_ option: String) {
        if selectedFrictions.contains(option) { selectedFrictions.remove(option) }
        else { selectedFrictions.insert(option) }
    }

    func toggleDocType(_ option: String) {
        if selectedDocTypes.contains(option) { selectedDocTypes.remove(option) }
        else { selectedDocTypes.insert(option) }
    }

    func toggleMissing(_ option: String) {
        if selectedMissing.contains(option) { selectedMissing.remove(option) }
        else { selectedMissing.insert(option) }
    }

    func submit() {
        AnalyticsService.log(.feedbackSubmitted(
            rating: rating,
            useCase: selectedUseCases.sorted().joined(separator: ","),
            frictions: selectedFrictions.sorted(),
            docTypes: selectedDocTypes.sorted(),
            missing: selectedMissing.sorted().joined(separator: ",")
        ))
    }
}
