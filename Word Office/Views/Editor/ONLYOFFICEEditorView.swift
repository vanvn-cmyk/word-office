import SwiftUI
import WebKit

/// Full-screen ONLYOFFICE web editor for Office formats (DOCX, XLSX, PPTX).
///
/// Flow:
///   1. `.task` uploads the file to the proxy server → gets a session ID
///   2. WKWebView loads `/editor/<sessionId>` — the server-rendered editor page
///   3. `.onDisappear` downloads the edited file back (no-ops if user never saved)
struct ONLYOFFICEEditorView: View {
    let ref: DocumentRef
    let apiClient: ONLYOFFICEAPIClient

    @State private var phase: Phase = .uploading
    @State private var sessionId: String?

    enum Phase { case uploading, ready, failed(String) }

    var body: some View {
        Group {
            switch phase {
            case .uploading:
                VStack(spacing: DSSpacing.md) {
                    ProgressView()
                    Text("Opening document…")
                        .font(DSFont.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.dsDocumentCanvas)

            case .ready:
                if let id = sessionId {
                    _ONLYOFFICEWebView(baseURL: apiClient.baseURL, sessionId: id)
                        .ignoresSafeArea()
                }

            case .failed(let msg):
                ContentUnavailableView(
                    "Could Not Open Document",
                    systemImage: "exclamationmark.triangle",
                    description: Text(msg)
                )
            }
        }
        .task { await startSession() }
        .onDisappear {
            guard let id = sessionId else { return }
            Task { try? await apiClient.downloadEdited(sessionId: id, overwriting: ref.url) }
        }
    }

    private func startSession() async {
        do {
            let id = try await apiClient.upload(fileAt: ref.url, filename: ref.name)
            sessionId = id
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

// MARK: - UIViewControllerRepresentable

private struct _ONLYOFFICEWebView: UIViewControllerRepresentable {
    let baseURL: URL
    let sessionId: String

    func makeUIViewController(context: Context) -> _ONLYOFFICEWebViewController {
        _ONLYOFFICEWebViewController(baseURL: baseURL, sessionId: sessionId)
    }

    func updateUIViewController(_ vc: _ONLYOFFICEWebViewController, context: Context) {}
}

private final class _ONLYOFFICEWebViewController: UIViewController {
    private let baseURL: URL
    private let sessionId: String
    private var webView: WKWebView!

    init(baseURL: URL, sessionId: String) {
        self.baseURL = baseURL
        self.sessionId = sessionId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        let cfg = WKWebViewConfiguration()
        cfg.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let url = baseURL.appendingPathComponent("editor/\(sessionId)")
        webView.load(URLRequest(url: url))
    }
}
