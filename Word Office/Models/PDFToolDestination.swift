import Foundation

/// Navigation destinations from the Tools home (`ToolsTabView`), per the approved
/// `Wireframe/PDFTools-Mockup-v2.html` — Convert (4 directions, §7.4), Organize
/// (Merge/Split, §7.1), Scan & OCR (§6).
enum PDFToolDestination: Hashable {
    case merge
    case split
    case convert(ConvertDirection)
    case scan
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
