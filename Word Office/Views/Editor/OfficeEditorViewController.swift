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

    // Shared content process pool — reusing the same process avoids the ~300-500ms
    // cold-start overhead when the editor is reopened within the same app session.
    private static let processPool = WKProcessPool()

    // MARK: - Properties

    private var webView: WKWebView!
    private let bridge = OfficeBridge()
    private let schemeHandler = OfficeSchemeHandler()
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
    /// Called when the active slide changes in PPT. Provides 1-based current index and total count.
    var onSlideChange: ((Int, Int) -> Void)?
    /// Called when JS captures a slide thumbnail from OO's render canvas.
    var onSlideThumbnail: ((Int, Data) -> Void)?

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

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release in-memory image cache to ease pressure before iOS kills the process.
        schemeHandler.clearImageCache()
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

    /// Prints the current document using iOS UIPrintInteractionController.
    /// Uses WKWebView's viewPrintFormatter() which captures the canvas-rendered OO content.
    func printDocument() {
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = documentURL?.lastPathComponent ?? "Document"

        let pc = UIPrintInteractionController.shared
        pc.printInfo = printInfo
        pc.printFormatter = webView.viewPrintFormatter()
        pc.present(animated: true, completionHandler: nil)
    }

    /// Inserts an image by converting to a data URL and using insertImageByDataURL,
    /// which creates an inner-frame blob URL before calling asc_insertImageFromUrl.
    /// Must NOT use insertImageByURL with a data: URL — that path calls AddImageUrl([dataURL])
    /// which triggers OO's internal HTTP loader, showing "Loading Image" and hanging
    /// because OO's WASM HTTP client cannot fetch data: scheme URLs.
    func insertImage(data: Data, mimeType: String = "image/jpeg") {
        guard scriptReady else { return }
        let b64 = data.base64EncodedString()
        // Store to window property first to avoid parsing a 700KB string literal inline.
        webView.evaluateJavaScript("window.__pendingImg = 'data:\(mimeType);base64,\(b64)';") { [weak self] _, _ in
            self?.webView.evaluateJavaScript(
                "window.insertImageByDataURL(window.__pendingImg); window.__pendingImg = null;"
            )
        }
    }

    /// Sends the user's filter selection back to the hidden OO filter panel.
    /// `selectedIds` are the checkbox indices the user left checked; pass empty + cancel=true to dismiss.
    func applyNativeFilter(selectedIds: [Int], cancel: Bool) {
        guard scriptReady else { return }
        let idsJSON = selectedIds.map { String($0) }.joined(separator: ",")
        let js = "window._applyNativeFilter([\(idsJSON)], \(cancel ? "true" : "false"))"
        webView.evaluateJavaScript(js)
    }

    /// Inserts a hyperlink via window._insertHyperlink defined in editor.html.
    /// That helper uses the cached _innerWin reference and restores OO cursor focus
    /// before calling the API, avoiding the cross-frame querySelector + lost-cursor issue.
    func insertHyperlink(url: String, displayText: String) {
        guard scriptReady else { return }
        let urlJS  = jsStringLiteral(url)
        let textJS = jsStringLiteral(displayText)
        webView.evaluateJavaScript("window._insertHyperlink(\(urlJS), \(textJS));")
    }

    /// Adds a comment via window._addComment defined in editor.html.
    func addComment(text: String) {
        guard scriptReady else { return }
        let textJS = jsStringLiteral(text)
        webView.evaluateJavaScript("window._addComment(\(textJS));")
    }

    /// Inserts a chart via window._insertChart. The type string maps to OO chart type constants in editor.html.
    func insertChart(type: String) {
        guard scriptReady else { return }
        let typeJS = jsStringLiteral(type)
        webView.evaluateJavaScript("window._insertChart(\(typeJS));")
    }

    /// Inserts a table using a direct ONLYOFFICE API sequence.
    /// Bypasses `window.execEditorCommand('insert-table')` which falls back to
    /// `_clickOOBtn` — clicking OO's hidden toolbar button opens OO's native
    /// insert-table dialog, which crashes WKWebView on iOS (same mechanism as chart wizard).
    func insertTable(rows: Int, cols: Int) {
        guard scriptReady else { return }
        let r = rows, c = cols
        let js = """
        (function(r,c){
          try {
            var ed = window._innerWin && window._innerWin.Asc && window._innerWin.Asc.editor;
            if (!ed) return;
            var done = false;
            // Word/PPT APIs first — asc_addTable and put_Table both accept (rows, cols).
            // asc_fmtTableApply is Excel-only (formats selection as table); calling it in
            // Word silently succeeds without inserting anything, blocking the real APIs.
            // put_Table is Word-only — use it first. asc_addTable is Excel-only and may
            // silently succeed in Word without inserting anything, blocking the real API.
            var pairs = [
              ['put_Table',         function(){ ed.put_Table(r, c); }],
              ['asc_addTable',      function(){ ed.asc_addTable(r, c); }],
              ['CreateTable',       function(){ ed.CreateTable(r, c); }],
              ['asc_fmtTableApply', function(){ ed.asc_fmtTableApply(null, null, true); }],
              ['asc_insertTable',   function(){ ed.asc_insertTable(); }],
            ];
            for (var i = 0; i < pairs.length; i++) {
              if (!done && typeof ed[pairs[i][0]] === 'function') {
                try { pairs[i][1](); done = true; console.log('[iOS] insertTable via', pairs[i][0]); } catch(e) { console.warn('[iOS] insertTable', pairs[i][0], e); }
              }
            }
          } catch(e) {}
        })(\(r), \(c));
        """
        webView.evaluateJavaScript(js)
    }

    /// Inserts a text box on the current PPT slide via window._insertTextBox.
    /// That function uses StartAddShape('textRect') + mouse simulation to draw the box
    /// at a centred position, then auto-double-clicks to enter text-edit mode immediately.
    func insertTextBox() {
        guard scriptReady else { return }
        webView.evaluateJavaScript("window._insertTextBox();")
    }

    /// Inserts a Unicode symbol/special character at the current cursor position.
    /// Tries ONLYOFFICE's internal typeText APIs, falls back to execCommand insertText.
    func insertSymbol(_ char: String) {
        guard scriptReady else { return }
        let charJS = jsStringLiteral(char)
        let js = """
        (function(c) {
          var ed = window._innerWin && window._innerWin.Asc && window._innerWin.Asc.editor;
          if (ed) {
            if (typeof ed.asc_typeText === 'function') { try { ed.asc_typeText(c); return; } catch(_) {} }
            if (typeof ed.asc_TypeText === 'function') { try { ed.asc_TypeText(c); return; } catch(_) {} }
          }
          try {
            window._innerWin && window._innerWin.focus();
            var iDoc = window._innerWin && window._innerWin.document;
            if (iDoc) {
              var sdk = iDoc.getElementById('editor_sdk') || iDoc.body;
              sdk.focus();
              iDoc.execCommand('insertText', false, c);
            }
          } catch(_) {}
        })(\(charJS));
        """
        webView.evaluateJavaScript(js)
    }

    /// Inserts a shape via window._insertShape. The type is an OO shape preset name (rect, ellipse, etc.).
    func insertShape(type: String) {
        guard scriptReady else { return }
        let typeJS = jsStringLiteral(type)
        webView.evaluateJavaScript("window._insertShape(\(typeJS));")
    }

    /// Applies a font family to the current text selection via window.ooSetFontFamily.
    func setFontFamily(_ name: String) {
        guard scriptReady else { return }
        let nameJS = jsStringLiteral(name)
        webView.evaluateJavaScript("window.ooSetFontFamily(\(nameJS));")
    }

    /// Performs find (and optional replace) via window.ooFindReplace.
    func findAndReplace(find: String, replace: String, replaceAll: Bool) {
        guard scriptReady else { return }
        let findJS    = jsStringLiteral(find)
        let replaceJS = jsStringLiteral(replace)
        webView.evaluateJavaScript("window.ooFindReplace(\(findJS), \(replaceJS), \(replaceAll ? "true" : "false"));")
    }

    /// Shows a UIAlertController with word/character statistics.
    func showWordCountAlert(words: Int, chars: Int, charsNoSpace: Int, paragraphs: Int) {
        let message = """
            Words: \(words)
            Characters (with spaces): \(chars)
            Characters (no spaces): \(charsNoSpace)
            Paragraphs: \(paragraphs)
            """
        let alert = UIAlertController(title: "Word Count", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - JS string helpers

    /// Returns a JS string literal (with surrounding quotes and proper escaping) for the given Swift string.
    /// Uses JSONEncoder — JSONSerialization requires Array/Dictionary at top level and throws NSException
    private func jsStringLiteral(_ s: String) -> String {
        if let data = try? JSONEncoder().encode(s),
           let str  = String(data: data, encoding: .utf8) { return str }
        return "\"\""
    }

    // MARK: - Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()

        // Share the content process across editor instances so reopening a document
        // reuses the warm process instead of spawning a new one (~300-500ms savings).
        config.processPool = Self.processPool

        // Register `office://` custom scheme for local bundle assets + in-memory stores
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "office")

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

        // Injected into every frame (forMainFrameOnly:false) — runs both in editor.html
        // AND directly inside OO's inner "frameEditor" iframe. When running in the inner
        // frame, document IS the OO editor document — no cross-frame _d gymnastics needed.
        let ooUIScript = WKUserScript(source: #"""
            (function() {
                window._ooInjectEnabled = true;

                var CSS = [
                    /* Ribbon toolbar */
                    '#toolbar{display:none!important;height:0!important;min-height:0!important;overflow:hidden!important}',
                    /* Coauthor / info badges */
                    '#id-btn-coauthors,#btn-coauthors,#btn-info,#id-btn-info,.btn-header-info,',
                    '#id-spreadsheet-info,.icon-info-container,#collaboration-info,',
                    '.asc-info-icon,.coauthors-btn,.btn-icon-info{display:none!important}',
                    /* Right sidebar */
                    '#right-panel,#id-right-panel,.right-panel,.rightpanel,',
                    '#id-right-panel-spreadsheet,#spreadsheetRightPanel,',
                    '[id*="right-panel"],[class*="right-panel"]{display:none!important}',
                    /* Left icon strip */
                    '#leftmenu,.leftmenu,#id-sidebar,.asc-leftmenu,',
                    '[id*="leftmenu"],[class*="leftmenu"],',
                    '#id-toolbar-left,[id*="left-panel-btn"]{display:none!important}',
                    /* PPT splitters */
                    '.resizer,.splitter{display:none!important}',
                    /* PPT thumbnail panel — OO 9.x VERIFIED ID (underscore, not hyphen).
                       visibility:hidden (NOT display:none) during loading: OO's 52% init step
                       measures offsetWidth of this panel to calculate canvas size. display:none
                       returns offsetWidth=0 → OO's init loop waits/fights → stuck at 52%.
                       After loading completes, ShowThumbnails(false) removes it from layout. */
                    '#id_panel_thumbnails{visibility:hidden!important;pointer-events:none!important}',
                    '#id_panel_notes{display:none!important;height:0!important;overflow:hidden!important}',
                    /* PPT canvas containers — the thumbnail panel is visibility:hidden (not
                       display:none) so OO can measure its offsetWidth during the 52% init step.
                       But the panel still occupies layout space and pushes area_id_main to the
                       right. Force both the outer parent AND the main area to left:0 so the
                       editing canvas starts at the screen edge. Width NOT overridden on area_id_main
                       because OO reads el.style.width inline for canvas-size calculation. */
                    '#id_main_parent{left:0!important}',
                    '#area_id_main{left:0!important;margin-left:0!important}',
                    /* Legacy/fallback selectors for other OO versions */
                    '#id-pe-panel-aside,.pe-panel-aside,',
                    '[id*="pe-panel-aside"],[class*="pe-panel-aside"],',
                    '.slide-panel-left,[class*="slide-panel"],',
                    '#slides-panel,#id-slides-panel,.slides-panel,.slidesPanel,',
                    '.presenter-panel,.presenterPanel,.leftThumbPanel',
                    '{display:none!important;width:0!important;min-width:0!important;max-width:0!important;flex:0 0 0!important;overflow:hidden!important}',
                    /* PPT notes panel — legacy names */
                    '#id-pe-notes,[id*="pe-notes"],[class*="pe-notes"],',
                    '#id-notes-panel,.notes-panel,[id*="notes-panel"],[class*="notes-panel"]',
                    '{display:none!important}',
                    /* Scrollbars */
                    '#ws-v-scrollbar,#ws-h-scrollbar,#ws-scrollbar-corner{display:none!important}',
                    '::-webkit-scrollbar{width:0!important;height:0!important}'
                ].join('');

                var SELECTORS = [
                    '#toolbar',
                    '#id-btn-coauthors','#btn-info','#id-btn-info',
                    '.btn-header-info','.asc-info-icon','.coauthors-btn',
                    '#right-panel','#id-right-panel','.right-panel',
                    '#leftmenu','.leftmenu','#id-sidebar','.asc-leftmenu'
                ];

                // PPT panel hide — targets OO 9.x verified element IDs (underscores).
                // #id_panel_thumbnails = slide thumbnails panel (left sidebar)
                // #id_panel_notes      = speaker notes panel (bottom)
                // OO SDK auto-recalculates canvas bounds when panel display=none.
                function _pptHideByID() {
                    var panelEl = document.getElementById('id_panel_thumbnails');
                    var notesEl = document.getElementById('id_panel_notes');
                    if (!panelEl) return false; // OO not rendered yet

                    // visibility:hidden keeps the panel in layout flow so OO can measure it;
                    // do NOT change display — let OO's own layout:{leftMenu:false} config
                    // manage the display state. Overriding display mid-load causes the 52% freeze.
                    // ShowThumbnails(false) is called from onDocumentReady in editor.html.
                    panelEl.style.setProperty('visibility',     'hidden', 'important');
                    panelEl.style.setProperty('pointer-events', 'none',   'important');
                    if (notesEl) {
                        notesEl.style.setProperty('display',  'none',   'important');
                        notesEl.style.setProperty('height',   '0',      'important');
                        notesEl.style.setProperty('overflow', 'hidden', 'important');
                    }


                    // Continuous version of the same repair the diagnostic dump below does
                    // once at fixed checkpoints. Log evidence showed OO doesn't just leave
                    // this collapsed once — it re-asserts display:none on it repeatedly
                    // (a one-time force-visible gets overwritten again within one tick), so
                    // a single fix at T2000/T5000 isn't enough. This re-checks and re-forces
                    // every 250ms for as long as the editor stays open (capped at 5 min,
                    // matching this file's other observer caps) instead of fixing once.
                    var _pptForceVisibleCount = 0, _pptForceVisibleLastLogged = 0;
                    function _pptForceVisibleTick() {
                        try {
                            var _fvMp = document.getElementById('id_main_parent');
                            if (!_fvMp) return;
                            var _fvCv = null;
                            var _fvCvs = _fvMp.querySelectorAll('canvas');
                            for (var _fi = 0; _fi < _fvCvs.length; _fi++) {
                                if (_fvCvs[_fi].width > 100) { _fvCv = _fvCvs[_fi]; break; }
                            }
                            if (!_fvCv) return;
                            var _fvEl = _fvCv.parentElement, _fvDepth = 0, _fvHit = false;
                            while (_fvEl && _fvEl !== _fvMp && _fvDepth < 8) {
                                if (window.getComputedStyle(_fvEl).display === 'none') {
                                    _fvEl.style.setProperty('display', 'block', 'important');
                                    _fvHit = true;
                                }
                                _fvEl = _fvEl.parentElement; _fvDepth++;
                            }
                            if (_fvHit) {
                                _pptForceVisibleCount++;
                                try { window.dispatchEvent(new Event('resize')); } catch(_) {}
                                // Throttle logging — this can fire every tick while OO keeps
                                // re-hiding, and NSLog at 250ms cadence for minutes would flood.
                                if (_pptForceVisibleCount - _pptForceVisibleLastLogged >= 20) {
                                    _pptForceVisibleLastLogged = _pptForceVisibleCount;
                                    try { window.webkit.messageHandlers.editorBridge.postMessage(
                                        {action:'debug', msg:'[OO-ppt-forcevis] repaired '+_pptForceVisibleCount+' times so far'}
                                    ); } catch(_) {}
                                }
                            }
                        } catch(_) {}
                    }
                    var _pptForceVisibleInterval = setInterval(_pptForceVisibleTick, 250);
                    setTimeout(function() { try { clearInterval(_pptForceVisibleInterval); } catch(_) {} }, 300000);

                    // Diagnostic dump — runs after OO has settled
                    function _pptDump(label) {
                        try {
                            var mp  = document.getElementById('id_main_parent');
                            var am  = document.getElementById('area_id_main');
                            var d   = '[PPT-'+label+']';
                            if (mp) {
                                var cs = window.getComputedStyle(mp);
                                var mpR = mp.getBoundingClientRect();
                                d += ' mp:left='+cs.left+' w='+cs.width+' h='+cs.height+' ov='+cs.overflow;
                                d += ' mp.rect=('+Math.round(mpR.left)+','+Math.round(mpR.top)+','+Math.round(mpR.width)+','+Math.round(mpR.height)+')';
                                // Log left-menu sibling so we know if it's taking space
                                var lm = document.getElementById('id_left_menu') || document.getElementById('left-menu');
                                if (lm) { var lmC=window.getComputedStyle(lm); d+=' lm:w='+lmC.width+' disp='+lmC.display; } else { d+=' lm:MISSING'; }
                                // Log first visible slide canvas + its full parent chain
                                var _firstCv = null;
                                mp.querySelectorAll('canvas').forEach(function(c,i){
                                    var cc=window.getComputedStyle(c);
                                    if (cc.display==='none') return;
                                    var r=c.getBoundingClientRect();
                                    d+=' cv['+i+']:px='+c.width+'×'+c.height+' cssW='+cc.width+' rect=('+Math.round(r.left)+','+Math.round(r.top)+','+Math.round(r.width)+','+Math.round(r.height)+')';
                                    if (!_firstCv && c.width > 100) _firstCv = c;
                                });
                                // Parent chain of first large canvas (find the collapsing ancestor)
                                if (_firstCv) {
                                    var _el = _firstCv.parentElement; var _depth = 0;
                                    d += ' chain:';
                                    var _repaired = [];
                                    while (_el && _el !== mp && _depth < 8) {
                                        var _er = _el.getBoundingClientRect();
                                        var _ec = window.getComputedStyle(_el);
                                        d += '['+(_el.id||_el.className.split(' ')[0]||'?')+' r=('+Math.round(_er.left)+','+Math.round(_er.top)+','+Math.round(_er.width)+','+Math.round(_er.height)+') disp='+_ec.display+' ov='+_ec.overflow+']';
                                        // Watchdog: an ancestor of the real slide canvas sitting at
                                        // display:none is never something WE set (nothing in this
                                        // file or editor.html targets these OO-internal ids) — it's
                                        // OO's own layout code leaving it collapsed, intermittently,
                                        // after the thumbnail-panel hide/show sequence (seen ~50% of
                                        // opens). Give OO one natural cycle to self-correct (skip on
                                        // the T500 pass) — if it's STILL display:none by T2000+, force
                                        // it visible directly. This only flips one CSS property back
                                        // to what every working run already shows it should be
                                        // (block) — it does not call any OO zoom/layout API, so it
                                        // can't hit the "recomputed zoom -> 0" failure mode that
                                        // asc_setZoomType/zoomFitToPage did.
                                        if (label !== 'T500' && _ec.display === 'none') {
                                            _el.style.setProperty('display', 'block', 'important');
                                            _repaired.push(_el.id || _el.className.split(' ')[0] || '?');
                                        }
                                        _el = _el.parentElement; _depth++;
                                    }
                                    if (_repaired.length) {
                                        d += ' REPAIRED:' + _repaired.join(',');
                                        try { window.dispatchEvent(new Event('resize')); } catch(_) {}
                                    }
                                }
                                // getCountPages to verify OO load state
                                try { var _ed2=window.Asc&&window.Asc.editor; if(_ed2&&typeof _ed2.getCountPages==='function') d+=' pages='+_ed2.getCountPages(); } catch(_){}
                            } else { d+=' mp:MISSING'; }
                            if (am) {
                                var cs2=window.getComputedStyle(am);
                                d+=' am:left='+cs2.left+' w='+cs2.width+' zi='+cs2.zIndex+' disp='+cs2.display+' bg='+cs2.backgroundColor;
                            } else { d+=' am:MISSING'; }
                            try {
                                var ed=window.Asc&&window.Asc.editor;
                                if(ed){
                                    // bShowThumbnails is the internal bool OO updates after ShowThumbnails()
                                    d+=' showThumb='+(ed.bShowThumbnails);
                                    d+=' hasShowFn='+(typeof ed.ShowThumbnails==='function');
                                }
                            } catch(_){}
                            window.webkit.messageHandlers.editorBridge.postMessage({action:'debug',msg:d});
                        } catch(_){}
                    }
                    setTimeout(function(){ _pptDump('T500'); },  500);
                    setTimeout(function(){ _pptDump('T2000'); }, 2000);
                    setTimeout(function(){ _pptDump('T5000'); }, 5000);
                    return true;
                }

                function pptHide() {
                    // Primary: direct ID targeting (OO 9.x verified)
                    if (_pptHideByID()) return;

                    // OO JS API (inner frame only) — try panel API methods
                    if (typeof window.Asc !== 'undefined') {
                        try {
                            var _oed = window.Asc && window.Asc.editor;
                            if (_oed) {
                                ['asc_SetThumbPanelVisible','asc_setThumbPanelVisible','setThumbPanelVisible'].forEach(function(fn) {
                                    if (typeof _oed[fn] === 'function') { try { _oed[fn](false); } catch(_) {} }
                                });
                                ['asc_SetNotesPanelVisible','asc_setNotesPanelVisible'].forEach(function(fn) {
                                    if (typeof _oed[fn] === 'function') { try { _oed[fn](false); } catch(_) {} }
                                });
                            }
                        } catch(_) {}
                    }

                    // Geometry fallback — used when OO not yet rendered or different version
                    var w = window.innerWidth  || 390;
                    var h = window.innerHeight || 700;
                    var maxPanelW = w * 0.45;
                    var didHide = false;
                    try {
                        document.querySelectorAll('*').forEach(function(el) {
                            try {
                                var tag = el.tagName.toLowerCase();
                                if (tag === 'canvas' || tag === 'script' || tag === 'style' ||
                                    tag === 'html'   || tag === 'body'   || tag === 'iframe') return;
                                var r = el.getBoundingClientRect();
                                if (r.width <= 0 || r.height <= 0) return;
                                if (el.querySelectorAll) {
                                    var _hasMain = false;
                                    el.querySelectorAll('canvas').forEach(function(c) {
                                        var cw = c.width || c.offsetWidth || 0;
                                        var ch = c.height || c.offsetHeight || 0;
                                        if (cw > 200 && ch > 100) _hasMain = true;
                                    });
                                    if (_hasMain) return;
                                }
                                if (r.left <= 150 && r.width >= 40 && r.width < maxPanelW && r.height > h * 0.5) {
                                    el.style.setProperty('display',   'none',    'important');
                                    el.style.setProperty('width',     '0',       'important');
                                    el.style.setProperty('overflow',  'hidden',  'important');
                                    didHide = true;
                                    var par = el.parentElement;
                                    if (par) {
                                        for (var ki = 0; ki < par.children.length; ki++) {
                                            var sib = par.children[ki];
                                            if (sib === el) continue;
                                            var sr = sib.getBoundingClientRect();
                                            if (sr.width > w * 0.1 || sr.height > h * 0.1) {
                                                sib.style.setProperty('left',  '0',    'important');
                                                sib.style.setProperty('width', '100%', 'important');
                                            }
                                        }
                                        par.style.setProperty('padding-left', '0', 'important');
                                    }
                                    return;
                                }
                                if (r.bottom >= h - 10 && r.height > 10 && r.height < h * 0.4 && r.width > w * 0.25) {
                                    el.style.setProperty('display',  'none',   'important');
                                    el.style.setProperty('height',   '0',      'important');
                                    el.style.setProperty('overflow', 'hidden', 'important');
                                    didHide = true;
                                }
                            } catch(_) {}
                        });
                    } catch(_) {}
                    if (didHide) { try { window.dispatchEvent(new Event('resize')); } catch(_) {} }
                }

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
                    pptHide();
                }

                // Slide count reporter — works in both outer (cross-frame) and inner frame contexts.
                function reportSlides() {
                    try {
                        var _innerFr2 = document.querySelector('iframe[name="frameEditor"]');
                        var _ooWin = _innerFr2 ? _innerFr2.contentWindow : window;
                        var ed = _ooWin && _ooWin.Asc && _ooWin.Asc.editor;
                        if (!ed) return;

                        var cur = 1, tot = 1;
                        var curFns = ['asc_getCurrentSlide','asc_getCurrentPage',
                                      'asc_getCurrentPageIndex','getCurrentPageIndex'];
                        for (var i = 0; i < curFns.length; i++) {
                            if (typeof ed[curFns[i]] === 'function') {
                                try { cur = (ed[curFns[i]]() || 0) + 1; break; } catch(_) {}
                            }
                        }
                        var totFns = ['asc_getSlidesCount','asc_getSlideCount',
                                      'asc_getCountPages','asc_getPagesCount','getSlideCount'];
                        for (var j = 0; j < totFns.length; j++) {
                            if (typeof ed[totFns[j]] === 'function') {
                                try { tot = ed[totFns[j]]() || 1; break; } catch(_) {}
                            }
                        }
                        // Brute-force: try ALL methods containing "count"/"pages"/"slides"
                        if (tot <= 1) {
                            try {
                                var _obj2 = ed;
                                for (var _qi = 0; _qi < 5 && _obj2 && tot <= 1; _qi++) {
                                    Object.getOwnPropertyNames(_obj2).forEach(function(m) {
                                        if (tot > 1) return;
                                        if (!/count|pages|slides/i.test(m)) return;
                                        if (typeof _obj2[m] !== 'function') return;
                                        try {
                                            var v = ed[m]();
                                            if (typeof v === 'number' && v > 1) tot = v;
                                        } catch(_) {}
                                    });
                                    _obj2 = Object.getPrototypeOf(_obj2);
                                }
                            } catch(_) {}
                        }
                        // Dump available slide/page/panel methods to Xcode console
                        try {
                            var _meths = []; var _o = ed;
                            for (var _pi = 0; _pi < 5 && _o; _pi++) {
                                Object.getOwnPropertyNames(_o).forEach(function(m) {
                                    if (/slide|page|count|thumb|note|panel|view/i.test(m)) _meths.push(m);
                                });
                                _o = Object.getPrototypeOf(_o);
                            }
                            window.webkit.messageHandlers.editorBridge.postMessage(
                                {action:'debug', msg:'[OO-methods] tot='+tot+' cur='+cur+' | '+_meths.join(' ')}
                            );
                        } catch(_) {}
                        // Always post (even if tot=1, so strip updates)
                        try { window.webkit.messageHandlers.editorBridge.postMessage(
                            {action: 'slideChange', current: cur, total: tot}
                        ); } catch(_) {}
                        // Capture thumbnail for current slide from OO's render canvas
                        captureThumb(cur);
                    } catch(_) {}
                }

                // Capture OO's main rendering canvas as a thumbnail for the given slide.
                // Finds the largest canvas in the document (= OO's slide render canvas),
                // downscales to 192×108 (2× our 96×54 strip card), and bridges as JPEG.
                // Works from both the outer frame (via frameEditor contentDocument) and from
                // inside the inner OO frame when ooUIScript runs there (forMainFrameOnly:false).
                function captureThumb(slideNum) {
                    try {
                        // Resolve the document containing OO's canvases
                        var targetDoc;
                        var _fr = document.querySelector('iframe[name="frameEditor"]');
                        if (_fr && _fr.contentDocument && _fr.contentDocument.body) {
                            targetDoc = _fr.contentDocument;  // running in outer frame
                        } else if (typeof window.Asc !== 'undefined' || !_fr) {
                            targetDoc = document;  // running inside the OO inner frame itself
                        }
                        if (!targetDoc) return;

                        // Find the largest canvas — OO's main slide render canvas.
                        // Skips tiny canvases (icons, rulers) by requiring > 100×60.
                        var biggest = null, bigArea = 0;
                        targetDoc.querySelectorAll('canvas').forEach(function(c) {
                            var w = c.width || c.offsetWidth || 0;
                            var h = c.height || c.offsetHeight || 0;
                            var area = w * h;
                            if (area > bigArea && w > 100 && h > 60) { bigArea = area; biggest = c; }
                        });
                        if (!biggest) return;

                        // Downscale to 192×108 (2× native strip card 96×54, sharp on Retina)
                        var out = document.createElement('canvas');
                        out.width  = 192;
                        out.height = 108;
                        var ctx = out.getContext('2d');
                        if (!ctx) return;
                        ctx.drawImage(biggest, 0, 0, biggest.width, biggest.height, 0, 0, 192, 108);
                        var b64 = out.toDataURL('image/jpeg', 0.6).split(',')[1];
                        if (!b64) return;
                        window.webkit.messageHandlers.editorBridge.postMessage(
                            { action: 'slideThumbnail', slideNum: slideNum, data: b64 }
                        );
                    } catch(_) {}
                }

                // Targeted PPT observer — fires with zero debounce whenever an element
                // matching known panel patterns is added or has its class/id changed.
                // Complements CSS (which handles elements already in DOM at inject time)
                // without the cost of a full querySelectorAll scan on every mutation.
                // Underscore IDs are OO 9.x verified; hyphen patterns are legacy fallback
                var _pptRE = /id_panel_thumbnails|id_panel_notes|pe-panel-aside|panel-thumbnails|pe-thumbnails|pe-left-panel|pe-panel-left|slide-panel|thumbnails-panel|slides-panel|slidesPanel|thumbnail-panel|thumbnailPanel|pe-notes|notes-panel/i;
                function _hidePPTEl(el) {
                    if (!el || el.nodeType !== 1) return;
                    var elId = el.id || '';
                    // Direct underscore-ID match (OO 9.x verified thumbnail panel)
                    if (elId === 'id_panel_thumbnails') {
                        // visibility:hidden only — never override display so OO's own
                        // layout: {leftMenu:false} config can manage display state freely.
                        el.style.setProperty('visibility',     'hidden', 'important');
                        el.style.setProperty('pointer-events', 'none',   'important');
                        return;
                    }
                    if (elId === 'id_panel_notes') {
                        el.style.setProperty('display',  'none',   'important');
                        el.style.setProperty('height',   '0',      'important');
                        el.style.setProperty('overflow', 'hidden', 'important');
                        return;
                    }
                    var sig = ' ' + elId + ' ' + (typeof el.className === 'string' ? el.className : '');
                    if (!_pptRE.test(sig)) return;
                    el.style.setProperty('display',   'none',    'important');
                    el.style.setProperty('width',     '0',       'important');
                    el.style.setProperty('min-width', '0',       'important');
                    el.style.setProperty('flex',      '0 0 0',   'important');
                    el.style.setProperty('overflow',  'hidden',  'important');
                }
                var _pptObs = new MutationObserver(function(muts) {
                    muts.forEach(function(m) {
                        m.addedNodes.forEach(function(n) {
                            if (n.nodeType !== 1) return;
                            _hidePPTEl(n);
                            try { n.querySelectorAll('*').forEach(_hidePPTEl); } catch(_) {}
                        });
                        if (m.type === 'attributes' && m.target) _hidePPTEl(m.target);
                    });
                });
                // Dedicated watcher for id_panel_thumbnails style attribute changes —
                // re-hides the panel if OO's JS re-shows it after our initial hide.
                function _watchPanelEl() {
                    var panelEl = document.getElementById('id_panel_thumbnails');
                    if (!panelEl || panelEl._watched) return;
                    panelEl._watched = true;
                    var watcher = new MutationObserver(function() {
                        // Keep panel invisible if OO tries to restore it.
                        // Use visibility:hidden (same as loading phase) — not display:none,
                        // since post-load OO may still need to measure it for transitions.
                        var v = panelEl.style.visibility;
                        if (v !== 'hidden') {
                            panelEl.style.setProperty('visibility',     'hidden', 'important');
                            panelEl.style.setProperty('pointer-events', 'none',   'important');
                        }
                    });
                    watcher.observe(panelEl, { attributes: true, attributeFilter: ['style'] });
                    setTimeout(function() { try { watcher.disconnect(); } catch(_) {} }, 60000);
                }


                inject();
                document.addEventListener('DOMContentLoaded', inject);
                window.addEventListener('load', inject);

                var _obsTimer = null;
                var obs = new MutationObserver(function() {
                    if (!window._ooInjectEnabled) return;
                    if (_obsTimer) return;
                    _obsTimer = setTimeout(function() {
                        _obsTimer = null;
                        inject();
                    }, 300);
                });
                obs.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class'] });
                setTimeout(function() { try { obs.disconnect(); } catch(_) {} }, 180000);
                try {
                    _pptObs.observe(document.body || document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'id', 'style'] });
                    setTimeout(function() { try { _pptObs.disconnect(); } catch(_) {} }, 30000);
                } catch(_) {}

                // Interval: short burst after load (5s), then stop — observer + CSS cover the rest
                var n = 0;
                var t = setInterval(function() {
                    inject();
                    if (++n >= 10) clearInterval(t);
                }, 500);
                // Late-fire slide count (PPT may load slides slowly)
                setTimeout(reportSlides, 3000);
                setTimeout(reportSlides, 6000);
                setTimeout(reportSlides, 10000);
                setTimeout(reportSlides, 20000);
                setTimeout(reportSlides, 30000);

                // Thumbnail strip only gets a real image for whichever slide the user has
                // actually viewed (captureThumb reads OO's live render canvas — there's no
                // way to grab a slide's bitmap without OO having drawn it at least once).
                // This walks every OTHER slide once, captures it, then returns to the slide
                // the user was actually on — reusing the exact same goToPage-family call
                // used by the native strip's own tap-to-navigate ("slide-goto:N") command,
                // so it's the same already-exercised path, not a new one. Self-contained:
                // does not touch reportSlides/captureThumb, and the existing _pptDump
                // watchdog (display:none repair) runs independently of this and still
                // protects against the canvas-collapse bug regardless of what triggers it.
                function _prefetchOtherThumbnails() {
                    try {
                        var _pfFr = document.querySelector('iframe[name="frameEditor"]');
                        var _pfWin = _pfFr && _pfFr.contentWindow;
                        var _pfEd = _pfWin && _pfWin.Asc && _pfWin.Asc.editor;
                        if (!_pfEd) return;

                        var _origSlide = 1, _pfTot = 1;
                        var _pfCurFns = ['asc_getCurrentSlide','asc_getCurrentPage','asc_getCurrentPageIndex'];
                        for (var _pi = 0; _pi < _pfCurFns.length; _pi++) {
                            if (typeof _pfEd[_pfCurFns[_pi]] === 'function') {
                                try { _origSlide = (_pfEd[_pfCurFns[_pi]]() || 0) + 1; break; } catch(_) {}
                            }
                        }
                        var _pfTotFns = ['asc_getSlidesCount','asc_getSlideCount','asc_getCountPages','asc_getPagesCount','getSlideCount'];
                        for (var _ti = 0; _ti < _pfTotFns.length; _ti++) {
                            if (typeof _pfEd[_pfTotFns[_ti]] === 'function') {
                                try { _pfTot = _pfEd[_pfTotFns[_ti]]() || 1; break; } catch(_) {}
                            }
                        }
                        if (_pfTot <= 1) return; // single slide (or count unknown) — nothing to prefetch

                        var _pfGotoFns = ['goToPage','asc_goToPage','asc_goToSlide','asc_GoToPage',
                                          'asc_setCurrentPage','asc_changeCurrentSlide','asc_SetCurrentSlide','asc_changeCurrentPage'];
                        function _pfGoto(idx1) {
                            var idx0 = idx1 - 1;
                            for (var _gi = 0; _gi < _pfGotoFns.length; _gi++) {
                                if (typeof _pfEd[_pfGotoFns[_gi]] === 'function') {
                                    try { _pfEd[_pfGotoFns[_gi]](idx0); return true; } catch(_) {}
                                }
                            }
                            return false;
                        }

                        var _pfQueue = [];
                        for (var _s = 1; _s <= _pfTot; _s++) { if (_s !== _origSlide) _pfQueue.push(_s); }

                        function _pfStep() {
                            if (!_pfQueue.length) {
                                // Done — return to the slide the user was actually viewing and
                                // resync the native strip's highlighted index.
                                _pfGoto(_origSlide);
                                setTimeout(function() {
                                    try {
                                        captureThumb(_origSlide);
                                        window.webkit.messageHandlers.editorBridge.postMessage(
                                            { action: 'slideChange', current: _origSlide, total: _pfTot }
                                        );
                                    } catch(_) {}
                                }, 450);
                                return;
                            }
                            var _next = _pfQueue.shift();
                            if (_pfGoto(_next)) {
                                setTimeout(function() {
                                    try { captureThumb(_next); } catch(_) {}
                                    setTimeout(_pfStep, 250);
                                }, 450);
                            } else {
                                setTimeout(_pfStep, 50); // nav API unavailable — skip to next
                            }
                        }
                        _pfStep();
                    } catch(_) {}
                }
                // Starts after the first two reportSlides passes (3s, 6s) have already
                // captured the originally-viewed slide and confirmed OO is stable.
                setTimeout(_prefetchOtherThumbnails, 6500);
                // PPT geometry fallback — CSS + observer cover most cases; these two
                // catch panels that appeared before the observer attached or escaped CSS.
                setTimeout(pptHide, 300);
                setTimeout(pptHide, 2000);
                setTimeout(_watchPanelEl, 1000);
                setTimeout(_watchPanelEl, 3000);
                setTimeout(_watchPanelEl, 8000);
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
        // Prevent UIScrollView from delaying touches to detect scrolling — the toolbar
        // rows are ScrollViews and this makes button taps feel immediate.
        webView.scrollView.delaysContentTouches = false
        // Suppress long-press link preview (300ms delay on every tap in the WebView).
        webView.allowsLinkPreview = false
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

        let fileName = url.lastPathComponent
        let fileType = url.pathExtension.lowercased()

        let data: Data? = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value

        guard let data else {
            onError?("Could not read file: \(fileName)")
            return
        }

        // Store doc bytes in the scheme handler; JS fetches via office:// URL.
        // No base64 encoding — eliminates the 33% memory overhead and the 45 MB cap.
        let docURL = schemeHandler.storeDocument(data: data, fileName: fileName)

        let escapedName   = jsonEscape(fileName)
        let escapedType   = jsonEscape(fileType)
        let escapedDocURL = jsonEscape(docURL)
        let js = "receiveFileFromIOS({ fileName: \(escapedName), fileType: \(escapedType), fileURL: \(escapedDocURL) })"

        do {
            try await webView.callAsyncJavaScript(
                js, arguments: [:], in: nil, contentWorld: .page
            )
        } catch {
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
    // iOS killed the WebContent process (OOM or watchdog). Reload so the editor
    // comes back; if scriptReady was true the file will be re-sent automatically.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        scriptReady  = false
        editorLoaded = false
        webView.reload()
    }

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
            // Fatal only if it fires BEFORE onAppReady (engine load failure, api.js
            // missing, sdkCore import error). onAppReady now posts 'ready' immediately,
            // so editorLoaded = true before any OO document-loading or feature error fires.
            // Document-loading errors (x2t failure, unsupported format) show OO's own
            // native error dialog inside the editor — no need to kill the editor view.
            if !editorLoaded {
                onError?(msg)
            }

        case .openError(let msg):
            // Always fatal — the document itself could not be opened.
            onError?(msg)

        case .ready:
            editorLoaded = true
            onReady?()
            // Delay filter interception by 3s so OO can restore any saved state
            // (auto-opened filter panels, view settings) without triggering native sheet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.webView?.evaluateJavaScript("window._filterInterceptEnabled = true;")
            }
            // Dump live DOM 4s after ready so ONLYOFFICE has finished rendering toolbar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.webView.evaluateJavaScript("window.execEditorCommand('dump-dom')")
            }

        case .documentStateChange(let dirty):
            onDirtyChange?(dirty)

        case .domDump(let entries):
            // Print ALL edge elements unfiltered — JS already pre-filters to right/bottom/corner
            NSLog("=== OO EDGE DUMP (%d elements) ===", entries.count)
            entries.forEach { NSLog("  %@", $0) }
            NSLog("=== END EDGE DUMP ===")

        case .apiDump(let methods):
            print("=== ONLYOFFICE Asc.editor align/sort/merge methods ===")
            methods.forEach { print("  \($0)") }
            print("=== END API DUMP (\(methods.count) methods) ===")

        case .showNativeFilter(let items):
            onFilterRequest?(items)

        case .slideChange(let current, let total):
            onSlideChange?(current, total)

        case .slideThumbnail(let slideNum, let data):
            onSlideThumbnail?(slideNum, data)

        case .wordCount(let words, let chars, let charsNoSpace, let paragraphs):
            DispatchQueue.main.async { [weak self] in
                self?.showWordCountAlert(words: words, chars: chars, charsNoSpace: charsNoSpace, paragraphs: paragraphs)
            }

        case .saved, .unknown:
            break
        }
    }
}
