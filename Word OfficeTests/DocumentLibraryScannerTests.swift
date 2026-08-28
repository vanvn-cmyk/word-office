import Foundation
import Testing
@testable import Word_Office

/// Unit tests for `DocumentLibraryScanner`. Uses a per-test temp folder with real
/// fixture files so UTI detection and filesystem attribute reads exercise the
/// same code paths as production. Temp folders leak (Swift Testing structs have
/// no reliable teardown hook) — the OS sweeps `/tmp` on its own schedule.
@Suite("DocumentLibraryScanner")
struct DocumentLibraryScannerTests {
    let scanner: DocumentLibraryScanner
    let tempFolder: URL

    init() throws {
        self.scanner = DocumentLibraryScanner()
        self.tempFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("wordoffice-scanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempFolder,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Filtering

    @Test("Returns only supported document kinds")
    func filtersOnlySupportedKinds() async throws {
        try makeFile("contract.pdf",  content: "%PDF-1.4")
        try makeFile("notes.txt",     content: "plain text")
        try makeFile("readme.md",     content: "# heading")
        try makeFile("styled.rtf",    content: "{\\rtf1 hello}")
        try makeFile("image.jpg",     content: "not a real jpg")
        try makeFile("data.foo",      content: "unknown extension")

        let entries = await scanner.scan(folder: tempFolder)
        let kinds = Set(entries.map(\.document.kind))

        #expect(kinds.isSuperset(of: [.pdf, .txt, .markdown, .rtf]))
        #expect(!kinds.contains(where: { $0 == .docx || $0 == .xlsx })) // no docx fixture here
        #expect(entries.count == 4)
    }

    @Test("Extracts kind from file UTI")
    func extractsCorrectKind() async throws {
        try makeFile("contract.pdf", content: "%PDF")
        try makeFile("notes.txt",    content: "hi")

        let entries = await scanner.scan(folder: tempFolder)
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.document.name, $0.document.kind) })

        #expect(byName["contract.pdf"] == .pdf)
        #expect(byName["notes.txt"] == .txt)
    }

    @Test("Skips hidden files")
    func skipsHiddenFiles() async throws {
        try makeFile(".DS_Store",     content: "hidden")
        try makeFile(".hidden.pdf",   content: "%PDF")
        try makeFile("visible.pdf",   content: "%PDF")

        let entries = await scanner.scan(folder: tempFolder)

        #expect(entries.count == 1)
        #expect(entries.first?.document.name == "visible.pdf")
    }

    @Test("Skips subdirectories")
    func skipsSubdirectories() async throws {
        let subfolder = tempFolder.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try makeFile("root.pdf",         content: "%PDF")
        try makeFile("nested/inner.pdf", content: "%PDF")

        let entries = await scanner.scan(folder: tempFolder)

        #expect(entries.count == 1)
        #expect(entries.first?.document.name == "root.pdf")
    }

    @Test("Returns empty for nonexistent folder")
    func returnsEmptyForNonexistentFolder() async {
        let bogus = tempFolder.appendingPathComponent("does-not-exist-\(UUID())")
        let entries = await scanner.scan(folder: bogus)

        #expect(entries.isEmpty)
    }

    // MARK: - Metadata mapping

    @Test("modifiedAt matches file contentModificationDate")
    func setsModifiedAtFromFile() async throws {
        try makeFile("aged.pdf", content: "%PDF")
        let fileURL = tempFolder.appendingPathComponent("aged.pdf")
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: fixedDate],
            ofItemAtPath: fileURL.path
        )

        let entries = await scanner.scan(folder: tempFolder)
        let aged = try #require(entries.first { $0.document.name == "aged.pdf" })

        // Filesystem timestamps can carry sub-second drift; 1s tolerance is safe.
        #expect(abs(aged.document.modifiedAt.timeIntervalSince(fixedDate)) < 1)
    }

    @Test("Reports .local downloadState for non-iCloud files")
    func returnsLocalDownloadState() async throws {
        try makeFile("plain.pdf", content: "%PDF")

        let entries = await scanner.scan(folder: tempFolder)
        let entry = try #require(entries.first)

        #expect(entry.downloadState == .local)
    }

    // MARK: - Fixtures

    private func makeFile(_ relativePath: String, content: String) throws {
        let url = tempFolder.appendingPathComponent(relativePath)
        try Data(content.utf8).write(to: url)
    }
}
