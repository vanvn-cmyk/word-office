import UIKit
import WebKit

// MARK: - MammothPDFService

/// Converts DOCX/DOC files to PDF on-device using mammoth.js + WKWebView.createPDF().
///
/// Flow:
///  1. A hidden WKWebView loads docxconverter.html (which includes mammoth.min.js).
///  2. Swift calls window.convertDocx(docUrl) via evaluateJavaScript.
///  3. mammoth.js converts the DOCX ArrayBuffer to HTML and sets document.body.innerHTML.
///  4. JS posts "htmlReady" via the editorBridge message handler.
///  5. Swift calls WKWebView.createPDF() to capture the rendered HTML as a PDF.
///
/// Quality: mammoth.js preserves semantic structure (headings, bold/italic, tables,
/// lists, images) but not pixel-perfect Word layout. Sufficient for "Office→PDF" MVP.
@MainActor
final class MammothPDFService: NSObject {
    static let shared = MammothPDFService()

    private var webView: WKWebView?
    private let schemeHandler = OfficeSchemeHandler()
    private var isReady = false
    private var readyContinuations: [CheckedContinuation<Void, Error>] = []
    private var pdfContinuation: CheckedContinuation<Data, Error>?

    // MARK: - Public API

    func convertToPDF(from source: URL, to destination: URL) async throws {
        let fileData = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: source)
        }.value

        try await ensureReady()

        let docURL = schemeHandler.storeDocument(data: fileData, fileName: source.lastPathComponent)
        let safeURL = docURL.replacingOccurrences(of: "'", with: "\\'")

        let pdfData: Data = try await withCheckedThrowingContinuation { continuation in
            self.pdfContinuation = continuation
            self.webView?.evaluateJavaScript("void window.convertDocx('\(safeURL)')") { _, error in
                if let error {
                    self.pdfContinuation?.resume(throwing: error)
                    self.pdfContinuation = nil
                }
            }
        }

        try await Task.detached(priority: .userInitiated) {
            try pdfData.write(to: destination)
        }.value
    }

    // MARK: - Bridge callbacks

    fileprivate func handleMessage(_ body: Any) {
        guard let dict = body as? [String: Any],
              let action = dict["action"] as? String else { return }
        switch action {
        case "mammothReady":
            isReady = true
            let pending = readyContinuations
            readyContinuations = []
            pending.forEach { $0.resume() }

        case "htmlReady":
            guard let wv = webView else {
                pdfContinuation?.resume(throwing: MammothError.notReady)
                pdfContinuation = nil
                return
            }
            wv.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
                Task { @MainActor [weak self] in
                    switch result {
                    case .success(let data):
                        self?.pdfContinuation?.resume(returning: data)
                    case .failure(let err):
                        self?.pdfContinuation?.resume(throwing: err)
                    }
                    self?.pdfContinuation = nil
                }
            }

        case "htmlError":
            let msg = dict["error"] as? String ?? "mammoth conversion failed"
            pdfContinuation?.resume(throwing: MammothError.conversionFailed(msg))
            pdfContinuation = nil

        default:
            break
        }
    }

    // MARK: - WebView lifecycle

    private func ensureReady() async throws {
        if isReady { return }
        if webView == nil { setupWebView() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            readyContinuations.append(cont)
        }
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "office")
        config.userContentController.add(WeakProxy(target: self), name: "editorBridge")

        // A4 width (595pt) ensures createPDF produces A4-proportioned pages.
        // Off-screen position keeps it invisible but still rendered by the GPU.
        let wv = WKWebView(
            frame: CGRect(x: -20000, y: -20000, width: 595, height: 842),
            configuration: config
        )
        webView = wv

        // WKWebView must be in the view hierarchy for layout and createPDF() to work.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        scene?.windows.first?.addSubview(wv)

        wv.load(URLRequest(url: URL(string: "office://host/docxconverter.html")!))
    }
}

// MARK: - Weak proxy (breaks WKUserContentController retain cycle)

private final class WeakProxy: NSObject, WKScriptMessageHandler {
    weak var target: MammothPDFService?
    init(target: MammothPDFService) { self.target = target }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let body = message.body
        Task { @MainActor in
            self.target?.handleMessage(body)
        }
    }
}

// MARK: - Errors

enum MammothError: Error, LocalizedError {
    case notReady
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReady:              return "PDF renderer not ready"
        case .conversionFailed(let m): return "Conversion failed: \(m)"
        }
    }
}
