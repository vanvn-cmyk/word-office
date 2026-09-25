import SwiftUI

@main
struct Word_OfficeApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        #if DEBUG
        // Allow simulator test runs to bypass first-run onboarding via a launch arg.
        // Usage: simctl launch UDID BUNDLE -- --skip-onboarding
        if CommandLine.arguments.contains("--skip-onboarding") {
            UserDefaults.standard.set(true, forKey: "root.hasCompletedOnboarding")
            UserDefaults.standard.set(true, forKey: SampleFileSeeder.didSeedDefaultsKey)
        }
        #endif
    }

    @State private var appState = AppState()
    @State private var themeStore = ThemeStore()
    @State private var sessionStore = SessionStore()
    @State private var libraryStore = LibraryStore()
    @State private var container = DependencyContainer()
    /// App-scope toast presenter — injected via `.environment(_:)` so any
    /// view can trigger a bottom toast via `@Environment(DSToastPresenter.self)`.
    @State private var toastPresenter = DSToastPresenter()
    @State private var usageTracker = AppUsageTracker()
    @State private var feedbackTrigger = FeedbackTriggerService()
    @State private var adService = AppOpenAdService()

    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView(container: container)
                    .environment(appState)
                    .environment(themeStore)
                    .environment(sessionStore)
                    .environment(libraryStore)
                    .environment(toastPresenter)
                    .environment(usageTracker)
                    .environment(feedbackTrigger)
                    .preferredColorScheme(themeStore.preferredColorScheme)
                    .tint(Color.dsBrandPrimary)
                    .onChange(of: scenePhase) { _, newPhase in
                        handleScenePhaseChange(newPhase)
                    }

                if isShowingSplash {
                    SplashView()
                        .transition(.opacity)
                }
            }
            // Scene-root toast host. Second (in-sheet) toast hosts are
            // applied inside `EditorSheet` (the shared editor wrapper)
            // and `LibraryAddButton`'s FAB scan sheet — SwiftUI sheets
            // present above scene-root overlays, so a toast fired while
            // any sheet is up is invisible unless the sheet itself
            // hosts one too.
            .toastHost(toastPresenter)
            .task {
                // Fixed minimum display time (not tied to any real loading state —
                // `DependencyContainer`/`RootView`'s own permission check are fast
                // enough that gating on them would make the splash flash by
                // inconsistently). Purely a brand beat, per the "basic splash" ask.
                adService.start()
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeOut(duration: 0.3)) { isShowingSplash = false }
                showAdIfPossible()
            }
        }
    }

    /// Handles app lifecycle transitions:
    /// - `.background`: flush autosave + reschedule re-engagement notifications.
    /// - `.active`:     cancel re-engagement (user is back — no point nagging).
    @MainActor
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            usageTracker.didEnterBackground()
            // Flush pending autosave
            if let ref = sessionStore.currentDocument {
                let autosave = container.autosaveScheduler
                let id = ref.id
                Task { await autosave.flush(id: id) }
            }
            // Reschedule re-engagement with the current draft count.
            // draftCount = 0 → cancelReEngagement() inside scheduleReEngagement.
            let draftCount = libraryStore.draftCount
            Task { await LocalNotificationScheduler.shared.scheduleReEngagement(draftCount: draftCount) }

        case .active:
            usageTracker.didBecomeActive()
            // User opened the app — remove any pending re-engagement notifications.
            LocalNotificationScheduler.shared.cancelReEngagement()
            // Show App Open Ad on resume (skip if splash is still visible — ad
            // fires after splash via the .task block on first launch).
            if !isShowingSplash { showAdIfPossible() }

        default:
            break
        }
    }

    /// Finds the top-most `rootViewController` and asks `adService` to show.
    /// No-op if the editor is open, premium, within cooldown, or ad not loaded.
    private func showAdIfPossible() {
        guard sessionStore.currentDocument == nil else { return }
        guard let root = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController
        else { return }
        adService.showIfReady(from: root)
    }
}
