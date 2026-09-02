import SwiftUI

@main
struct Word_OfficeApp: App {
    @State private var appState = AppState()
    @State private var themeStore = ThemeStore()
    @State private var sessionStore = SessionStore()
    @State private var libraryStore = LibraryStore()
    @State private var container = DependencyContainer()

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
            .task {
                // Fixed minimum display time (not tied to any real loading state —
                // `DependencyContainer`/`RootView`'s own permission check are fast
                // enough that gating on them would make the splash flash by
                // inconsistently). Purely a brand beat, per the "basic splash" ask.
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeOut(duration: 0.3)) { isShowingSplash = false }
            }
        }
    }

    /// Flush the pending autosave when the app enters background so an OS kill
    /// cannot lose the last 2 s of edits (the debounce window that the scheduler
    /// would otherwise wait out). MVP has a single active editor at a time —
    /// tracked via `SessionStore.currentDocument`. Multi-doc future: iterate all
    /// pending IDs held by the scheduler.
    @MainActor
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .background else { return }
        guard let ref = sessionStore.currentDocument else { return }
        let scheduler = container.autosaveScheduler
        let id = ref.id
        Task { await scheduler.flush(id: id) }
    }
}
