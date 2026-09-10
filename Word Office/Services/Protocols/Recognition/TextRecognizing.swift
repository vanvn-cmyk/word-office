import CoreGraphics
import Foundation

/// Wraps Vision's `VNRecognizeTextRequest` — 100% on-device, no network call (§6.5),
/// unlike the AI features in Appendix A/B which both require a cloud call.
/// See Phase0-Implementation-Logic-v2.md §6.
protocol TextRecognizing: Sendable {
    /// Recognize text in `image`, tagged with `pageIndex` for multi-page scans.
    /// `languages` in priority order (e.g. `["vi-VN", "en-US"]`) — caller decides
    /// the default (system language) + user override (§6.3), never hardcode `en-US` alone.
    func recognize(in image: CGImage, pageIndex: Int, languages: [String]) async throws -> OCRResult
}

enum TextRecognitionError: Error, Sendable, LocalizedError {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let reason):
            "Text recognition failed: \(reason)"
        }
    }
}
