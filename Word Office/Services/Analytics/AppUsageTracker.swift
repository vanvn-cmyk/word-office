import Foundation

/// Tracks total foreground time since app launch (resets on process kill).
/// Call `didEnterBackground()` / `didBecomeActive()` from `Word_OfficeApp`'s
/// `scenePhase` handler to keep the timer accurate across backgrounding.
@Observable
@MainActor
final class AppUsageTracker {

    private var sessionStart: Date = .now
    private var accumulatedSeconds: TimeInterval = 0
    private var isActive: Bool = true

    var elapsedMinutes: Double {
        let inFlight = isActive ? Date.now.timeIntervalSince(sessionStart) : 0
        return (accumulatedSeconds + inFlight) / 60.0
    }

    func didEnterBackground() {
        guard isActive else { return }
        accumulatedSeconds += Date.now.timeIntervalSince(sessionStart)
        isActive = false
    }

    func didBecomeActive() {
        guard !isActive else { return }
        sessionStart = .now
        isActive = true
    }
}
