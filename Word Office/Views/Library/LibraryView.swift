import SwiftUI

/// Library — the core-loop landing screen (Library-Architecture.md §4).
/// Renders the library once permission is granted; empty/loading/error states
/// live here so the parent shell doesn't need to know them.
/// `onChangeFolder` lets the user pick a different granted folder — the parent
/// wires it to `FolderPermissionViewModel.resetPermission`.
struct LibraryView: View {
    @Bindable var viewModel: LibraryViewModel
    @Environment(LibraryStore.self) private var store

    let onChangeFolder: () async -> Void

    var body: some View {
        Group {
            if store.folderPermissionState == .checking {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.entries.isEmpty && !viewModel.isLoading {
                EmptyStateView(
                    icon: "tray",
                    title: "No documents yet",
                    message: "The granted folder has no supported files. Add files to the folder, or pull down to rescan."
                )
            } else {
                libraryList
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Task { await viewModel.loadLibrary() }
                    } label: {
                        Label("Rescan folder", systemImage: "arrow.clockwise")
                    }
                    Button {
                        Task { await onChangeFolder() }
                    } label: {
                        Label("Change folder…", systemImage: "folder.badge.gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Folder options")
            }
        }
        .task { await viewModel.loadLibrary() }
        .refreshable { await viewModel.loadLibrary() }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            ),
            presenting: viewModel.errorMessage
        ) { _ in
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private var navigationTitle: String {
        let draft = store.draftCount
        return draft > 0 ? "Library · \(draft) draft\(draft == 1 ? "" : "s")" : "Library"
    }

    @ViewBuilder
    private var libraryList: some View {
        List {
            ForEach(store.entries) { entry in
                DocumentCard(entry: entry) {
                    Task { await viewModel.recordOpen(entry.id) }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: DSSpacing.xxs, leading: DSSpacing.md, bottom: DSSpacing.xxs, trailing: DSSpacing.md))
                .contextMenu { contextMenu(for: entry) }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func contextMenu(for entry: LibraryEntry) -> some View {
        Section("Change status") {
            ForEach(DocumentStatus.allCases) { status in
                Button {
                    Task { await viewModel.setStatus(status, for: entry.id) }
                } label: {
                    Label(status.displayName, systemImage: status.systemImage)
                }
                .disabled(status == entry.metadata.status)
            }
        }
    }
}
