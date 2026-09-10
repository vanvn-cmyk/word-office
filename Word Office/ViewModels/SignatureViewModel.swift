// Session 12 (2026-09-04, revision 2) — Sign flow orchestration.
// Two stages: pick PDF → fill (tap-position-first, sheet canvas).
//
// Previous 3-stage flow (canvas → placement) was replaced per user
// feedback: tap-position-first matches Adobe Fill & Sign and the app's
// own FillFormView pattern, so users don't relearn the interaction
// model between two very similar tools. Also fixed a Save-button
// clipping bug the old placement stage suffered from.

import CoreGraphics
import Foundation
import Observation
import PDFKit

@Observable
@MainActor
final class SignatureViewModel {
    enum Stage: Sendable {
        case pickPDF
        case fill
    }

    /// Where the drawn signature currently sits — page index + rect in
    /// PDF page coordinate space (bottom-left origin). `nil` when the
    /// signature exists but hasn't been placed yet (i.e. between the
    /// sheet being dismissed and the user re-tapping to place it).
    struct Placement: Sendable, Hashable {
        let pageIndex: Int
        let pageRect: CGRect
    }

    var stage: Stage = .pickPDF
    private(set) var sourceURL: URL?
    private(set) var pageCount: Int = 1
    /// Preloaded `PDFDocument` for `sourceURL` — populated by `selectPDF`
    /// off the main actor so the `.fill` stage's `PDFView`
    /// representable can install it synchronously without blocking the
    /// navigation animation (F8 in code review — large scanned PDFs took
    /// hundreds of ms to parse on the main thread from `makeUIView`).
    private(set) var pdfDocument: PDFDocument?

    /// PNG bytes of the drawn signature. Nil until the user commits from
    /// the draw sheet. Non-nil across taps — subsequent taps only move
    /// the existing signature; the sheet does not re-open unless the
    /// user long-presses to Clear.
    private(set) var signatureImageData: Data?
    /// Latest placement (single-signature model for MVP — one signature
    /// per Save, moved by tapping different spots).
    private(set) var placement: Placement?

    private(set) var isProcessing = false
    var errorMessage: String?

    private let stamper: any SignatureStamping
    private let previewCommitter: any PreviewCommitting
    private let documentsURL: URL

    init(
        stamper: any SignatureStamping,
        previewCommitter: any PreviewCommitting,
        documentsURL: URL
    ) {
        self.stamper = stamper
        self.previewCommitter = previewCommitter
        self.documentsURL = documentsURL
    }

    // MARK: - Stage transitions

    func selectPDF(_ url: URL) async {
        sourceURL = url
        signatureImageData = nil
        placement = nil
        pdfDocument = nil
        // Load the PDFDocument off-main so the `.fill` stage's
        // `PDFView` gets an already-parsed doc synchronously — no
        // main-thread parse from `makeUIView` (F8), no page-count-off-
        // by-one on first render (F14).
        //
        // Session 19 code-review #4 — `startAccessingSecurityScopedResource`
        // wrap is REQUIRED here. `SignFlowView.handleFilePicked`
        // dispatches the picker URL into `Task { await selectPDF(url) }`,
        // and the `.fileImporter` grant does NOT survive that hop.
        // Without the claim, `PDFDocument(url:)` returns nil for any
        // PDF picked from iCloud Drive / third-party Files providers,
        // and the `.fill` stage silently renders the "No PDF loaded"
        // empty state.
        let doc = await Task.detached(priority: .utility) {
            let didStartScope = url.startAccessingSecurityScopedResource()
            defer { if didStartScope { url.stopAccessingSecurityScopedResource() } }
            return PDFDocument(url: url)
        }.value
        pdfDocument = doc
        pageCount = max(doc?.pageCount ?? 1, 1)
        stage = .fill
    }

    /// Called after the sheet commits a drawing. Sets both the image
    /// bytes AND places it at the tap location that opened the sheet.
    func commitSignature(pngData: Data, at placement: Placement) {
        signatureImageData = pngData
        self.placement = placement
    }

    /// Called on subsequent taps once a signature already exists —
    /// updates the placement without re-opening the sheet, so the user
    /// can nudge the signature by tapping elsewhere.
    func movePlacement(to placement: Placement) {
        guard signatureImageData != nil else { return }
        self.placement = placement
    }

    /// Wipes the signature bytes and placement — next tap will re-open
    /// the sheet for a fresh signature. Used from the long-press-clear
    /// action on the placed signature overlay.
    func clearSignature() {
        signatureImageData = nil
        placement = nil
    }

