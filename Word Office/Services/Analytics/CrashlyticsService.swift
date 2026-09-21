import FirebaseCrashlytics
import Foundation

/// Thin wrapper around Firebase Crashlytics.
/// Call at app launch after `FirebaseApp.configure()`.
enum CrashlyticsService {

    // MARK: - Setup

    /// Enable or disable crash reporting (call with `false` when user
    /// opts out of analytics — required for GDPR/App Store compliance).
    static func setCrashCollectionEnabled(_ enabled: Bool) {
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(enabled)
    }

    // MARK: - User context

    static func setUserId(_ id: String?) {
        Crashlytics.crashlytics().setUserID(id ?? "")
    }

    static func setCustomValue(_ value: Any, forKey key: String) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }

    // MARK: - Non-fatal errors

    /// Log a non-fatal error — shows up in the Crashlytics dashboard
    /// under "Non-fatals" with full stack context.
    static func record(_ error: Error, context: [String: Any]? = nil) {
        var info = context ?? [:]
        info["recorded_at"] = ISO8601DateFormatter().string(from: Date())
        Crashlytics.crashlytics().record(error: error, userInfo: info)
    }

    /// Log a message to the Crashlytics log (visible in crash reports
    /// as breadcrumbs leading up to a crash).
    static func log(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }
}
