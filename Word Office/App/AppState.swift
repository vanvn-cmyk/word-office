import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var launchCount: Int = 0
    var lastVersion: String?
    var isFirstRun: Bool = true
}
