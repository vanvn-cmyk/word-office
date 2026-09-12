import UIKit

/// Centralized runtime orientation gate.
///
/// `AppDelegate.application(_:supportedInterfaceOrientationsFor:)` reads
/// `supported` so every UIViewController in the scene inherits the correct
/// mask without per-screen subclassing.
///
/// Only the Office editor (`EditorSheet`) should call `allowAll()` /
/// `lockToPortrait()` — everything else stays portrait by default.
final class OrientationManager {
    static let shared = OrientationManager()
    private init() {}

    private(set) var supported: UIInterfaceOrientationMask = .portrait

    /// Called when the editor appears — enables landscape.
    func allowAll() {
        supported = .all
    }

    /// Called when the editor disappears — locks back to portrait and
    /// rotates the window if the device is currently in landscape.
    func lockToPortrait() {
        supported = .portrait
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
    }
}
