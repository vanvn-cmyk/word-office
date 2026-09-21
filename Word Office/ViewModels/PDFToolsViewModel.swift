// Sprint 0.3 — merge/split orchestration. Compress excluded (moved to Phase 1 — see
// Phase0-Implementation-Logic-v2.md §7 changelog note, 2026-08-31).
// §7.4 (2026-09-01) — extended with the 4 Convert directions (Office→PDF, PDF→Word,
// PDF→Image, Image→PDF). Deliberately kept on this same view model rather than one
// per direction — all 4 share the reentrancy-guard/progress pattern already here.

import Foundation
import Observation
import PDFKit
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

    /// Guarantees `documentsURL` exists before any write. `createDirectory`
    /// with `withIntermediateDirectories: true` is idempotent — no-op when
    /// the directory is already there, so calling this in every commit path
    /// costs one stat(2) and is safe to repeat.
    private func ensureDocumentsDir() throws {
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
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
            try ensureDocumentsDir()
            let destination = FileManager.default.nonConflictingURL(for: "Merged.pdf", in: documentsURL)
            try await merger.merge(urls, into: destination)
            lastMergedURL = destination
            errorMessage = nil
            NotificationCenter.default.postDocumentsDidChange([destination: .draft])
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
            NotificationCenter.default.postDocumentsDidChange(
                Dictionary(uniqueKeysWithValues: lastSplitURLs.map { ($0, DocumentStatus.draft) })
            )
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
            try ensureDocumentsDir()
            let stem = url.deletingPathExtension().lastPathComponent
            let destination = FileManager.default.nonConflictingURL(for: "\(stem).pdf", in: documentsURL)
            try await exporter.exportPDF(from: url, to: destination)
            lastConvertedURL = destination
            errorMessage = nil
            NotificationCenter.default.postDocumentsDidChange([destination: .done])
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

    /// PDF → Word. For PDFs with a text layer, uses `PDFPage.attributedString` to
    /// preserve bold/italic/heading structure. Falls back to OCR plain text for
    /// scanned PDFs (§7.4).
    func convertPDFToWord(_ url: URL) async {
        guard !isProcessing else { return }
        isProcessing = true
        lastConvertedURL = nil
        defer { isProcessing = false }
        do {
            let stem = url.deletingPathExtension().lastPathComponent
            let destination = FileManager.default.nonConflictingURL(for: "\(stem).docx", in: documentsURL)
            let needsOCR = (try? await textExtractor.needsOCR(url)) ?? false

            if !needsOCR {
                // Text layer present — extract with font attributes for richer DOCX output
                let attributed = try await Task.detached(priority: .utility) { () throws -> NSAttributedString in
                    guard let document = PDFDocument(url: url) else {
                        throw PDFTextExtractingError.unreadableDocument
                    }
                    let combined = NSMutableAttributedString()
                    for i in 0..<document.pageCount {
                        guard let page = document.page(at: i),
                              let pageAttr = page.attributedString else { continue }
                        if combined.length > 0 {
                            combined.append(NSAttributedString(string: "\n\n"))
                        }
                        combined.append(pageAttr)
                    }
                    return combined
                }.value
                try await Task.detached(priority: .utility) {
                    try DOCXCodec.write(attributed, to: destination)
                }.value
            } else {
                // Scanned PDF — OCR gives plain text only
                let text = try await textExtractor.extractText(from: url, languages: recognitionLanguages)
                try await Task.detached(priority: .utility) {
                    try DOCXCodec.write(AttributedString(text), to: destination)
                }.value
            }

            lastConvertedURL = destination
            errorMessage = nil
            // PDF→Word output may need OCR quality review — start as draft.
            NotificationCenter.default.postDocumentsDidChange([destination: .draft])
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
            NotificationCenter.default.postDocumentsDidChange(
                Dictionary(uniqueKeysWithValues: lastImageExportURLs.map { ($0, DocumentStatus.done) })
            )
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
            try ensureDocumentsDir()
            let destination = FileManager.default.nonConflictingURL(for: "Images.pdf", in: documentsURL)
            try await pdfFromImages.exportPDF(from: images, to: destination)
            lastConvertedURL = destination
            errorMessage = nil
            NotificationCenter.default.postDocumentsDidChange([destination: .done])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Staged variant of `convertImagesToPDF` — converts to a temp file so
    /// the caller can preview before committing to the Library. Does NOT
    /// post a `documentsDidChange` notification. Call `commitImagesPDF(_:)`
    /// to move the result into the Library when the user confirms.
    func convertImagesToPDFToTemp(_ images: [UIImage]) async -> URL? {
        guard !isProcessing else { return nil }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let destination = tempDir.appendingPathComponent("Images-preview.pdf")
            try await pdfFromImages.exportPDF(from: images, to: destination)
            errorMessage = nil
            return destination
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Moves a staged temp PDF into the Library and notifies `LibraryStore`.
    /// Returns the final Library URL on success, `nil` on failure.
    @discardableResult
    func commitImagesPDF(_ tempURL: URL) async -> URL? {
        do {
            try ensureDocumentsDir()
            let destination = FileManager.default.nonConflictingURL(for: "Images.pdf", in: documentsURL)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            lastConvertedURL = destination
            errorMessage = nil
            NotificationCenter.default.postDocumentsDidChange([destination: .done])
            return destination
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Staged Convert variants

    /// Office → PDF to a temp file — does NOT save to Library or post a
    /// notification. Call `commitToPDF(_:)` when the user confirms.
    func convertToPDFToTemp(_ url: URL) async -> URL? {
        guard !isProcessing else { return nil }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let stem = url.deletingPathExtension().lastPathComponent
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let destination = tempDir.appendingPathComponent("\(stem).pdf")
            try await exporter.exportPDF(from: url, to: destination)
            errorMessage = nil
            return destination
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Moves staged temp PDF into the Library. Returns the Library URL.
    @discardableResult
    func commitToPDF(_ tempURL: URL) async -> URL? {
        do {
            try ensureDocumentsDir()
            let stem = tempURL.deletingPathExtension().lastPathComponent
            let destination = FileManager.default.nonConflictingURL(for: "\(stem).pdf", in: documentsURL)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            lastConvertedURL = destination
            errorMessage = nil
            NotificationCenter.default.postDocumentsDidChange([destination: .done])
            return destination
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// PDF → Word to a temp file — does NOT save to Library.
    /// Call `commitPDFToWord(_:)` when the user confirms.
    func convertPDFToWordToTemp(_ url: URL) async -> URL? {
        guard !isProcessing else { return nil }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let stem = url.deletingPathExtension().lastPathComponent
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let destination = tempDir.appendingPathComponent("\(stem).docx")
            let needsOCR = (try? await textExtractor.needsOCR(url)) ?? false
            if !needsOCR {
                let attributed = try await Task.detached(priority: .utility) { () throws -> NSAttributedString in
                    guard let document = PDFDocument(url: url) else {
                        throw PDFTextExtractingError.unreadableDocument
                    }
                    let combined = NSMutableAttributedString()
                    for i in 0..<document.pageCount {
                        guard let page = document.page(at: i),
                              let pageAttr = page.attributedString else { continue }
                        if combined.length > 0 {
                            combined.append(NSAttributedString(string: "\n\n"))
                        }
                        combined.append(pageAttr)
                    }
                    return combined
                }.value
                try await Task.detached(priority: .utility) {
                    try DOCXCodec.write(attributed, to: destination)
                }.value
            } else {
                let text = try await textExtractor.extractText(from: url, languages: recognitionLanguages)
                try await Task.detached(priority: .utility) {
                    try DOCXCodec.write(AttributedString(text), to: destination)
                }.value
            }
            errorMessage = nil
            return destination
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Moves staged temp DOCX into the Library. Returns the Library URL.
    @discardableResult
    func commitPDFToWord(_ tempURL: URL) async -> URL? {
        do {
            try ensureDocumentsDir()
            let stem = tempURL.deletingPathExtension().lastPathComponent
            let destination = FileManager.default.nonConflictingURL(for: "\(stem).docx", in: documentsURL)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            lastConvertedURL = destination
            errorMessage = nil
            NotificationCenter.default.postDocumentsDidChange([destination: .draft])
            return destination
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// PDF → Images to a temp directory — does NOT save to Library.
    /// Call `commitPDFToImages(_:)` when the user confirms via Save All.
    func convertPDFToImagesToTemp(_ url: URL, pageRange: ClosedRange<Int>?) async -> [URL] {
        guard !isProcessing else { return [] }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let outputs = try await imageExporter.exportImages(from: url, pageRange: pageRange, into: tempDir)
            errorMessage = nil
            return outputs
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Moves staged temp images into the Library. Returns Library URLs.
    @discardableResult
    func commitPDFToImages(_ tempURLs: [URL]) async -> [URL] {
        var finals: [URL] = []
        try? ensureDocumentsDir()
        for tempURL in tempURLs {
            let dest = FileManager.default.nonConflictingURL(for: tempURL.lastPathComponent, in: documentsURL)
            do {
                try FileManager.default.moveItem(at: tempURL, to: dest)
                finals.append(dest)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if !finals.isEmpty {
            lastImageExportURLs = finals
            NotificationCenter.default.postDocumentsDidChange(
                Dictionary(uniqueKeysWithValues: finals.map { ($0, DocumentStatus.done) })
            )
        }
        return finals
    }

    /// Splits `url` into temp files — does NOT save to the Library or post
    /// a `documentsDidChange` notification. Call `commitSplit(_:)` to finalize.
    func splitToTemp(_ url: URL, ranges: [ClosedRange<Int>]) async -> [URL] {
        guard !isProcessing else { return [] }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let outputs = try await splitter.split(url, ranges: ranges, into: tempDir)
            errorMessage = nil
            return outputs
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Moves staged temp split PDFs into the Library and notifies `LibraryStore`.
    @discardableResult
    func commitSplit(_ tempURLs: [URL]) async -> [URL] {
        var finals: [URL] = []
        try? ensureDocumentsDir()
        for tempURL in tempURLs {
            let dest = FileManager.default.nonConflictingURL(for: tempURL.lastPathComponent, in: documentsURL)
            do {
                try FileManager.default.moveItem(at: tempURL, to: dest)
                finals.append(dest)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if !finals.isEmpty {
            lastSplitURLs = finals
            NotificationCenter.default.postDocumentsDidChange(
                Dictionary(uniqueKeysWithValues: finals.map { ($0, DocumentStatus.draft) })
            )
        }
        return finals
    }

    /// Merges `urls` into a temp file — does NOT save to the Library or post
    /// a `documentsDidChange` notification. Call `commitMerge(_:)` to finalize.
    func mergeToTemp(_ urls: [URL]) async -> URL? {
        guard !isProcessing else { return nil }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let destination = tempDir.appendingPathComponent("Merged-preview.pdf")
            try await merger.merge(urls, into: destination)
            errorMessage = nil
            return destination
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Moves a staged temp merge PDF into the Library and notifies `LibraryStore`.
    @discardableResult
    func commitMerge(_ tempURL: URL) async -> URL? {
        do {
            try ensureDocumentsDir()
            let destination = FileManager.default.nonConflictingURL(for: "Merged.pdf", in: documentsURL)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            lastMergedURL = destination
            errorMessage = nil
            NotificationCenter.default.postDocumentsDidChange([destination: .draft])
            return destination
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
