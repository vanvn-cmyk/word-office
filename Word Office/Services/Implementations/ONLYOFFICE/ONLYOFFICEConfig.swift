import Foundation

enum ONLYOFFICEConfig {
    /// Base URL of the Node.js proxy server (server.js, port 5178).
    ///
    /// Simulator: localhost resolves to the Mac automatically.
    /// Device: set to your Mac's WiFi IP (System Settings → Wi-Fi → Details → IP Address).
    /// Production: replace with your HTTPS server URL.
    #if targetEnvironment(simulator)
    static let serverBaseURL = URL(string: "http://localhost:5178")!
    #else
    static let serverBaseURL = URL(string: "http://192.168.1.100:5178")! // ← change to your Mac's IP
    #endif
}
