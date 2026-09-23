import WebKit
import Foundation

/// A single row in the ONLYOFFICE AutoFilter dropdown, as extracted by JS.
struct NativeFilterItem: Identifiable {
    let id: Int        // index in the original checkbox list
    let text: String   // display label extracted from the DOM row
    let checked: Bool  // current checked state in the OO panel
}

/// A button descriptor extracted from a simple ONLYOFFICE `.asc-window` dialog.
struct OODialogButton {
    let label: String
    let isPrimary: Bool
}

/// Payload for an intercepted OO dialog that may contain a text input field.
struct OODialogPayload {
    let id: String
    let title: String
    let message: String
    let buttons: [OODialogButton]
    let defaultValue: String?   // non-nil → show a text field (e.g. Column Width)
}

/// Messages JS sends to Swift via `window.webkit.messageHandlers.editorBridge.postMessage(...)`.
enum OfficeBridgeMessage {
    /// sdk-core module loaded; window.receiveFileFromIOS is now defined.
    case scriptReady
    /// Editor is initialized and ready (inner frame loaded).
    case ready
    /// User triggered save; contains the file data.
    case save(fileName: String, data: Data)
    /// User made or discarded edits.
    case documentStateChange(isDirty: Bool)
    /// Programmatic save completed (no content — user-triggered saves use .save instead).
    case saved
    /// An error occurred in the editor.
    case editorError(message: String)
    /// Opening the file failed.
    case openError(message: String)
    /// DOM structure dump for debugging toolbar selectors.
    case domDump(entries: [String])
    /// API method name dump for debugging Asc.editor interface.
    case apiDump(methods: [String])
    /// JS intercepted the OO filter panel; show native filter UI with these rows.
    case showNativeFilter(items: [NativeFilterItem])
    /// Slide navigation changed; provides 1-based current slide and total count.
    case slideChange(current: Int, total: Int)
    /// Word page changed; provides 1-based current page and total page count.
    case wordPageChange(current: Int, total: Int)
    /// Thumbnail image captured from OO's rendering canvas for a slide.
    case slideThumbnail(slideNum: Int, data: Data)
    /// Word document statistics returned by asc_getDocumentStatistic.
    case wordCount(words: Int, chars: Int, charsNoSpace: Int, paragraphs: Int)
    /// JS intercepted a simple OO dialog; show as native UIAlertController (with optional text field).
    case nativeDialog(OODialogPayload)
    /// Excel sheet list changed or active sheet changed; provides all sheet names and the active index.
    case sheetList(names: [String], activeIndex: Int)
    /// Excel selection changed; provides the font name of the selected cell.
    case excelFontChange(fontName: String)
    /// Word selection changed; provides the font name at the cursor/selection.
    case wordFontChange(fontName: String)
    /// PPT text selection changed; provides the font name of the selected text.
    case pptFontChange(fontName: String)
    /// JS requests that the native UITextField keyboard proxy become first responder.
    case focusKeyboard
    /// JS requests that the native UITextField keyboard proxy resign first responder (keyboard hide).
    case blurKeyboard
    /// Unknown/unparseable message.
    case unknown(body: Any)
}

protocol OfficeBridgeDelegate: AnyObject {
    func officeBridge(_ bridge: OfficeBridge, didReceive message: OfficeBridgeMessage)
}

/// WKScriptMessageHandler — bridges JavaScript editor events to Swift.
///
/// Register on the WKUserContentController under name "editorBridge":
/// ```swift
/// config.userContentController.add(bridge, name: "editorBridge")
/// ```
final class OfficeBridge: NSObject, WKScriptMessageHandler {

