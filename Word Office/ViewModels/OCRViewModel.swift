// Sprint 0.3 — scan recognition orchestration. Builds up per-page OCRResult.
// §6 (2026-09-01) — output redefined: editable .docx is the primary export
// (`exportEditableWord`, reuses `DOCXCodec.write`), searchable PDF is now a
// secondary/optional export (`exportSearchablePDF`, via `SearchablePDFRendering`)
// rather than the sole output. ScanFlowView drives 3 input sources (camera,
// Photos, existing PDF — §6.1) and hands this view model the resulting page images;
// all 3 converge on the same `recognize(_:)` below, no per-source branching here.

import CoreGraphics
import Foundation
import Observation

@Observable
@MainActor
final class OCRViewModel {
    /// Priority-ordered BCP-47 tags, e.g. ["vi-VN", "en-US"] — never hardcode
    /// English alone (§6.3). Caller (DI factory) seeds the default; a language
    /// picker in ScanFlowView can override before `recognize` runs.
    var recognitionLanguages: [String]

    private(set) var isProcessing = false
    private(set) var results: [OCRResult] = []
    private(set) var completedPageCount = 0
    var errorMessage: String?

    /// The page images `recognize(_:)` was last called with — kept so the export
    /// step can build a searchable PDF (original image + invisible text overlay)
    /// without the caller having to hand them over a second time.
    private(set) var pages: [CGImage] = []

    /// Vision's `.accurate` recognition is CPU-heavy — cap concurrent pages
    /// rather than firing one task per page at once (§6.2).
    private let maxConcurrentPages = 3

    private let recognizer: any TextRecognizing
    private let searchablePDFRenderer: any SearchablePDFRendering

    init(
        recognizer: any TextRecognizing,
        searchablePDFRenderer: any SearchablePDFRendering,
        recognitionLanguages: [String] = ["vi-VN", "en-US"]
    ) {
        self.recognizer = recognizer
        self.searchablePDFRenderer = searchablePDFRenderer
        self.recognitionLanguages = recognitionLanguages
    }

    /// Blocks below confidence threshold across every recognized page so far —
    /// surfaced in UI, never silently trusted as correct (§6.4).
    var lowConfidenceBlockCount: Int {
        results.reduce(0) { $0 + $1.lowConfidenceBlocks.count }
    }

    var totalPageCount: Int = 0

    /// Recognizes every page in `pages`, at most `maxConcurrentPages` at once.
    /// One page failing does not abort the rest (same "don't fail the whole
    /// batch" contract as `DocumentImporter.importBatch`, §4.3) — failures are
    /// collected into `errorMessage` as a summary, not thrown.
    func recognize(_ pages: [CGImage]) async {
        guard !isProcessing else { return }
        isProcessing = true
        results = []
        completedPageCount = 0
        totalPageCount = pages.count
        self.pages = pages
        var failedPageIndices: [Int] = []
        defer { isProcessing = false }

        // Captured once, by value, before entering the task group — `startTask`
        // hands this Sendable array into `@Sendable` child tasks, avoiding a
        // cross-actor read of `recognitionLanguages` from inside them.
        let languages = recognitionLanguages

        await withTaskGroup(of: (pageIndex: Int, outcome: Result<OCRResult, Error>).self) { group in
            var nextIndex = 0

            func startTask(for index: Int) {
                let image = pages[index]
                group.addTask { [recognizer] in
                    do {
                        let result = try await recognizer.recognize(in: image, pageIndex: index, languages: languages)
                        return (index, .success(result))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }

            let initialBatch = min(maxConcurrentPages, pages.count)
            for index in 0..<initialBatch {
                startTask(for: index)
            }
            nextIndex = initialBatch

            while let (pageIndex, outcome) = await group.next() {
                switch outcome {
                case .success(let result):
                    results.append(result)
                case .failure:
                    failedPageIndices.append(pageIndex)
                }
                completedPageCount += 1

                if nextIndex < pages.count {
                    startTask(for: nextIndex)
                    nextIndex += 1
                }
            }
        }

        results.sort { $0.pageIndex < $1.pageIndex }
        errorMessage = failedPageIndices.isEmpty
            ? nil
            : "Couldn't recognize page(s) \(failedPageIndices.map { $0 + 1 }.sorted().map(String.init).joined(separator: ", "))"
    }

    // MARK: - Export (§6.5)

    /// Primary output — plain text only (no layout/images/tables), reuses the
    /// exact same `DOCXCodec.write` the Editor and "PDF → Word" convert both use.
    func exportEditableWord(to destination: URL) async throws {
        let text = results
            .sorted { $0.pageIndex < $1.pageIndex }
            .map(\.fullText)
            .joined(separator: "\n\n")
        try await Task.detached(priority: .utility) {
            try DOCXCodec.write(AttributedString(text), to: destination)
        }.value
    }

    /// Secondary/optional output — keeps the original scanned image, adds an
    /// invisible searchable text layer at the position Vision recognized it.
    func exportSearchablePDF(to destination: URL) async throws {
        try await searchablePDFRenderer.render(pages: pages, results: results, to: destination)
    }
}
