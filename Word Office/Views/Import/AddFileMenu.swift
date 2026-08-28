// Sprint 0.2 — Add File flow entry point
import SwiftUI
import UniformTypeIdentifiers

/// Menu presented from the Import button. Opens a UIDocumentPickerViewController
/// via .fileImporter modifier for Local + iCloud Drive picks.
///
/// Per Phase0-Implementation-Logic.md §5.1:
/// - `.allowsMultipleSelection` true for batch import (§5.3)
/// - Copy into sandbox (asCopy semantics via fileImporter)
/// - Per-file iCloud placeholder download handled downstream (§5.2)
struct AddFileMenu: View {
    let onFilesPicked: ([URL]) -> Void
    @State private var isPresentingPicker = false

    var body: some View {
        Button {
            isPresentingPicker = true
        } label: {
            Label("Import file", systemImage: "square.and.arrow.down")
        }
        .fileImporter(
            isPresented: $isPresentingPicker,
            allowedContentTypes: Self.supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                onFilesPicked(urls)
            case .failure:
                // User cancelled or picker error — non-fatal, ignore.
                break
            }
        }
    }

    /// UTIs matching DocumentKind (Extensions/DocumentKind+UTI.swift).
    /// Keep in sync when new formats are added.
    static let supportedTypes: [UTType] = {
        var types: [UTType] = [.rtf, .plainText, .pdf]
        if let docx = UTType("org.openxmlformats.wordprocessingml.document") { types.append(docx) }
        if let xlsx = UTType("org.openxmlformats.spreadsheetml.sheet") { types.append(xlsx) }
        if let pptx = UTType("org.openxmlformats.presentationml.presentation") { types.append(pptx) }
        if let doc  = UTType("com.microsoft.word.doc") { types.append(doc) }
        if let xls  = UTType("com.microsoft.excel.xls") { types.append(xls) }
        if let ppt  = UTType("com.microsoft.powerpoint.ppt") { types.append(ppt) }
        if let md   = UTType(filenameExtension: "md") { types.append(md) }
        return types
    }()
}
