import Foundation

/// Where the user picks a file from when a tool needs one.
/// Carried as an associated value on `PDFToolDestination` so the tool view
/// knows which picker to open automatically when it first appears.
enum FilePickerSource: Hashable {
    case library
    case browse
}

/// Navigation destinations from the Tools home (`ToolsTabView`), per the approved
/// `Wireframe/PDFTools-Mockup-v2.html` — Convert (4 directions, §7.4), Organize
/// (Merge/Split, §7.1), Scan & OCR (§6). Session 12 (2026-09-04) added the
/// `Fill & Sign` category (`Wireframe/FillAndSign-Mockup-v1.html`) — Fill Form,
/// Sign (spec §9.1 Tier 1), Print (spec §3.3, backend from Session 6).
///
/// File-requiring cases carry an optional `FilePickerSource` that tells the
/// destination which picker to open automatically on first appear — set by
/// `ToolsTabView` after the user picks a source from the bottom sheet on the
/// Tools tab itself (before navigating in).
enum PDFToolDestination: Hashable {
    case merge(source: FilePickerSource? = nil)
    case split(source: FilePickerSource? = nil)
    case convert(ConvertDirection, source: FilePickerSource? = nil)
    case scan
    case fillForm(source: FilePickerSource? = nil)
    case sign(source: FilePickerSource? = nil)
    case print
}

/// The 4 Convert directions (§7.4). `To PDF` accepts any of the 3 Office formats
/// in one picker — not 3 separate directions (see Tools home mockup discussion).
enum ConvertDirection: Hashable, CaseIterable {
    case officeToPDF
    case pdfToWord
    case pdfToImage
    case imageToPDF

    var title: String {
        switch self {
        case .officeToPDF: "To PDF"
        case .pdfToWord:   "PDF to Word"
        case .pdfToImage:  "PDF to Image"
        case .imageToPDF:  "Image to PDF"
        }
    }
}
