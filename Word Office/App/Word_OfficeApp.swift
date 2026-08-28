import SwiftUI

@main
struct Word_OfficeApp: App {
    @State private var appState = AppState()
    @State private var themeStore = ThemeStore()
    @State private var sessionStore = SessionStore()
    @State private var libraryStore = LibraryStore()
    @State private var container = DependencyContainer()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
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
