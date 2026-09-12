import WebKit
import Foundation

/// A single row in the ONLYOFFICE AutoFilter dropdown, as extracted by JS.
struct NativeFilterItem: Identifiable {
    let id: Int        // index in the original checkbox list
    let text: String   // display label extracted from the DOM row
    let checked: Bool  // current checked state in the OO panel
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

        default:
            return .unknown(body: body)
        }
    }
}
