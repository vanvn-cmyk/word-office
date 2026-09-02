import CoreGraphics
import Foundation
import Vision

/// Recognizes text via `VNRecognizeTextRequest` — native, on-device, no SDK dependency.
/// See Phase0-Implementation-Logic-v2.md §6.3 (language selection) + §6.4 (confidence
/// surfaced per block, never silently assumed correct).
///
/// Per-page concurrency limiting (§6.2 — cap ~2-3 pages at once) belongs to the
/// caller's scan queue, not here — this type recognizes one page per call.
final class VisionTextRecognizer: TextRecognizing {
    func recognize(in image: CGImage, pageIndex: Int, languages: [String]) async throws -> OCRResult {
        // `.accurate` recognition is CPU-heavy (hundreds of ms to seconds per page).
        // `VNImageRequestHandler.perform` is synchronous — must run off the
        // caller's actor, same reasoning as `PDFKitMerger`/`PDFKitSplitter`.
        try await Task.detached(priority: .userInitiated) {
            try await withCheckedThrowingContinuation { continuation in
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: TextRecognitionError.requestFailed(error.localizedDescription))
                        return
                    }
                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let blocks = observations.compactMap { observation -> OCRTextBlock? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return OCRTextBlock(
                            text: candidate.string,
                            boundingBox: observation.boundingBox,
                            confidence: candidate.confidence
                        )
                    }
                    continuation.resume(returning: OCRResult(pageIndex: pageIndex, blocks: blocks))
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = languages

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: TextRecognitionError.requestFailed(error.localizedDescription))
                }
            }
        }.value
    }
}
