import FirebaseRemoteConfig
import Foundation

/// Singleton that fetches and activates Remote Config on launch, then
/// exposes typed accessors for every flag used in the app.
///
/// Usage:
///   let isPremiumEnabled = RemoteConfigService.shared.isPremiumEnabled
///
/// Add new keys to `RemoteConfigKey` and a matching accessor below.
@MainActor
final class RemoteConfigService {

    static let shared = RemoteConfigService()

    private let config: RemoteConfig

    // MARK: - Init

    private init() {
        config = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        #if DEBUG
        settings.minimumFetchInterval = 0   // always fresh in dev
        #else
        settings.minimumFetchInterval = 3600  // 1 h in prod
        #endif
        config.configSettings = settings
        config.setDefaults(RemoteConfigKey.defaults)
    }

    // MARK: - Fetch

    /// Call once at app launch (after `FirebaseApp.configure()`).
    /// Fetches & activates in the background; subsequent reads use the
    /// activated values until the next fetch.
    func fetchAndActivate() {
        config.fetchAndActivate { [weak self] status, error in
            if let error { print("[RemoteConfig] fetch error: \(error)") }
        }
    }

    // MARK: - Typed accessors

    var isPremiumEnabled: Bool {
        config[RemoteConfigKey.isPremiumEnabled].boolValue
    }

    var paywallTitle: String {
        config[RemoteConfigKey.paywallTitle].stringValue ?? RemoteConfigKey.Defaults.paywallTitle
    }

    var trialDurationDays: Int {
        Int(config[RemoteConfigKey.trialDurationDays].numberValue)
    }

    var maxFreeImports: Int {
        Int(config[RemoteConfigKey.maxFreeImports].numberValue)
    }

    /// Minutes of foreground usage before the in-app feedback survey is triggered.
    var surveyThresholdMinutes: Int {
        Int(config[RemoteConfigKey.surveyThresholdMinutes].numberValue)
    }
}

// MARK: - Key catalogue

enum RemoteConfigKey {
    static let isPremiumEnabled       = "is_premium_enabled"
    static let paywallTitle           = "paywall_title"
    static let trialDurationDays      = "trial_duration_days"
    static let maxFreeImports         = "max_free_imports"
    static let surveyThresholdMinutes = "number_show_survey"

    enum Defaults {
        static let paywallTitle = "Unlock Word Office Pro"
    }

    static var defaults: [String: NSObject] {
        [
            isPremiumEnabled:       true  as NSNumber,
            paywallTitle:           Defaults.paywallTitle as NSString,
            trialDurationDays:      7 as NSNumber,
            maxFreeImports:         10 as NSNumber,
            surveyThresholdMinutes: 2 as NSNumber,
        ]
    }
}