    var canSave: Bool {
        signatureImageData != nil && placement != nil && !isProcessing
    }

    /// True when the current `sourceURL` sits inside the library folder
    /// (`documentsURL`) — that is, a PDF the app previously imported or
    /// created, so "Replace original" is at most annoying (user backup +
    /// re-run to recover). False when the PDF was picked directly from
    /// `.fileImporter` outside the sandbox (iCloud Drive, third-party
    /// providers), where an in-place overwrite is instantly synced to
    /// every collaborator with no local recovery — the sheet hides the
    /// destructive option entirely in that case (code-review finding
    /// #13). `sourceURL` nil means no PDF picked yet, so no replace is
    /// possible either.
    var canReplaceSourceInPlace: Bool {
        guard let source = sourceURL else { return false }
        return source.isInside(documentsURL)
    }

    /// Stamps the signature onto the source PDF into a staging location
    /// (temp directory) so the user can preview + confirm before the
    /// final file lands in Documents/. Two-phase (Session 12 UX):
    /// stage → preview sheet → commit or discard.
    func stagePreview() async -> URL? {
        guard canSave,
              let sourceURL,
              let imageData = signatureImageData,
              let placement
        else { return nil }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let signature = Signature(imageData: imageData)
            let tempDir = FileManager.default.temporaryDirectory
            let staged = try await stamper.stamp(
                signature,
                on: sourceURL,
                pageIndex: placement.pageIndex,
                pageRect: placement.pageRect,
                into: tempDir
            )
            errorMessage = nil
            return staged
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Commits the staged signed PDF into its final location per the
    /// user's choice from `PreviewConfirmSheet`. Thin delegation to
    /// `PreviewCommitting` — the shared service owns security-scoped
    /// resource access, `NSFileCoordinator` write coordination,
    /// off-main dispatch, and the "is-final-inside-library-folder"
    /// scope check. See `PreviewCommitting.swift` doc-comment for the
    /// full contract; keeping the logic behind that protocol prevents
    /// this VM and `FillFormViewModel.commitPreview` from drifting
    /// apart the way an earlier day-one duplication propagated the
    /// same trash-bin comment error to both (code-review finding #6).
    ///
    /// Nil on failure — staged temp deleted, message surfaces via
    /// `errorMessage`.
    func commitPreview(_ stagedURL: URL, mode: PreviewSaveMode) async -> URL? {
        // `sourceURL` is always non-nil here — `stagePreview` returns
        // nil unless `canSave`, which requires `sourceURL != nil`.
        // Bail with a clear message on the unreachable-in-current-code
        // path rather than force-unwrapping.
        guard let source = sourceURL else {
            discardPreview(stagedURL)
            errorMessage = "Cannot commit: source file is no longer available."
            return nil
        }

        // isProcessing on the commit path too — earlier version only
        // set it during `stagePreview`, so the `ProcessingOverlay`
        // vanished once staging finished and left the confirmation
        // dialog re-tappable during the actual `replaceItemAt` (code-
        // review finding #8). Cross-volume fallback can take ~1s for
        // a 40MB PDF.
        isProcessing = true
        defer { isProcessing = false }

        do {
            let result = try await previewCommitter.commit(
                stagedURL: stagedURL,
                sourceURL: source,
                mode: mode,
                documentsURL: documentsURL
            )
            // Gate the Library re-scan on where the file actually
            // landed. External replaces (source picked from iCloud
            // Drive via `.fileImporter`) don't touch Documents/, so
            // posting `.documentsDidChange` would trigger a pointless
            // re-scan AND imply "look in Library" for a file that
            // never lands there (code-review finding #5). The caller
            // (View) surfaces a "Replaced in <folder>" toast for the
            // external case instead.
            if result.isInDocumentsFolder {
                NotificationCenter.default.post(name: .documentsDidChange, object: nil)
            }
            errorMessage = nil
            return result.finalURL
        } catch {
            // Failure path — delete the staged temp file so it doesn't
            // linger. Caller skips its discard branch on nil (Code
            // Review #3).
            discardPreview(stagedURL)
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Best-effort delete of a staged preview file — user cancelled out
    /// of the preview sheet. A stray temp file is harmless if this fails.
    func discardPreview(_ stagedURL: URL) {
        try? FileManager.default.removeItem(at: stagedURL)
    }

    func reset() {
        stage = .pickPDF
        sourceURL = nil
        pageCount = 1
        pdfDocument = nil
        signatureImageData = nil
        placement = nil
        errorMessage = nil
    }
}
