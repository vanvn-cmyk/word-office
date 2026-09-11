import WebKit
import Foundation

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

        default:
            return .unknown(body: body)
        }
    }
}
