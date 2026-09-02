import CoreGraphics
import Foundation

/// Result of running text recognition on one scanned page.
/// See Phase0-Implementation-Logic-v2.md §6.4 (confidence) + §6.5 (output).
struct OCRResult: Sendable {
    let pageIndex: Int
    let blocks: [OCRTextBlock]

    /// Blocks below threshold — surfaced in UI, never silently trusted as correct (§6.4).
    var lowConfidenceBlocks: [OCRTextBlock] {
        blocks.filter { $0.confidence < OCRTextBlock.confidenceThreshold }
    }

    /// Recognized text joined in the order Vision returned observations.
    var fullText: String {
        blocks.map(\.text).joined(separator: "\n")
    }
}

struct OCRTextBlock: Sendable, Identifiable, Hashable {
    static let confidenceThreshold: Float = 0.5

    let id: UUID
    let text: String
    /// Normalized bounding box (0...1, origin bottom-left) — Vision's native coordinate space.
    let boundingBox: CGRect
    let confidence: Float

    init(id: UUID = UUID(), text: String, boundingBox: CGRect, confidence: Float) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}
