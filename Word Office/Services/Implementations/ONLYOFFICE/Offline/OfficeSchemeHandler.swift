import WebKit

/// Handles `office://host/…` requests from WKWebView and serves files
/// from the OfficeBundle directory bundled in the app.
///
/// Registered on the WKWebViewConfiguration as the scheme handler for "office".
/// Allows the editor HTML, JS, WASM and ONLYOFFICE scaffold to be served
/// locally without a server, enabling true offline editing.
///
/// Also serves dynamically-uploaded images at `office://host/img/<uuid>.<ext>`.
/// This avoids passing large base64 strings through the JS bridge (which spikes
/// memory in the WKWebView content process and can trigger an iOS OOM kill).
final class OfficeSchemeHandler: NSObject, WKURLSchemeHandler {

    // MARK: - Bundle root

    // Optional — nil if OfficeBundle was not copied into the .app bundle (returns 503 for every request instead of crashing).
    private let bundleURL: URL? = Bundle.main.url(forResource: "OfficeBundle", withExtension: nil)

    // MARK: - Temporary image store (office://host/img/<uuid>)
    // Keys are the path component after "img/" — e.g. "img/abc-123.jpg".
    // Cleared when the scheme handler is released (editor closed).
    // Lock protects against storeImage being called off the main thread.
    private static let _lock = NSLock()
    private static var _images: [String: (data: Data, mime: String)] = [:]

    /// Store `data` and return an `office://host/img/<uuid>.<ext>` URL the JS
    /// layer can pass directly to `asc_insertImageFromUrl` without base64 encoding.
    static func storeImage(data: Data, mimeType: String) -> String {
        let ext  = mimeType == "image/png" ? "png" : "jpg"
        let uuid = UUID().uuidString.lowercased()
        let key  = "\(uuid).\(ext)"
        _lock.lock(); _images[key] = (data, mimeType); _lock.unlock()
        return "office://host/img/\(key)"
    }

    // MARK: - Active tasks
    // WKURLSchemeHandler callbacks are always on the main thread (documented by Apple),
    // so no additional synchronisation is needed for activeTasks.

    private var activeTasks: Set<ObjectIdentifier> = []
    private let ioQueue = DispatchQueue(label: "com.wordoffice.OfficeSchemeHandler.io", qos: .userInitiated)

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let taskId = ObjectIdentifier(urlSchemeTask)
        activeTasks.insert(taskId)

        guard let requestURL = urlSchemeTask.request.url else {
            activeTasks.remove(taskId)
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let url = requestURL

        // ── Temporary images (office://host/img/<uuid>.<ext>) ────────────────────
        var rawPath = url.path
        if rawPath.hasPrefix("/") { rawPath = String(rawPath.dropFirst()) }

        if rawPath.hasPrefix("img/") {
            let key = String(rawPath.dropFirst(4))
            Self._lock.lock()
            let entry = Self._images[key]
            Self._lock.unlock()
            if let (data, mime) = entry {
                respond(to: urlSchemeTask, url: url, status: 200, mimeType: mime, data: data)
            } else {
                respond(to: urlSchemeTask, url: url, status: 404, body: "Image not found: \(key)")
            }
            activeTasks.remove(taskId)
            return
        }

        guard let bundleURL else {
            respond(to: urlSchemeTask, url: url, status: 503, body: "OfficeBundle missing from app bundle")
            activeTasks.remove(taskId)
            return
        }

        // Strip `office://host` prefix → relative file path
        let path = rawPath
        let fileURL = bundleURL.appendingPathComponent(path)
        let mime = mimeType(for: fileURL.pathExtension)

        // Read on a background queue — x2t.wasm is 63 MB and would block the
        // main thread long enough to trigger a watchdog warning if read inline.
        ioQueue.async { [weak self] in
            let data = try? Data(contentsOf: fileURL)
            DispatchQueue.main.async {
                guard let self, self.activeTasks.contains(taskId) else { return }
                if let data {
                    self.respond(to: urlSchemeTask, url: url, status: 200, mimeType: mime, data: data)
                } else {
                    self.respond(to: urlSchemeTask, url: url, status: 404, body: "Not found: \(path)")
                }
                self.activeTasks.remove(taskId)
            }
        }
    }

    // MARK: - Response helpers

    private func respond(
        to task: any WKURLSchemeTask,
        url: URL,
        status: Int,
        mimeType: String = "text/plain; charset=utf-8",
        data: Data
    ) {
        var headers: [String: String] = [
            "Content-Type": mimeType,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*",
        ]
        if status == 200 { headers["Cache-Control"] = "public, max-age=86400" }
        guard let response = HTTPURLResponse(
            url: url, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: headers
        ) else { return }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func respond(to task: any WKURLSchemeTask, url: URL, status: Int, body: String) {
        respond(to: task, url: url, status: status,
                data: (body.data(using: .utf8) ?? Data()))
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
