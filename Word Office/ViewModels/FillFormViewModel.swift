// Session 12 (2026-09-04) — Fill Form free-text overlay orchestration.
// Two states: pickPDF and fill. In fill state the user taps to add
// text annotations, edits inline via a sheet, and finally saves.

import CoreGraphics
import Foundation
import Observation
import PDFKit

@Observable
@MainActor
final class FillFormViewModel {
    enum Stage: Sendable {
        case pickPDF
        case fill
    }

    var stage: Stage = .pickPDF
    private(set) var sourceURL: URL?
    private(set) var pageCount: Int = 1
    /// Preloaded `PDFDocument` — see `SignatureViewModel.pdfDocument`
    /// for the same F8 rationale (off-main parse before stage flip).
    private(set) var pdfDocument: PDFDocument?

    /// Committed text annotations across all pages. New taps append here
    /// after the user commits via the edit sheet.
    private(set) var annotations: [TextAnnotation] = []

    private(set) var isProcessing = false
    var errorMessage: String?

    private let filler: any FormFilling
    private let previewCommitter: any PreviewCommitting
    private let documentsURL: URL

    init(
        filler: any FormFilling,
        previewCommitter: any PreviewCommitting,
        documentsURL: URL
    ) {
        self.filler = filler
        self.previewCommitter = previewCommitter
        self.documentsURL = documentsURL
    }

    func selectPDF(_ url: URL) async {
        sourceURL = url
        annotations = []
        pdfDocument = nil
        // Load PDFDocument off-main so the `.fill` stage's `PDFView`
        // representable installs an already-parsed doc synchronously
        // (F8) and the page indicator has the real count on first
        // render (F14).
        //
        // Session 19 code-review #4 — security-scope claim REQUIRED
        // on external picker URLs; the `.fileImporter` transient
        // grant doesn't survive the `Task { await selectPDF }` hop in
        // `FillFormView.handleFilePicked`. Same fix + same rationale
        // as the mirror block in `SignatureViewModel.selectPDF`.
        let doc = await Task.detached(priority: .utility) {
            let didStartScope = url.startAccessingSecurityScopedResource()
            defer { if didStartScope { url.stopAccessingSecurityScopedResource() } }
            return PDFDocument(url: url)
        }.value
        pdfDocument = doc
        pageCount = max(doc?.pageCount ?? 1, 1)
        stage = .fill
    }

    func addAnnotation(_ annotation: TextAnnotation) {
        annotations.append(annotation)
    }

    func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
    }

    /// Updates a placed annotation's page-space rect — fired by the
    /// text overlay's drag gesture on release. `pageRect` is already
    /// in PDF page coordinates (converted by the overlay via
    /// `PDFView.convert(_:to:)`).
    func moveAnnotation(id: UUID, to pageRect: CGRect) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].pageRect = pageRect
    }

    func undoLast() {
        _ = annotations.popLast()
    }

    var canSave: Bool { !annotations.isEmpty && !isProcessing }

    /// Mirror of `SignatureViewModel.canReplaceSourceInPlace` — see
    /// that doc-comment for why external sources are gated out of the
    /// destructive "Replace original" path.
    var canReplaceSourceInPlace: Bool {
        guard let source = sourceURL else { return false }
        return source.isInside(documentsURL)
    }

    /// Writes the filled PDF to a staging location (temp directory) so
    /// the user can preview + confirm before it lands in Documents/
    /// (and shows in Library). Returns the staged URL, or nil on
    /// failure — caller reads `errorMessage`. Two-phase pattern
    /// (Session 12 UX): stage → preview → commit or discard.
    func stagePreview() async -> URL? {
        guard canSave, let sourceURL else { return nil }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let staged = try await filler.fill(annotations, on: sourceURL, into: tempDir)
            errorMessage = nil
            return staged
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Commits a previously staged preview into its final location per
    /// the user's choice from `PreviewConfirmSheet`. Mirror of
    /// `SignatureViewModel.commitPreview(_:mode:)` — both delegate to
    /// the same `PreviewCommitting` service so security-scope + file
    /// coordination + off-main dispatch + scope-check logic can't
    /// drift between the two flows. See that method's doc-comment and
    /// `PreviewCommitting.swift` for the full contract.
    func commitPreview(_ stagedURL: URL, mode: PreviewSaveMode) async -> URL? {
        guard let source = sourceURL else {
            discardPreview(stagedURL)
            errorMessage = "Cannot commit: source file is no longer available."
            return nil
        }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let result = try await previewCommitter.commit(
                stagedURL: stagedURL,
                sourceURL: source,
                mode: mode,
                documentsURL: documentsURL
            )
            if result.isInDocumentsFolder {
                NotificationCenter.default.post(name: .documentsDidChange, object: nil)
            }
            errorMessage = nil
            return result.finalURL
        } catch {
            discardPreview(stagedURL)
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Deletes a staged preview file — called when the user cancels
    /// out of the preview sheet. Best-effort: a stray temp file has no
    /// user-visible consequence, so a failed delete is swallowed.
    func discardPreview(_ stagedURL: URL) {
        try? FileManager.default.removeItem(at: stagedURL)
    }

    func reset() {
        stage = .pickPDF
        sourceURL = nil
        pageCount = 1
        pdfDocument = nil
        annotations = []
        errorMessage = nil
    }
}
