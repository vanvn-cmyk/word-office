import FirebaseAnalytics
import Foundation

/// Thin wrapper around Firebase Analytics.
/// Call `AnalyticsService.log(_:)` anywhere — no import of FirebaseAnalytics
/// needed at call sites, keeping the dependency contained here.
enum AnalyticsService {

    // MARK: - Log event

    static func log(_ event: AppEvent) {
        Analytics.logEvent(event.name, parameters: event.parameters)
    }

    // MARK: - User properties

    static func setUserProperty(_ value: String?, forName name: String) {
        Analytics.setUserProperty(value, forName: name)
    }

    static func setUserId(_ id: String?) {
        Analytics.setUserID(id)
    }
}

// MARK: - Event catalogue

/// All analytics events in one place — adding a new event is just a new
/// `case`. Parameters are typed via associated values so call sites can't
/// pass wrong keys.
enum AppEvent {
    // Onboarding
    case onboardingStarted
    case onboardingCompleted(step: Int)

    // Library
    case fileImported(kind: String)
    case fileOpened(kind: String)
    case fileDeleted(kind: String)

    // Tools
    case toolOpened(name: String)
    case toolCompleted(name: String, success: Bool)

    // Sign / Fill Form
    case signatureAdded
    case formFilled(fieldCount: Int)

    // Paywall
    case paywallShown(source: String)
    case paywallDismissed(source: String)
    case purchaseStarted(productId: String)
    case purchaseCompleted(productId: String)
    case purchaseFailed(productId: String)

    // Editor
    case editorOpened(kind: String)
    case editorClosed(kind: String, durationSeconds: Int)

    // Feedback
    case feedbackSubmitted(rating: Int, useCase: String, frictions: [String], docTypes: [String], missing: String)

    // MARK: - Serialisation

    var name: String {
        switch self {
        case .onboardingStarted:             return "onboarding_started"
        case .onboardingCompleted:           return "onboarding_completed"
        case .fileImported:                  return "file_imported"
        case .fileOpened:                    return "file_opened"
        case .fileDeleted:                   return "file_deleted"
        case .toolOpened:                    return "tool_opened"
        case .toolCompleted:                 return "tool_completed"
        case .signatureAdded:                return "signature_added"
        case .formFilled:                    return "form_filled"
        case .paywallShown:                  return "paywall_shown"
        case .paywallDismissed:              return "paywall_dismissed"
        case .purchaseStarted:               return "purchase_started"
        case .purchaseCompleted:             return "purchase_completed"
        case .purchaseFailed:                return "purchase_failed"
        case .editorOpened:                  return "editor_opened"
        case .editorClosed:                  return "editor_closed"
        case .feedbackSubmitted:             return "feedback_submitted"
        }
    }

    var parameters: [String: Any]? {
        switch self {
        case .onboardingStarted, .signatureAdded:
            return nil
        case .onboardingCompleted(let step):
            return ["step": step]
        case .fileImported(let kind), .fileOpened(let kind), .fileDeleted(let kind):
            return ["kind": kind]
        case .toolOpened(let name), .toolCompleted(let name, _):
            var p: [String: Any] = ["tool": name]
            if case .toolCompleted(_, let success) = self { p["success"] = success ? 1 : 0 }
            return p
        case .formFilled(let count):
            return ["field_count": count]
        case .paywallShown(let src), .paywallDismissed(let src):
            return ["source": src]
        case .purchaseStarted(let id), .purchaseCompleted(let id), .purchaseFailed(let id):
            return ["product_id": id]
        case .editorOpened(let kind):
            return ["kind": kind]
        case .editorClosed(let kind, let dur):
            return ["kind": kind, "duration_seconds": dur]
        case .feedbackSubmitted(let r, let u, let f, let d, let m):
            return [
                "rating": r,
                "use_case": u,
                "frictions": f.joined(separator: ","),
                "doc_types": d.joined(separator: ","),
                "missing": m
            ]
        }
    }
}
