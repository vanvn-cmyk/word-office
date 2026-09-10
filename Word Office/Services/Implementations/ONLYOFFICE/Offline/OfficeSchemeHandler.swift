import WebKit

/// Handles `office://host/…` requests from WKWebView and serves files
/// from the OfficeBundle directory bundled in the app.
///
/// Registered on the WKWebViewConfiguration as the scheme handler for "office".
/// Allows the editor HTML, JS, WASM and ONLYOFFICE scaffold to be served
/// locally without a server, enabling true offline editing.
final class OfficeSchemeHandler: NSObject, WKURLSchemeHandler {

    // MARK: - Bundle root

    private let bundleURL: URL = {
        guard let url = Bundle.main.url(forResource: "OfficeBundle", withExtension: nil) else {
            fatalError("OfficeBundle not found in app bundle — add folder reference in Xcode")
        }
        return url
    }()

    // MARK: - Active tasks

    private var activeTasks: Set<ObjectIdentifier> = []

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let taskId = ObjectIdentifier(urlSchemeTask)
        activeTasks.insert(taskId)

        let url = urlSchemeTask.request.url!
        // Strip `office://host` prefix → relative file path
        var path = url.path  // e.g. "/web-apps/apps/api/documents/api.js"
        if path.hasPrefix("/") { path = String(path.dropFirst()) }

        let fileURL = bundleURL.appendingPathComponent(path)

        guard activeTasks.contains(taskId) else { return }

        if let data = try? Data(contentsOf: fileURL) {
            let mimeType = mimeType(for: fileURL.pathExtension)
            let headers: [String: String] = [
                "Content-Type": mimeType,
                "Content-Length": "\(data.count)",
                "Cache-Control": "public, max-age=86400",
                "Access-Control-Allow-Origin": "*",
            ]
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } else {
            let response = HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain"]
            )!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive("Not found: \(path)".data(using: .utf8)!)
            urlSchemeTask.didFinish()
        }

        activeTasks.remove(taskId)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        activeTasks.remove(ObjectIdentifier(urlSchemeTask))
    }

    // MARK: - MIME helpers

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html":  return "text/html; charset=utf-8"
        case "js":    return "application/javascript; charset=utf-8"
        case "mjs":   return "application/javascript; charset=utf-8"
        case "wasm":  return "application/wasm"
        case "json":  return "application/json; charset=utf-8"
        case "css":   return "text/css; charset=utf-8"
        case "png":   return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg":   return "image/svg+xml"
        case "ico":   return "image/x-icon"
        case "ttf":   return "font/ttf"
        case "woff":  return "font/woff"
        case "woff2": return "font/woff2"
        default:      return "application/octet-stream"
        }
    }
}
