import UIKit
import WebKit

/// UIViewController that hosts the offline ONLYOFFICE editor in a WKWebView.
///
/// Architecture:
///  1. `viewDidLoad` configures WKWebView with `office://` scheme handler and JS bridge.
///  2. Loads `office://host/editor.html` — the bootstrap HTML from OfficeBundle.
///  3. `webView(_:didFinish:)` fires → if `documentURL` is set, calls `sendFileToEditor`.
///  4. Caller may call `openFile(at:)` before or after the page loads; it auto-defers if needed.
///  5. When JS sends `save`, `onFileSaved` is called with the new Data + suggested file name.
final class OfficeEditorViewController: UIViewController {

    // MARK: - Properties

    private var webView: WKWebView!
    private let bridge = OfficeBridge()
    private var documentURL: URL?
    private var webViewReady = false

    /// Called when the editor has saved a file. Provides new Data and suggested file name.
    var onFileSaved: ((Data, String) -> Void)?
    /// Called when an error occurs.
    var onError: ((String) -> Void)?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        loadEditorHTML()
    }

    // MARK: - Public API

    func openFile(at url: URL) {
        documentURL = url
        if webViewReady {
            Task { await sendFileToEditor(url: url) }
        }
        // else: deferred until webView(_:didFinish:)
    }

    // MARK: - Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()

        // Register `office://` custom scheme for local bundle assets
        config.setURLSchemeHandler(OfficeSchemeHandler(), forURLScheme: "office")

        // Allow cross-origin requests (needed for CDN sdkjs loading via base href in scaffold HTML)
        config.preferences.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        // JS bridge
        bridge.delegate = self
        config.userContentController.add(bridge, name: "editorBridge")

        // Allow inline media (ONLYOFFICE may play notification sounds)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func loadEditorHTML() {
        let editorURL = URL(string: "office://host/editor.html")!
        webView.load(URLRequest(url: editorURL))
    }

    // MARK: - File I/O

    private func sendFileToEditor(url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            onError?("Could not read file: \(url.lastPathComponent)")
            return
        }

        let fileName = url.lastPathComponent
        let fileType = url.pathExtension.lowercased()
        let base64   = data.base64EncodedString()

        // Build the JS call manually; the payload is passed as a JS object literal
        // to avoid double-encoding issues with callAsyncJavaScript arguments dict.
        let escapedName = jsonEscape(fileName)
        let escapedType = jsonEscape(fileType)
        // base64 contains only [A-Za-z0-9+/=] — safe to interpolate
        let js = "receiveFileFromIOS({ fileName: \(escapedName), fileType: \(escapedType), base64data: \"\(base64)\" })"

        do {
            try await webView.callAsyncJavaScript(
                js,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
        } catch {
            onError?("Failed to open file: \(error.localizedDescription)")
        }
    }

    private func jsonEscape(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(value),
           let str  = String(data: data, encoding: .utf8) { return str }
        return "\"\""
    }
}

// MARK: - WKNavigationDelegate

extension OfficeEditorViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webViewReady = true
        if let url = documentURL {
            Task { await sendFileToEditor(url: url) }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onError?("WebView navigation failed: \(error.localizedDescription)")
    }
}

// MARK: - OfficeBridgeDelegate

extension OfficeEditorViewController: OfficeBridgeDelegate {
    func officeBridge(_ bridge: OfficeBridge, didReceive message: OfficeBridgeMessage) {
        switch message {
        case .save(let fileName, let data):
            onFileSaved?(data, fileName)

        case .editorError(let msg), .openError(let msg):
            onError?(msg)

        case .ready, .documentStateChange, .saved, .unknown:
            break
        }
    }
}
