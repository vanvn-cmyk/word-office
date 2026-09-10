// Sprint 0.3 — merge/split orchestration. Compress excluded (moved to Phase 1 — see
// Phase0-Implementation-Logic-v2.md §7 changelog note, 2026-08-31).
// §7.4 (2026-09-01) — extended with the 4 Convert directions (Office→PDF, PDF→Word,
// PDF→Image, Image→PDF). Deliberately kept on this same view model rather than one
// per direction — all 4 share the reentrancy-guard/progress pattern already here.

import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class PDFToolsViewModel {
    private(set) var isProcessing = false
    private(set) var lastMergedURL: URL?
    private(set) var lastSplitURLs: [URL] = []
    private(set) var lastConvertedURL: URL?
    private(set) var lastImageExportURLs: [URL] = []
    var errorMessage: String?

    private let merger: any PDFMerging
    private let splitter: any PDFSplitting
    private let printer: any DocumentPrinting
    private let exporter: any DocumentExporting
    private let textExtractor: any PDFTextExtracting
    private let imageExporter: any PDFImageExporting
    private let pdfFromImages: any ImagePDFExporting
    private let documentsURL: URL
    private let recognitionLanguages: [String]

    init(
        merger: any PDFMerging,
        splitter: any PDFSplitting,
        printer: any DocumentPrinting,
        exporter: any DocumentExporting,
        textExtractor: any PDFTextExtracting,
        imageExporter: any PDFImageExporting,
        pdfFromImages: any ImagePDFExporting,
        documentsURL: URL,
        recognitionLanguages: [String]
    ) {
        self.merger = merger
        self.splitter = splitter
        self.printer = printer
        self.exporter = exporter
        self.textExtractor = textExtractor
        self.imageExporter = imageExporter
        self.pdfFromImages = pdfFromImages
        self.documentsURL = documentsURL
        self.recognitionLanguages = recognitionLanguages
    }

    /// Merges `urls` in the given order into a new file in the app's Documents
    /// directory — same location the library scanner already watches, so the
    /// result shows up in the document list without a separate import step.
    ///
    /// Guards against re-entrancy: the destination name is picked synchronously
    /// but the actual write is `await`-ed, so a second call before the first
    /// finishes would otherwise compute the same "Merged.pdf" name and race it.
    func merge(_ urls: [URL]) async {
        guard !isProcessing else { return }
        isProcessing = true
        lastMergedURL = nil
        defer { isProcessing = false }
        do {
            let destination = FileManager.default.nonConflictingURL(for: "Merged.pdf", in: documentsURL)
            try await merger.merge(urls, into: destination)
            lastMergedURL = destination
            errorMessage = nil
            NotificationCenter.default.post(name: .documentsDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Splits `url` by `ranges` (0-based, inclusive) into the Documents directory.
    /// `PDFKitSplitter` itself picks non-conflicting names per output file.
    func split(_ url: URL, ranges: [ClosedRange<Int>]) async {
        guard !isProcessing else { return }
        isProcessing = true
        lastSplitURLs = []
        defer { isProcessing = false }
        do {
            lastSplitURLs = try await splitter.split(url, ranges: ranges, into: documentsURL)
            errorMessage = nil
            NotificationCenter.default.post(name: .documentsDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Presents the AirPrint sheet. Failure surfaces via `errorMessage` like the
    /// other actions here — cancellation (`DocumentPrinting`'s success case) is not
    /// treated as an error.
    ///
    /// Same `isProcessing` reentrancy guard as every other method here — Print
    /// shares this view model instance with Merge/Split/Convert (`ToolsTabView`
    /// wires all 4 destinations to one `pdfToolsVM`), so without this guard a
    /// concurrent Merge/Split/Convert `await` in flight could race this method's
    /// `errorMessage` write against that other operation's own.
    func print(_ url: URL, jobName: String) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await printer.print(url, jobName: jobName)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Convert (§7.4)

    /// Office (Word/Excel/PowerPoint) → PDF. Reuses the SDK's `exportPDF` — no
    /// separate engine, same reasoning as §1's in-editor "Export as PDF".
    func convertToPDF(_ url: URL) async {
        guard !isProcessing else { return }
        isProcessing = true
        lastConvertedURL = nil
        defer { isProcessing = false }
        do {
            let stem = url.deletingPathExtension().lastPathComponent
            let destination = FileManager.default.nonConflictingURL(for: "\(stem).pdf", in: documentsURL)
            try await exporter.exportPDF(from: url, to: destination)
            lastConvertedURL = destination
            errorMessage = nil
            NotificationCenter.default.post(name: .documentsDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `true` when `url` has no embedded text layer and converting it would need
    /// OCR (slower) — the caller shows this before the user commits to converting.
    /// `nil` means the check itself failed (e.g. corrupted PDF) — distinct from
    /// `false` ("has text, no OCR needed") so the caller doesn't show a confident
    /// but wrong notice; the real failure still surfaces properly from
    /// `convertPDFToWord` itself a moment later either way.
    func checkNeedsOCR(_ url: URL) async -> Bool? {
        try? await textExtractor.needsOCR(url)
    }

    /// PDF → Word. Text-only — no formatting/images/tables (§7.4). Auto-detects
    /// scanned PDFs (no text layer) and falls back to OCR via `PDFTextExtracting`,
    /// same engine `Scan & OCR` uses.
    func convertPDFToWord(_ url: URL) async {
        guard !isProcessing else { return }
        isProcessing = true
        lastConvertedURL = nil
        defer { isProcessing = false }
        do {
            let text = try await textExtractor.extractText(from: url, languages: recognitionLanguages)
            let stem = url.deletingPathExtension().lastPathComponent
            let destination = FileManager.default.nonConflictingURL(for: "\(stem).docx", in: documentsURL)
            try await Task.detached(priority: .utility) {
                try DOCXCodec.write(AttributedString(text), to: destination)
            }.value
            lastConvertedURL = destination
            errorMessage = nil
            NotificationCenter.default.post(name: .documentsDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// PDF → Image. `pageRange` is 0-based inclusive; `nil` exports every page.
    func convertPDFToImages(_ url: URL, pageRange: ClosedRange<Int>?) async {
        guard !isProcessing else { return }
        isProcessing = true
        lastImageExportURLs = []
        defer { isProcessing = false }
        do {
            lastImageExportURLs = try await imageExporter.exportImages(from: url, pageRange: pageRange, into: documentsURL)
            errorMessage = nil
            NotificationCenter.default.post(name: .documentsDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Image → PDF. `images` order = page order; each page sized to its own image.
    func convertImagesToPDF(_ images: [UIImage]) async {
        guard !isProcessing else { return }
        isProcessing = true
        lastConvertedURL = nil
        defer { isProcessing = false }
        do {
            let destination = FileManager.default.nonConflictingURL(for: "Images.pdf", in: documentsURL)
            try await pdfFromImages.exportPDF(from: images, to: destination)
            lastConvertedURL = destination
            errorMessage = nil
            NotificationCenter.default.post(name: .documentsDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