    weak var delegate: OfficeBridgeDelegate?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let parsed = parse(body: message.body)
        delegate?.officeBridge(self, didReceive: parsed)
    }

    // MARK: - Parsing

    private func parse(body: Any) -> OfficeBridgeMessage {
        guard let dict = body as? [String: Any],
              let action = dict["action"] as? String
        else { return .unknown(body: body) }

        switch action {
        case "scriptReady":
            return .scriptReady

        case "ready":
            return .ready

        case "save":
            guard
                let fileName = dict["fileName"] as? String,
                let b64 = dict["base64data"] as? String,
                let data = Data(base64Encoded: b64)
            else { return .unknown(body: body) }
            return .save(fileName: fileName, data: data)

        case "documentStateChange":
            let isDirty = dict["isDirty"] as? Bool ?? false
            return .documentStateChange(isDirty: isDirty)

        case "saved":
            return .saved

        case "editorError", "saveError", "saveUnavailable":
            let msg = dict["message"] as? String ?? action
            return .editorError(message: msg)

        case "openError":
            let msg = dict["message"] as? String ?? "Open failed"
            return .openError(message: msg)

        case "domDump":
            let entries = dict["dump"] as? [String] ?? []
            return .domDump(entries: entries)

        case "apiDump":
            let methods = dict["methods"] as? [String] ?? []
            return .apiDump(methods: methods)

        case "showNativeFilter":
            let rawItems = dict["items"] as? [[String: Any]] ?? []
            let items: [NativeFilterItem] = rawItems.compactMap { d in
                guard let id = d["id"] as? Int, let text = d["text"] as? String else { return nil }
                return NativeFilterItem(id: id, text: text, checked: d["checked"] as? Bool ?? false)
            }
            return .showNativeFilter(items: items)

        case "slideChange":
            let current = dict["current"] as? Int ?? 1
            let total   = dict["total"]   as? Int ?? 1
            return .slideChange(current: current, total: total)

        case "wordPageChange":
            let current = dict["current"] as? Int ?? 1
            let total   = dict["total"]   as? Int ?? 1
            return .wordPageChange(current: current, total: total)

        case "slideThumbnail":
            let num = dict["slideNum"] as? Int ?? 1
            guard let b64 = dict["data"] as? String,
                  let data = Data(base64Encoded: b64)
            else { return .unknown(body: body) }
            return .slideThumbnail(slideNum: num, data: data)

        case "wordCount":
            let words        = dict["words"]        as? Int ?? 0
            let chars        = dict["chars"]        as? Int ?? 0
            let charsNoSpace = dict["charsNoSpace"] as? Int ?? 0
            let paragraphs   = dict["paragraphs"]   as? Int ?? 0
            return .wordCount(words: words, chars: chars, charsNoSpace: charsNoSpace, paragraphs: paragraphs)

        case "nativeDialog":
            let id           = dict["id"]           as? String ?? ""
            let title        = dict["title"]        as? String ?? ""
            let message      = dict["message"]      as? String ?? ""
            let defaultValue = dict["defaultValue"] as? String
            let rawBtns      = dict["buttons"]      as? [[String: Any]] ?? []
            let buttons      = rawBtns.map { d in
                OODialogButton(label: d["label"] as? String ?? "OK",
                               isPrimary: d["primary"] as? Bool ?? false)
            }
            let payload = OODialogPayload(id: id, title: title, message: message,
                                          buttons: buttons, defaultValue: defaultValue)
            return .nativeDialog(payload)

        case "sheetList":
            let names       = dict["names"]       as? [String] ?? []
            let activeIndex = dict["activeIndex"] as? Int      ?? 0
            return .sheetList(names: names, activeIndex: activeIndex)

        case "excelFont":
            let fontName = dict["font"] as? String ?? "Font"
            return .excelFontChange(fontName: fontName)

        case "wordFont":
            let fontName = dict["font"] as? String ?? "Font"
            return .wordFontChange(fontName: fontName)

        case "pptFont":
            let fontName = dict["font"] as? String ?? "Font"
            return .pptFontChange(fontName: fontName)

        case "focusKeyboard":
            return .focusKeyboard

        case "blurKeyboard":
            return .blurKeyboard

        case "debug":
            if let msg = dict["msg"] as? String {
                NSLog("[OO-DEBUG] %@", msg)
            }
            return .saved // silent no-op in UI

        default:
            return .unknown(body: body)
        }
    }
}
