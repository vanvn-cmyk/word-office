import Foundation
import Observation

/// Owns the first-run onboarding pager state (4 pages). Deliberately narrow —
/// the S4 "Choose Folder" action is not owned here; the container view wires it
/// to the existing `FolderPermissionViewModel` (SOLID: this VM has no reason to
/// change if permission internals change).
///
/// Completion is signaled by invoking the `onFinish` closure passed on init —
/// `RootView` persists the `hasCompletedOnboarding` flag and unmounts the flow.
@Observable
@MainActor
final class OnboardingViewModel {
    let pages: [OnboardingPage]
    private(set) var currentIndex: Int = 0

    private let onFinish: () -> Void

    init(pages: [OnboardingPage] = OnboardingPage.all, onFinish: @escaping () -> Void) {
        self.pages = pages
        self.onFinish = onFinish
    }

    var currentPage: OnboardingPage { pages[currentIndex] }
    var isLastPage: Bool { currentIndex == pages.count - 1 }
    var isFirstPage: Bool { currentIndex == 0 }

    /// Advance to the next page, or finish if we're already on the last.
    /// Non-last pages' primary CTA calls this; S4 uses `finish()` directly
    /// after the folder-permission grant returns.
    func advance() {
        guard currentIndex < pages.count - 1 else {
            finish()
            return
        }
        currentIndex += 1
    }

    /// Jump to a specific page — swipe gesture on the pager binds through this.
    func jump(to index: Int) {
        guard pages.indices.contains(index) else { return }
        currentIndex = index
    }

    /// Mark onboarding complete. Called on S4 grant, S4 "Maybe Later", or a
    /// direct `advance()` past the last page.
    func finish() {
        onFinish()
    }
}
