import SwiftUI

struct FilesTabView: View {
    let container: DependencyContainer
    @State private var listVM: DocumentListViewModel

    init(container: DependencyContainer) {
        self.container = container
        self._listVM = State(initialValue: container.makeDocumentListViewModel())
    }

    var body: some View {
        NavigationStack {
            DocumentListView(viewModel: listVM, selection: .constant(nil))
                .navigationTitle("Files")
                .navigationDestination(for: DocumentRef.self) { ref in
                    EditorPlaceholderView(container: container, ref: ref)
                }
        }
    }
}

#Preview {
    FilesTabView(container: DependencyContainer())
}
