import WebKit
import Foundation

// MARK: - DocumentKind format codes

private extension DocumentKind {
    /// x2t / AVS_FILE_* format code for this kind as an input format.
    var x2tFormatCode: Int {
        switch self {
        case .docx:                 return 65   // AVS_FILE_DOCUMENT_DOCX
        case .doc:                  return 66   // AVS_FILE_DOCUMENT_DOC
        case .rtf:                  return 68   // AVS_FILE_DOCUMENT_RTF
        case .txt, .markdown:       return 69   // AVS_FILE_DOCUMENT_TXT
        case .xlsx:                 return 257  // AVS_FILE_SPREADSHEET_XLSX
        case .xls:                  return 258  // AVS_FILE_SPREADSHEET_XLS
        case .pptx:                 return 129  // AVS_FILE_PRESENTATION_PPTX
        case .ppt:                  return 130  // AVS_FILE_PRESENTATION_PPT
        default:                    return 65
        }
    }
}

// MARK: - X2tConverterService

/// Converts Office documents to PDF on-device using the x2t.wasm engine bundled
/// with the ONLYOFFICE SDK. No network connection or commercial license required.
///
/// Runs a hidden WKWebView that loads `converter.html`, which imports X2tConverter
/// from `sdk-core/index.mjs` and exposes `window.x2tConvert()`. Swift calls that
/// function via `evaluateJavaScript` and receives the PDF bytes back through the
/// `editorBridge` WKScriptMessageHandler.
///
/// The WebView is created lazily and kept alive as a singleton so the 63 MB x2t.wasm
/// stays resident after the first conversion — subsequent conversions are fast.
@MainActor
final class X2tConverterService: NSObject {
    static let shared = X2tConverterService()

    private var webView: WKWebView?
    private let schemeHandler = OfficeSchemeHandler()
    private var isReady = false
    private var readyContinuations: [CheckedContinuation<Void, Error>] = []
    private var conversionContinuation: CheckedContinuation<Data, Error>?

    // MARK: - Export entry point

    func exportPDF(from source: URL, to destination: URL) async throws {
        // File I/O off main thread — local files are fast, but don't block UI.
        let fileData = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: source)
        }.value

        // Ensure the converter WebView is initialized and x2t.wasm is loaded.
        try await ensureReady()

        // Store file bytes in OfficeSchemeHandler so JS can fetch them via
        // office://host/doc/<uuid>.ext — no base64 encoding needed for the input.
        let docURL = schemeHandler.storeDocument(data: fileData, fileName: source.lastPathComponent)

        let kind = DocumentKind(rawValue: source.pathExtension.lowercased()) ?? .docx
        let formatCode = kind.x2tFormatCode
        // Escape single quotes in filename to avoid breaking the JS string literal.
        let safeName = source.lastPathComponent.replacingOccurrences(of: "'", with: "\\'")
        let js = "void window.x2tConvert('\(docURL)', \(formatCode), '\(safeName)')"

        // Kick off conversion and wait for the bridge callback.
        let pdfData: Data = try await withCheckedThrowingContinuation { continuation in
            self.conversionContinuation = continuation
            self.webView?.evaluateJavaScript(js) { _, error in
                if let error {
                    // evaluateJavaScript itself failed (page not loaded, syntax error, etc.)
                    self.conversionContinuation?.resume(throwing: X2tError.jsEvalFailed(error))
                    self.conversionContinuation = nil
                }
                // Happy path: continuation is resolved later via bridge callback.
            }
        }

        try await Task.detached(priority: .userInitiated) {
            try pdfData.write(to: destination)
        }.value
    }

    // MARK: - WebView lifecycle

    private func ensureReady() async throws {
        if isReady { return }
        if webView == nil { setupWebView() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readyContinuations.append(continuation)
        }
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "office")

        // Use a weak proxy to avoid the WKUserContentController retain-cycle.
        let proxy = WeakMessageHandlerProxy(target: self)
        config.userContentController.add(proxy, name: "editorBridge")

        let wv = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1, height: 1),
            configuration: config
        )
        webView = wv
        wv.load(URLRequest(url: URL(string: "office://host/converter.html")!))
    }

    // MARK: - Bridge callbacks (called by WeakMessageHandlerProxy)

    fileprivate func handleBridgeMessage(_ body: Any) {
        guard let dict = body as? [String: Any],
              let action = dict["action"] as? String else { return }

        switch action {
        case "converterReady":
            isReady = true
            let pending = readyContinuations
            readyContinuations = []
            pending.forEach { $0.resume() }

        case "convertResult":
            let success = dict["success"] as? Bool ?? false
            if success,
               let b64 = dict["base64pdf"] as? String,
               let data = Data(base64Encoded: b64) {
                conversionContinuation?.resume(returning: data)
            } else {
                let msg = dict["error"] as? String ?? "Unknown x2t error"
                conversionContinuation?.resume(throwing: X2tError.conversionFailed(msg))
            }
            conversionContinuation = nil

        case "converterError":
            isReady = false
            let msg = dict["error"] as? String ?? "x2t init failed"
            let err = X2tError.initFailed(msg)
            let pending = readyContinuations
            readyContinuations = []
            pending.forEach { $0.resume(throwing: err) }

        default:
            break
        }
    }
}

// MARK: - Weak proxy (breaks WKUserContentController retain cycle)

private final class WeakMessageHandlerProxy: NSObject, WKScriptMessageHandler {
    weak var target: X2tConverterService?
    init(target: X2tConverterService) { self.target = target }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let body = message.body
        Task { @MainActor in
            self.target?.handleBridgeMessage(body)
        }
    }
}

// MARK: - Errors

enum X2tError: Error, LocalizedError {
    case jsEvalFailed(Error)
    case conversionFailed(String)
    case initFailed(String)

    var errorDescription: String? {
        switch self {
        case .jsEvalFailed(let e):    return "JavaScript error: \(e.localizedDescription)"
        case .conversionFailed(let m): return "Conversion failed: \(m)"
        case .initFailed(let m):       return "x2t failed to initialize: \(m)"
        }
    }
}

// MARK: - DocumentExporting adapter

/// Thin adapter that bridges the @MainActor conversion services to the
/// DocumentExporting protocol (which must be Sendable).
///
/// Routing:
///  • DOCX / DOC → MammothPDFService (mammoth.js + WKWebView.createPDF)
///    — reliable on iOS; x2t's PDF renderer is not functional in the WASM build.
///  • Other formats → X2tConverterService (best-effort; may fail for PDF output).
final class X2tDocumentExporter: DocumentExporting, @unchecked Sendable {
    func exportPDF(from source: URL, to destination: URL) async throws {
        let ext = source.pathExtension.lowercased()
        if ext == "docx" || ext == "doc" {
            try await MammothPDFService.shared.convertToPDF(from: source, to: destination)
        } else {
            try await X2tConverterService.shared.exportPDF(from: source, to: destination)
        }
    }
}
