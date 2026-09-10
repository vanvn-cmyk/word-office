import Foundation

/// One page in the first-run onboarding flow (4 total). Purely presentational
/// data — the ViewModel maps this into the pager and CTA layout.
///
/// The final page (`.chooseFolder`) is the folder-permission gate: its primary
/// CTA delegates back to `FolderPermissionViewModel.requestPermission()`, and
/// its secondary "Maybe Later" mirrors the existing "Skip for now" path on
/// `FolderPermissionOnboarding`.
struct OnboardingPage: Identifiable, Hashable {
    let id: Kind
    let imageName: String
    let title: String
    let subtitle: String
    let primaryCTA: String
    let secondaryCTA: String?
    let showsPrivacyChip: Bool
    let usesGradientCTA: Bool

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
            title: "Edit Office files anywhere",
            subtitle: "Open and edit Word, Excel, and PowerPoint files while preserving every table, font, and layout.",
            primaryCTA: "Get Started",
            secondaryCTA: nil,
            showsPrivacyChip: false,
            usesGradientCTA: false
        ),
        OnboardingPage(
            id: .tools,
            imageName: "OnboardingTools",
            title: "Every tool, one tap away",
            subtitle: "Convert to PDF, sign documents, and compress files—all without switching apps.",
            primaryCTA: "Continue",
            secondaryCTA: nil,
            showsPrivacyChip: false,
            usesGradientCTA: true
        ),
        OnboardingPage(
            id: .trackDocuments,
            imageName: "OnboardingTrackDocuments",
            title: "Stay on top of every document",
            subtitle: "Tag files as Draft, Reviewed, or Signed so you always know what needs attention.",
            primaryCTA: "Continue",
            secondaryCTA: nil,
            showsPrivacyChip: false,
            usesGradientCTA: true
        ),
        OnboardingPage(
            id: .chooseFolder,
            imageName: "OnboardingChooseFolder",
            title: "Choose a folder.\nYour files stay yours.",
            subtitle: "Grant access once to find and organize files directly on your device—nothing gets uploaded.",
            primaryCTA: "Choose Folder",
            secondaryCTA: "Maybe Later",
            showsPrivacyChip: true,
            usesGradientCTA: true
        ),
    ]
}
