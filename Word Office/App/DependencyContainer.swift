import Foundation

// MARK: - Compile-time SDK swap (C3)
// Debug-Mock build config sets SWIFT_ACTIVE_COMPILATION_CONDITIONS += USE_MOCK_SDK.
// When Artifex license lands, switch to Debug-Real (no USE_MOCK_SDK flag) → Real impls compile in.

@MainActor
final class DependencyContainer {
    // MARK: - Core services (stored — safe to init eagerly)

    let localFileService: LocalFileServiceImpl
    let autosaveScheduler: AutosaveScheduler

    // MARK: - Library services (Sprint 0.2 group A — Library core loop)

    let folderPermissionPicker: FolderPermissionPicker
    let folderBookmarkStore: FolderBookmarkStore
    let documentLibraryScanner: DocumentLibraryScanner
    let metadataStore: MetadataStoreImpl
    let remindScheduler: RemindScheduler

    // MARK: - Import services (Sprint 0.2 group B — secondary Add-file flow)

    let iCloudImporter: ICloudPlaceholderImporter
    let documentImporter: DocumentImporter

    // MARK: - Crash recovery (Sprint 0.2 group B — autosave backstop)

    let crashRecoveryScanner: CrashRecoveryScanner

    // MARK: - PDF power tools + OCR + print (Sprint 0.3 — native, no SDK/SPM dependency)

    let pdfMerger: PDFKitMerger
    let pdfSplitter: PDFKitSplitter
    let textRecognizer: VisionTextRecognizer
    let documentPrinter: AirPrintCoordinator

    // MARK: - Convert (§7.4, 2026-09-01 — Office↔PDF, Image↔PDF)

    let documentExporter: MockArtifexDocumentExporter
    let pdfTextExtractor: PDFKitTextExtractor
    let pdfImageExporter: PDFKitImageExporter
    let imagePDFExporter: UIGraphicsImagePDFExporter
    let searchablePDFRenderer: CGSearchablePDFRenderer

    init() {
        let docsURL = URL.documentsDirectory
        self.localFileService = LocalFileServiceImpl(documentsURL: docsURL)
        self.autosaveScheduler = AutosaveScheduler()

        self.folderPermissionPicker = FolderPermissionPicker()
        self.folderBookmarkStore = FolderBookmarkStore()
        self.documentLibraryScanner = DocumentLibraryScanner()

        // Metadata DB open failure is fatal — no useful fallback for MVP,
        // app cannot serve the core loop without the metadata table.
        // FIXME(A6): resolveDatabaseURL falls back to Application Support until
        // the App Group entitlement is provisioned — see MetadataStoreLocator.
        do {
            let databaseURL = try MetadataStoreLocator.resolveDatabaseURL()
            self.metadataStore = try MetadataStoreImpl(databaseURL: databaseURL)
        } catch {
            preconditionFailure("Metadata store init failed: \(error)")
        }
        self.remindScheduler = RemindScheduler(metadata: metadataStore)

        self.iCloudImporter = ICloudPlaceholderImporter()
        self.documentImporter = DocumentImporter(
            documentsURL: docsURL,
            iCloudImporter: iCloudImporter
        )

        self.crashRecoveryScanner = CrashRecoveryScanner(documentsURL: docsURL)

        self.pdfMerger = PDFKitMerger()
        self.pdfSplitter = PDFKitSplitter()
        self.textRecognizer = VisionTextRecognizer()
        self.documentPrinter = AirPrintCoordinator()

        self.documentExporter = MockArtifexDocumentExporter()
        self.pdfTextExtractor = PDFKitTextExtractor(recognizer: textRecognizer)
        self.pdfImageExporter = PDFKitImageExporter()
        self.imagePDFExporter = UIGraphicsImagePDFExporter()
        self.searchablePDFRenderer = CGSearchablePDFRenderer()
    }

    // MARK: - Document session (SDK-backed)

    func makeDocumentSessionManager() -> any DocumentSessionManaging {
        #if USE_MOCK_SDK
        MockArtifexDocumentSessionManager()
        #else
        // TODO Sprint 0.2: return ArtifexDocumentSessionManager(licenseKey: ...)
        MockArtifexDocumentSessionManager()
        #endif
    }

    func makeDocumentReader(for kind: DocumentKind) -> any DocumentReading {
        #if USE_MOCK_SDK
        MockArtifexDocumentReader(kind: kind)
        #else
        // TODO Sprint 0.2
        MockArtifexDocumentReader(kind: kind)
        #endif
    }

    func makeDocumentWriter(for kind: DocumentKind) -> any DocumentWriting {
        #if USE_MOCK_SDK
        MockArtifexDocumentWriter(kind: kind)
        #else
        // TODO Sprint 0.2
        MockArtifexDocumentWriter(kind: kind)
        #endif
    }

    // MARK: - ViewModel factories

    func makeDocumentListViewModel() -> DocumentListViewModel {
        DocumentListViewModel(
            lister: localFileService,
            creator: localFileService
        )
    }

    func makeEditorViewModel(for ref: DocumentRef) -> EditorViewModel {
        EditorViewModel(
            ref: ref,
            reader: makeDocumentReader(for: ref.kind),
            writer: makeDocumentWriter(for: ref.kind),
            autosave: autosaveScheduler
        )
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel()
    }

    // MARK: - PDF Tools + OCR ViewModel factories (Sprint 0.3 — native, no SDK dependency)

    func makePDFToolsViewModel() -> PDFToolsViewModel {
        PDFToolsViewModel(
            merger: pdfMerger,
            splitter: pdfSplitter,
            printer: documentPrinter,
            exporter: documentExporter,
            textExtractor: pdfTextExtractor,
            imageExporter: pdfImageExporter,
            pdfFromImages: imagePDFExporter,
            documentsURL: localFileService.documentsURL,
            recognitionLanguages: Self.defaultRecognitionLanguages()
        )
    }

    func makeOCRViewModel() -> OCRViewModel {
        OCRViewModel(
            recognizer: textRecognizer,
            searchablePDFRenderer: searchablePDFRenderer,
            recognitionLanguages: Self.defaultRecognitionLanguages()
        )
    }

    /// System language(s) first, English guaranteed as a fallback — never
    /// hardcode English alone (§6.3). `Locale.preferredLanguages` already
    /// yields well-formed BCP-47 tags (e.g. "vi-VN") that Vision accepts as-is.
    private static func defaultRecognitionLanguages() -> [String] {
        var languages = Locale.preferredLanguages
        if !languages.contains(where: { $0.hasPrefix("en") }) {
            languages.append("en-US")
        }
        return languages
    }

    // MARK: - Library ViewModel factories (take LibraryStore as param — store lives at app scope)

    func makeLibraryViewModel(store: LibraryStore) -> LibraryViewModel {
        LibraryViewModel(
            store: store,
            bookmarkStore: folderBookmarkStore,
            scanner: documentLibraryScanner,
            metadataStore: metadataStore,
            reminders: remindScheduler,
            importer: documentImporter,
            documentCreator: localFileService,
            documentsURL: localFileService.documentsURL
        )
    }

    func makeFolderPermissionViewModel(store: LibraryStore) -> FolderPermissionViewModel {
        FolderPermissionViewModel(
            store: store,
            picker: folderPermissionPicker,
            bookmarkStore: folderBookmarkStore
        )
    }
}
