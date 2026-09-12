import Foundation

/// One page in the first-run onboarding flow (4 total). Purely presentational
/// data — the ViewModel maps this into the pager and CTA layout.
///
/// The final page (`.chooseFolder`) is the folder-permission gate: its primary
/// CTA delegates back to `FolderPermissionViewModel.requestPermission()`.
struct OnboardingPage: Identifiable, Hashable {
    let id: Kind
    let imageName: String
    let title: String
    let subtitle: String
    let primaryCTA: String
    let secondaryCTA: String?
    let showsPrivacyChip: Bool

    enum Kind: Hashable {
        case editOffice
        case tools
        case trackDocuments
        case chooseFolder
    }

    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: .editOffice,
            imageName: "OnboardingEditOffice",
            title: "Edit Word, Excel & PowerPoint on the go",
            subtitle: "Open the file your colleague just sent, make your changes on iPhone, and send it right back — tables and formatting stay perfectly intact",
            primaryCTA: "Get Started",
            secondaryCTA: nil,
            showsPrivacyChip: false
        ),
        // Compress dropped from the subtitle — cut from MVP scope
        // (Phase0-Implementation-Logic-v2.md); the hero image still shows
        // its zip icon, a known follow-up pending a re-exported asset.
        OnboardingPage(
            id: .tools,
            imageName: "OnboardingTools",
            title: "Every document task, one tap away",
            subtitle: "Split a report into pages, combine files for a client, export as PDF, or add your signature — all without leaving the app",
            primaryCTA: "Continue",
            secondaryCTA: nil,
            showsPrivacyChip: false
        ),
        OnboardingPage(
            id: .trackDocuments,
            imageName: "OnboardingTrackDocuments",
            title: "From first draft to final signature",
            subtitle: "Mark documents as Draft, Reviewed, or Signed so you always know what's done and what still needs attention",
            primaryCTA: "Continue",
            secondaryCTA: nil,
            showsPrivacyChip: false
        ),
        OnboardingPage(
            id: .chooseFolder,
            imageName: "OnboardingChooseFolder",
            title: "Choose a folder\nYour files stay yours",
            subtitle: "Grant access once to find and organize files directly on your device — nothing gets uploaded",
            primaryCTA: "Choose Folder",
            secondaryCTA: "Maybe Later",
            showsPrivacyChip: true
        ),
    ]
}
