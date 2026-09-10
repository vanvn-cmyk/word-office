import Foundation

/// First-launch seed of the 3 "Get Started" sample files (Word, Excel,
/// PowerPoint) into the app's own `Documents/` sandbox — the app's
/// default library folder in the auto-grant flow (see Session 19
/// "Bundle sample files" change: user opens app for the first time,
/// skips the folder-permission onboarding, and finds Word Office
/// pre-populated with three tour files they can open, edit, or use
/// as tool inputs).
///
/// Runs at most once per install. Guarded by a UserDefaults flag
/// (`hasSeededSampleFiles`) so a user who deletes the seeded files
/// doesn't get them silently reappearing on the next launch — the
/// intent is a first-run demo, not a permanent template set.
final class SampleFileSeeder {
    /// UserDefaults key. Namespaced with the `sampleFileSeeder.`
    /// prefix so it doesn't collide with any other first-run flag
    /// the app might later add.
    static let didSeedDefaultsKey = "sampleFileSeeder.hasSeededSampleFiles"

    /// The three bundle files this seeder ships. Filenames match the
    /// on-disk names in `Word Office/Resources/SampleFiles/`; the
    /// on-disk name is also what the user sees in the Library after
    /// the copy, so keeping them stable in one place makes any future
    /// re-branding a single edit.
    static let sampleFiles: [SampleFile] = [
        SampleFile(bundleName: "Get Started Word", ext: "docx"),
        SampleFile(bundleName: "Get Started Excel", ext: "xlsx"),
        SampleFile(bundleName: "Get Started PowerPoint", ext: "pptx"),
    ]

    struct SampleFile: Sendable {
        let bundleName: String
        let ext: String
        var filename: String { "\(bundleName).\(ext)" }
    }

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let bundle: Bundle

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.bundle = bundle
    }

    /// Copies the 3 bundled sample files into `destinationDirectory`
    /// on first launch. No-op on subsequent launches (guarded by the
    /// UserDefaults flag). Safe to call synchronously at app-startup;
    /// three tiny Office file copies (each <50 KB) complete
    /// well under one runloop tick.
    ///
    /// Failures are best-effort: a single file that fails to copy (or
    /// can't be found in the bundle) doesn't block the other two, and
    /// the "did seed" flag still flips true — the seeder is a
    /// convenience, not a critical path, and repeated retries after
    /// a permanent failure would just re-log the same error every
    /// launch.
    func seedIfNeeded(to destinationDirectory: URL) {
        guard !defaults.bool(forKey: Self.didSeedDefaultsKey) else { return }
        defer { defaults.set(true, forKey: Self.didSeedDefaultsKey) }

        // Ensure destination exists — `URL.documentsDirectory` is created
        // by iOS on first access, but this is defensive.
        if !fileManager.fileExists(atPath: destinationDirectory.path) {
            try? fileManager.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
        }

        for sample in Self.sampleFiles {
            guard let sourceURL = bundle.url(
                forResource: sample.bundleName,
                withExtension: sample.ext,
                subdirectory: "SampleFiles"
            ) ?? bundle.url(
                forResource: sample.bundleName,
                withExtension: sample.ext
            ) else {
                continue
            }
            let destinationURL = destinationDirectory
                .appendingPathComponent(sample.filename)
            // If a file with the same name already exists at destination
            // (edge case — the flag was cleared but the copy survived),
            // skip rather than overwrite. Users may have edited the seed;
            // the flag is the authority on "should we seed", not the
            // absence of files.
            guard !fileManager.fileExists(atPath: destinationURL.path) else { continue }
            try? fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }
}
