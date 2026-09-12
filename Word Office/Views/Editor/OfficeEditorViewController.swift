import UIKit
import SwiftUI
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
    // True after JS posts scriptReady — means window.receiveFileFromIOS is defined.
    private var scriptReady = false
    // True after JS posts 'ready' (onAppReady fired, editor UI visible).
    // Any editorError arriving before this is a fatal init failure.
    // Any editorError arriving after this is a non-fatal runtime feature
    // error (e.g. ONLYOFFICE module unavailable offline) — must NOT kill
    // the editor or the user loses all unsaved edits.
    private var editorLoaded = false
    // Watchdog: if scriptReady hasn't arrived within 40s of the page loading,
    // the JS bridge silently failed. Surface an error instead of an infinite spinner.
    private var scriptReadyWatchdog: DispatchWorkItem?

    /// Called when the editor has saved a file. Provides new Data and suggested file name.
    var onFileSaved: ((Data, String) -> Void)?
    /// Called when an error occurs.
    var onError: ((String) -> Void)?
    /// Called when the editor is fully ready (sdkjs loaded and rendered).
    var onReady: (() -> Void)?
    /// Called whenever the document dirty state changes (true = unsaved edits, false = clean).
    var onDirtyChange: ((Bool) -> Void)?
    /// Called when JS intercepts the OO filter panel; present native filter UI.
    var onFilterRequest: (([NativeFilterItem]) -> Void)?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        guard Bundle.main.url(forResource: "OfficeBundle", withExtension: nil) != nil else {
            onError?("Editor bundle missing from app. Please reinstall the app.")
            return
        }
        setupWebView()
        loadEditorHTML()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    func openFile(at url: URL) {
        documentURL = url
        if scriptReady {
            Task { await sendFileToEditor(url: url) }
        }
        // else: deferred until bridge receives scriptReady
    }

    /// Sends a formatting command to the ONLYOFFICE inner iframe via `window.execEditorCommand`.
    /// Commands: 'bold', 'italic', 'underline', 'strikeout', 'undo', 'redo',
    ///           'align-left', 'align-center', 'align-right', 'align-justify',
    ///           'list-bullet', 'list-numbered', 'style:<StyleName>'
    func execEditorCommand(_ cmd: String) {
        guard scriptReady else { return }
        // cmd only contains alphanumeric, hyphens, and spaces (style names) — safe to interpolate
        webView.evaluateJavaScript("window.execEditorCommand('\(cmd)')")
    }

    func insertImage(dataURL: String) {
        guard scriptReady else { return }
        let escaped = dataURL.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.insertImageByDataURL('\(escaped)')")
    }

    /// Sends the user's filter selection back to the hidden OO filter panel.
    /// `selectedIds` are the checkbox indices the user left checked; pass empty + cancel=true to dismiss.
    func applyNativeFilter(selectedIds: [Int], cancel: Bool) {
        guard scriptReady else { return }
        let idsJSON = selectedIds.map { String($0) }.joined(separator: ",")
        let js = "window._applyNativeFilter([\(idsJSON)], \(cancel ? "true" : "false"))"
        webView.evaluateJavaScript(js)
    }

    /// Inserts a hyperlink at the current cursor position using ONLYOFFICE's asc_insertHyperlink API.
    func insertHyperlink(url: String, displayText: String) {
        guard scriptReady else { return }
        let urlJS  = jsStringLiteral(url)
        let textJS = jsStringLiteral(displayText)
        let js = """
        (function(url, text) {
          var _iw = document.querySelector('iframe[name="frameEditor"]');
          if (!_iw) return;
          var iwin = _iw.contentWindow;
          var _ed = iwin.Asc && iwin.Asc.editor;
          if (!_ed) return;
          try {
            var _A = iwin.Asc || {};
            var HyperCls = _A.asc_CHyperlink
              || (iwin.AscCommon && iwin.AscCommon.asc_CHyperlink)
              || iwin.asc_CHyperlink;
            if (HyperCls) {
              var hl = new HyperCls();
              typeof hl.asc_setUrl  === 'function' ? hl.asc_setUrl(url)   : (hl.Url  = url);
              typeof hl.asc_setText === 'function' ? hl.asc_setText(text) : (hl.Text = text);
              if (typeof _ed.asc_insertHyperlink === 'function') { _ed.asc_insertHyperlink(hl); return; }
              if (typeof _ed.asc_addHyperlink    === 'function') { _ed.asc_addHyperlink(hl);    return; }
            }
            // Fallback: focused command
            iwin.focus();
            iwin.AscDesktopEditor && iwin.AscDesktopEditor.executeFocusedCommand('InsertHyperlink');
          } catch(e) { console.warn('[iOS] insertHyperlink:', e); }
        })(\(urlJS), \(textJS));
        """
        webView.evaluateJavaScript(js)
    }

    /// Adds a comment at the current selection using ONLYOFFICE's asc_addComment API.
    func addComment(text: String) {
        guard scriptReady else { return }
        let textJS = jsStringLiteral(text)
        let js = """
        (function(text) {
          var _iw = document.querySelector('iframe[name="frameEditor"]');
          if (!_iw) return;
          var iwin = _iw.contentWindow;
          var _ed = iwin.Asc && iwin.Asc.editor;
          if (!_ed) return;
          try {
            if (typeof _ed.asc_addComment === 'function') { _ed.asc_addComment(text, true); return; }
            if (typeof _ed.asc_AddComment === 'function') { _ed.asc_AddComment(text);        return; }
            iwin.focus();
            iwin.AscDesktopEditor && iwin.AscDesktopEditor.executeFocusedCommand('AddComment');
          } catch(e) { console.warn('[iOS] addComment:', e); }
        })(\(textJS));
        """
        webView.evaluateJavaScript(js)
    }

    // MARK: - JS string helpers

    /// Returns a JS string literal (with surrounding quotes and proper escaping) for the given Swift string.
    private func jsStringLiteral(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: s),
              let str  = String(data: data, encoding: .utf8) else { return "\"\"" }
        return str
    }

    // MARK: - Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()

        // Register `office://` custom scheme for local bundle assets
        config.setURLSchemeHandler(OfficeSchemeHandler(), forURLScheme: "office")

        // JS bridge
        bridge.delegate = self
        // Capture JS errors → editorBridge so they surface in Swift UI
        let errorCapture = WKUserScript(source: """
            window.onerror = function(msg, src, line, col, err) {
                // Cross-frame errors always arrive as "Script error." with src="" line=0.
                // They are already caught inside the inner frame — safe to discard here.
                if (!src && (!line || line === 0)) return true;
                // After the editor has fully loaded, any JS error is a non-fatal
                // feature error (insert command, unsupported API, etc.) — not engine init.
                if (window._editorFullyLoaded) {
                    console.warn('[editor] non-fatal post-load JS error:', msg, src + ':' + line);
                    return true;
                }
                try { webkit.messageHandlers.editorBridge.postMessage(
                    { action: 'editorError', message: 'JS error: ' + msg + ' (' + src + ':' + line + ')' }
                ); } catch(_) {}
            };
            window.addEventListener('unhandledrejection', function(e) {
                // window._editorFullyLoaded is set by editor.html once onAppReady fires.
                // After that point, rejections come from individual features (offline
                // modules, unsupported chart types, clipboard access, etc.) — they are
                // non-fatal and must NOT close the editor.
                if (window._editorFullyLoaded) {
                    console.warn('[editor] non-fatal rejection (feature error):', String(e.reason));
                    return;
                }
                // Pre-load rejections are fatal (module import / engine init failed).
                try { webkit.messageHandlers.editorBridge.postMessage(
                    { action: 'editorError', message: 'Unhandled promise rejection: ' + String(e.reason) }
                ); } catch(_) {}
            });
            """, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.add(bridge, name: "editorBridge")
        config.userContentController.addUserScript(errorCapture)

        // Injected into every frame. Hides ONLYOFFICE chrome in the inner iframe.
        // #toolbar = entire ONLYOFFICE ribbon (File/Home/Insert tabs + formatting row).
        // Kept: #cell-editing-box (formula bar), #statusbar (sheet tabs/page info).
        let ooUIScript = WKUserScript(source: #"""
            (function() {
                var CSS = [
                    /* ── Ribbon: File/Home/Insert tab row + all formatting buttons ── */
                    /* Replaced by the native EditorTopToolbar above the WebView.     */
                    '#toolbar{display:none!important;height:0!important;min-height:0!important;overflow:hidden!important}',
                    /* ── Info / collaboration / co-author floating buttons ── */
                    '#id-btn-coauthors,#btn-coauthors,#btn-info,#id-btn-info,.btn-header-info,',
                    '#id-spreadsheet-info,.icon-info-container,#collaboration-info,',
                    '.asc-info-icon,.coauthors-btn,.btn-icon-info{display:none!important}',
                    /* ── Right panel / insert sidebar (table, shape, image, chart…) ── */
                    '#right-panel,#id-right-panel,.right-panel,.rightpanel,',
                    '#id-right-panel-spreadsheet,#spreadsheetRightPanel,',
                    '[id*="right-panel"],[class*="right-panel"]{display:none!important}',
                    /* ── Left sidebar icon strip (search / spell / info buttons) ── */
                    '#leftmenu,.leftmenu,#id-sidebar,.asc-leftmenu,',
                    '[id*="leftmenu"],[class*="leftmenu"],',
                    '#id-toolbar-left,[id*="left-panel-btn"]{display:none!important}',
                    /* ── Scrollbars (touch scrolling handled by WKWebView) ── */
                    '#ws-v-scrollbar,#ws-h-scrollbar,#ws-scrollbar-corner{display:none!important}',
                    '::-webkit-scrollbar{width:0!important;height:0!important}'
                    /* Formula bar (#cell-editing-box) and status bar (#statusbar)   */
                    /* are intentionally kept — editing features on mobile.          */
                ].join('');

                var SELECTORS = [
                    '#toolbar',
                    '#id-btn-coauthors', '#btn-coauthors', '#btn-info', '#id-btn-info',
                    '.btn-header-info', '.asc-info-icon', '.coauthors-btn', '.btn-icon-info',
                    '#right-panel', '#id-right-panel', '.right-panel', '.rightpanel',
                    '#leftmenu', '.leftmenu', '#id-sidebar', '.asc-leftmenu'
                ];

                function inject() {
                    var head = document.head || document.documentElement;
                    if (!head) return;
                    if (!document.getElementById('_oo_hide_style')) {
                        var s = document.createElement('style');
                        s.id = '_oo_hide_style';
                        s.textContent = CSS;
                        head.appendChild(s);
                    }
                    SELECTORS.forEach(function(sel) {
                        try { document.querySelectorAll(sel).forEach(function(el) {
                            if (el.style.display !== 'none')
                                el.style.setProperty('display', 'none', 'important');
                        }); } catch(e) {}
                    });
                }

                inject();
                document.addEventListener('DOMContentLoaded', inject);
                window.addEventListener('load', inject);

                var obs = new MutationObserver(inject);
                obs.observe(document.documentElement, { childList: true, subtree: true });

                var n = 0;
                var t = setInterval(function() { inject(); if (++n >= 20) clearInterval(t); }, 500);
            })();
            """#, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(ooUIScript)

        // Allow inline media (ONLYOFFICE may play notification sounds)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
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

    // callAsyncJavaScript serialises its script as a UTF-16 JS string before passing
    // it to WebKit. The engine rejects strings larger than ~128 MB (JSC limit), and
    // iOS crashes the process around 64 MB in practice. Base64 expands ~33%, so a
    // 48 MB source file produces a ~64 MB string — right at the threshold.
    // The proper long-term fix is to upload the file via the office:// scheme handler
    // (serve it as office://host/tmp/<uuid>/<name> and pass only the URL to JS).
    // Until then, guard here so users get a readable error instead of a silent crash.
    private static let base64SafeLimit = 45 * 1_024 * 1_024  // 45 MB raw → ~60 MB base64

    private func sendFileToEditor(url: URL) async {
        // Read the document on a background thread — this function is called from
        // @MainActor context and Data(contentsOf:) would otherwise block the main thread.
        let accessing = url.startAccessingSecurityScopedResource()
        // defer fires when this async function returns (after all awaits), so
        // the security scope covers both the background read and base64 encoding.
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let fileName = url.lastPathComponent
        let fileType = url.pathExtension.lowercased()

        let data: Data? = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value

        guard let data else {
            onError?("Could not read file: \(fileName)")
            return
        }

        // Guard before base64 encoding: very large files exceed the JS string size limit
        // and cause a silent crash or an opaque WKError.
        if data.count > Self.base64SafeLimit {
            let mb = data.count / (1_024 * 1_024)
            onError?(
                "\"\(fileName)\" is \(mb) MB — files larger than 45 MB cannot be " +
                "opened in the editor yet. Support for large files is coming in a future update."
            )
            return
        }

        let base64 = await Task.detached(priority: .userInitiated) {
            data.base64EncodedString()
        }.value

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
            // Extract JS exception detail from WKError userInfo when available
            let nsError = error as NSError
            let jsMessage = nsError.userInfo["WKJavaScriptExceptionMessage"] as? String
                ?? nsError.userInfo["NSLocalizedDescription"] as? String
                ?? error.localizedDescription
            onError?("JS error: \(jsMessage)")
        }
    }

    private func jsonEscape(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(value),
           let str  = String(data: data, encoding: .utf8) { return str }
        return "\"\""
    }

    // MARK: - Theme

    // ONLYOFFICE exposes `window.DocEditor.currentDocument.theme.changeTheme(id)` and
    // the simpler `AscCommon.AscBrowser.isDarkTheme` toggle. The official JS API for
    // runtime theme change is `window._doceditor?.changeTheme?.({id: "theme-dark"})`.
    private func sendThemeToEditor() {
        guard scriptReady else { return }
        let isDark = traitCollection.userInterfaceStyle == .dark
        let themeId = isDark ? "theme-dark" : "theme-light"
        let js = """
            (function() {
                try {
                    if (window._doceditor && window._doceditor.changeTheme) {
                        window._doceditor.changeTheme({ id: "\(themeId)" });
                    } else if (window.DocsAPI && window.DocsAPI._editor && window.DocsAPI._editor.changeTheme) {
                        window.DocsAPI._editor.changeTheme({ id: "\(themeId)" });
                    }
                } catch(e) {}
            })();
            """
        webView.evaluateJavaScript(js)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        sendThemeToEditor()
    }
}

// MARK: - WKNavigationDelegate

extension OfficeEditorViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webViewReady = true
        // Do NOT send file here — wait for scriptReady from JS (dynamic import is async).
        startScriptReadyWatchdog()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        scriptReadyWatchdog?.cancel()
        onError?("WebView navigation failed: \(error.localizedDescription)")
    }

    private func startScriptReadyWatchdog() {
        scriptReadyWatchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.scriptReady else { return }
            self.onError?(
                "The editor took too long to initialize. " +
                "Please close and reopen the document."
            )
        }
        scriptReadyWatchdog = item
        // 40 s: ONLYOFFICE's own 30s timeout fires first if it's a CDN failure,
        // so this only triggers for silent JS bridge failures.
        DispatchQueue.main.asyncAfter(deadline: .now() + 40, execute: item)
    }
}

// MARK: - WKUIDelegate

extension OfficeEditorViewController: WKUIDelegate {
    // ONLYOFFICE's inner editor HTML fires window.alert() after a 30-second
    // timeout when its scripts fail to load (CDN unreachable on first launch).
    // Intercept it here so the user sees our error UI instead of a raw JS alert.
    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let isEditorLoadTimeout = message.contains("connection is too slow")
            || message.contains("components could not be loaded")
            || message.contains("reload the page")

        if isEditorLoadTimeout {
            onError?(
                "The editor engine could not load. " +
                "Connect to the internet and reopen the file — the editor downloads ~86 MB of " +
                "components on first use, and again if they were cleared from device storage."
            )
        } else {
            onError?("Editor error: \(message)")
        }
        completionHandler()
    }
}

// MARK: - OfficeBridgeDelegate

extension OfficeEditorViewController: OfficeBridgeDelegate {
    func officeBridge(_ bridge: OfficeBridge, didReceive message: OfficeBridgeMessage) {
        switch message {
        case .scriptReady:
            scriptReady = true
            scriptReadyWatchdog?.cancel()
            if let url = documentURL {
                Task { await sendFileToEditor(url: url) }
            }

        case .save(let fileName, let data):
            onFileSaved?(data, fileName)

        case .editorError(let msg):
            // Fatal only while the editor is still initialising (engine load failure,
            // api.js error, etc.). Once the editor UI is visible (`editorLoaded`),
            // these are runtime feature errors from ONLYOFFICE internals (offline
            // modules, unsupported operations, clipboard access) — swallow silently
            // so the user keeps their unsaved edits.
            if !editorLoaded {
                onError?(msg)
            }

        case .openError(let msg):
            // Always fatal — the document itself could not be opened.
            onError?(msg)

        case .ready:
            editorLoaded = true
            onReady?()
            // Dump live DOM 4s after ready so ONLYOFFICE has finished rendering toolbar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.webView.evaluateJavaScript("window.execEditorCommand('dump-dom')")
            }

        case .documentStateChange(let dirty):
            onDirtyChange?(dirty)

        case .domDump(let entries):
            let relevant = entries.filter { line in
                let lower = line.lowercased()
                return lower.contains("toolbar") || lower.contains("header") ||
                       lower.contains("tabbar") || lower.contains("statusbar") ||
                       lower.contains("formula") || lower.contains("ribbon") ||
                       lower.contains("tabs-") || lower.contains("cell-edit")
            }
            print("=== ONLYOFFICE DOM DUMP (toolbar-related) ===")
            relevant.forEach { print("  \($0)") }
            print("=== END DOM DUMP (\(entries.count) total elements) ===")

        case .apiDump(let methods):
            print("=== ONLYOFFICE Asc.editor align/sort/merge methods ===")
            methods.forEach { print("  \($0)") }
            print("=== END API DUMP (\(methods.count) methods) ===")

        case .showNativeFilter(let items):
            onFilterRequest?(items)

        case .saved, .unknown:
            break
        }
    }
}
