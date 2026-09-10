import Foundation

/// Network client for the ONLYOFFICE Node.js proxy server.
/// All methods are safe to call from any Swift concurrency context.
actor ONLYOFFICEAPIClient {
    let baseURL: URL

    init(baseURL: URL = ONLYOFFICEConfig.serverBaseURL) {
        self.baseURL = baseURL
    }

    // MARK: - Upload

    /// Uploads a local file to the server and returns the session ID.
    func upload(fileAt url: URL, filename: String) async throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let fileData = try Data(contentsOf: url)

        let boundary = UUID().uuidString
        var body = Data()
        func add(_ s: String) { body.append(s.data(using: .utf8)!) }
        add("--\(boundary)\r\n")
        add("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        add("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        add("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: baseURL.appendingPathComponent("api/upload"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ONLYOFFICEError.uploadFailed
        }
        return try JSONDecoder().decode(UploadResponse.self, from: data).id
    }

    // MARK: - Status

    func isSaved(sessionId: String) async throws -> Bool {
        let (data, _) = try await URLSession.shared.data(
            from: baseURL.appendingPathComponent("api/status/\(sessionId)")
        )
        return try JSONDecoder().decode(StatusResponse.self, from: data).ready
    }

    // MARK: - Download

    /// Downloads the edited file from the server and overwrites the original.
    /// No-ops silently if the user never saved (status.ready == false).
    func downloadEdited(sessionId: String, overwriting destination: URL) async throws {
        guard try await isSaved(sessionId: sessionId) else { return }
        let (data, response) = try await URLSession.shared.data(
            from: baseURL.appendingPathComponent("api/download/\(sessionId)")
        )
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ONLYOFFICEError.downloadFailed
        }
        let accessing = destination.startAccessingSecurityScopedResource()
        defer { if accessing { destination.stopAccessingSecurityScopedResource() } }
        try data.write(to: destination, options: .atomic)
    }

    // MARK: - Private

    private struct UploadResponse: Decodable { let id: String }
    private struct StatusResponse: Decodable { let ready: Bool }
}

enum ONLYOFFICEError: LocalizedError {
    case uploadFailed, downloadFailed

    var errorDescription: String? {
        switch self {
        case .uploadFailed:   "Could not upload document to the editing server."
        case .downloadFailed: "Could not download the edited document."
        }
    }
}
