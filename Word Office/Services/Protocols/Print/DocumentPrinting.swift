import Foundation

/// Present the system print sheet (AirPrint) for a document.
/// See Phase0-Implementation-Logic-v2.md §3.3.
protocol DocumentPrinting: Sendable {
    /// Present the AirPrint sheet for `url`. Returns once the sheet is dismissed
    /// (job accepted or cancelled) — does not wait for the physical print to finish.
    func print(_ url: URL, jobName: String) async throws
}

enum DocumentPrintingError: Error, Sendable, LocalizedError {
    case noPresentingViewController
    case printFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPresentingViewController:
            "Couldn't find a view controller to present from"
        case .printFailed(let reason):
            "Printing failed: \(reason)"
        }
    }
}
