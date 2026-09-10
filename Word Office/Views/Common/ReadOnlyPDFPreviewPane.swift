import PDFKit
import SwiftUI
import UIKit

/// PDFKit native preview — read-only, autoscaling, continuous scroll.
/// Shared by `EditorPlaceholderView` (opening any `.pdf` `DocumentRef`) and
/// `PreviewConfirmSheet` (previewing a staged Sign/Fill Form output before
/// commit) — previously duplicated identically in both files.
struct ReadOnlyPDFPreviewPane: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = PDFDocument(url: url)
        view.displayMode = .singlePageContinuous
        view.autoScales = true
        view.backgroundColor = .systemBackground
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // Reload document if url changed (rare — parent typically
        // creates a fresh instance per file).
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
