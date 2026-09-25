import UIKit

/// Re-enables the system interactive-pop (swipe-back) gesture on every
/// UINavigationController in the app. SwiftUI's NavigationStack hides
/// the system navigation bar on request (`.toolbar(.hidden, for:
/// .navigationBar)`) but that also nullifies the pop gesture by setting
/// its delegate to the nav-bar controller, which refuses the gesture
/// when the bar is hidden. Clearing the delegate restores the native
/// swipe-back feel without touching any ONLYOFFICE / WKWebView code.
extension UINavigationController {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = nil
    }
}
