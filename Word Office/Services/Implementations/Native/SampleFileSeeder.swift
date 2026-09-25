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
        SampleFile(bundleName: "Sample Document",     ext: "docx"),
        SampleFile(bundleName: "Sample Spreadsheet",  ext: "xlsx"),
        SampleFile(bundleName: "Sample Presentation", ext: "pptx"),
    ]

    /// Initial status for sample files — all `.getStarted` so they appear
    /// together in a dedicated "Get Started" section, separate from the
    /// user's real working documents.
    static let sampleFileStatuses: [String: DocumentStatus] = [
        "Sample Document.docx":     .getStarted,
        "Sample Spreadsheet.xlsx":  .getStarted,
        "Sample Presentation.pptx": .getStarted,
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
    /// The "did seed" flag is set only when at least one file was
    /// actually accessible in the bundle — either copied or already
    /// present at the destination. This lets the seeder retry on the
    /// next launch if all bundle URLs were unavailable (e.g. a build
    /// that shipped without the SampleFiles resources), rather than
    /// silently marking itself done with an empty Documents/.
    func seedIfNeeded(to destinationDirectory: URL) {
        guard !defaults.bool(forKey: Self.didSeedDefaultsKey) else { return }

        // Ensure destination exists — `URL.documentsDirectory` is created
        // by iOS on first access, but this is defensive.
        if !fileManager.fileExists(atPath: destinationDirectory.path) {
            try? fileManager.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
        }

        var accessibleCount = 0
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
            if fileManager.fileExists(atPath: destinationURL.path) {
                accessibleCount += 1
                continue
            }
            if (try? fileManager.copyItem(at: sourceURL, to: destinationURL)) != nil {
                accessibleCount += 1
            }
        }

        // Only mark seeding done when at least 1 file reached Documents/.
        // If accessibleCount == 0 (all bundle URLs missing), leave the flag
        // unset so the next launch retries.
        if accessibleCount > 0 {
            defaults.set(true, forKey: Self.didSeedDefaultsKey)
        }
    }
}
