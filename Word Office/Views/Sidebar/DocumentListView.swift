import SwiftUI

struct DocumentListView: View {
    @Bindable var viewModel: DocumentListViewModel
    @Binding var selection: DocumentRef?

    @State private var showCreateSheet = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.documents.isEmpty {
                ProgressView().controlSize(.large)
            } else if viewModel.documents.isEmpty {
                EmptyStateView(
                    icon: "doc.badge.plus",
                    title: "No documents yet",
                    message: "Create your first document to get started."
                )
            } else {
                List(selection: $selection) {
                    ForEach(viewModel.sortedDocuments) { ref in
                        NavigationLink(value: ref) {
                            DSFileRow(ref: ref)
                        }
                        .tag(ref)
                    }
                    .onDelete { indexSet in
                        Task {
                            for index in indexSet {
                                let ref = viewModel.sortedDocuments[index]
                                await viewModel.delete(ref)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New document")
            }

            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Picker("Sort", selection: $viewModel.sortOrder) {
                        ForEach(DocumentSortOrder.allCases, id: \.self) { order in
                            Text(order.displayName).tag(order)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort options")
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $showCreateSheet) {
            CreateDocumentSheet { name, kind in
                Task { _ = await viewModel.create(name: name, kind: kind) }
            }
        }
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
}

// MARK: - Create sheet

private struct CreateDocumentSheet: View {
    let onCreate: (String, DocumentKind) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var kind: DocumentKind = .txt

    var body: some View {
        NavigationStack {
            Form {
                TextField("Document name", text: $name)
                Picker("Type", selection: $kind) {
                    ForEach([DocumentKind.txt, .rtf, .markdown], id: \.self) { k in
                        Label(k.displayName, systemImage: k.systemImage).tag(k)
                    }
                }
            }
            .navigationTitle("New Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(name.isEmpty ? "Untitled" : name, kind)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
