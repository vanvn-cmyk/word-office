import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class ThemeStore {
    var appearance: AppTheme = .light
    var defaultFontSize: CGFloat = 17
    var accentColor: Color = .dsBrandPrimary

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }
}
