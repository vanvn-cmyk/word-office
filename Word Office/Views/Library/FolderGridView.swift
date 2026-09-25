import SwiftUI

// MARK: - Sort order

enum FolderSortOrder: String, CaseIterable, Identifiable {
    case nameAsc  = "Name (A → Z)"
    case nameDesc = "Name (Z → A)"
    case newest   = "Newest first"
    case oldest   = "Oldest first"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .nameAsc:  "a.circle"
        case .nameDesc: "z.circle"
        case .newest:   "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .oldest:   "clock"
        }
    }

    var shortLabel: String {
        switch self {
        case .nameAsc:  "A→Z"
        case .nameDesc: "Z→A"
        case .newest:   "Newest"
        case .oldest:   "Oldest"
        }
    }
}

// MARK: - FolderGridView

/// Folders tab inside Library — grid of user folders, search + sort bar at top.
/// Tapping a folder card calls `onSelectFolder` → LibraryView switches to Files tab
/// and filters to that folder's contents.
// Generic over `Header` so callers avoid `AnyView` type-erasure.
// `AnyView` prevents SwiftUI from diffing the header subtree — it gets
// torn down and rebuilt on every parent body pass. A concrete type lets
// SwiftUI keep stable identity and only re-render changed parts.
struct FolderGridView<Header: View>: View {
    @Bindable var folderManager: FolderManager
    @Binding var searchText: String
    @Binding var sortOrder: FolderSortOrder
    var onSelectFolder: (UUID) -> Void
    var header: Header

    @State private var showNewFolder = false
    @State private var editingFolder: AppFolder? = nil

    init(
        folderManager: FolderManager,
        searchText: Binding<String>,
        sortOrder: Binding<FolderSortOrder>,
        onSelectFolder: @escaping (UUID) -> Void,
        @ViewBuilder header: () -> Header
    ) {
        _folderManager = Bindable(folderManager)
        _searchText = searchText
        _sortOrder = sortOrder
        self.onSelectFolder = onSelectFolder
        self.header = header()
    }

    // 2 balanced columns; adaptive on wider screens (iPad)
    private let columns = [
        GridItem(.flexible(), spacing: DSSpacing.md),
        GridItem(.flexible(), spacing: DSSpacing.md),
    ]

    private var displayedFolders: [AppFolder] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty
            ? folderManager.folders
            : folderManager.folders.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return switch sortOrder {
        case .nameAsc:  filtered.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .nameDesc: filtered.sorted { $0.name.localizedCompare($1.name) == .orderedDescending }
        case .newest:   filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:   filtered.sorted { $0.createdAt < $1.createdAt }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Scrollable header injected from LibraryView (banner + tabs + sort row).
                header

                // ── Folder grid ──
                LazyVGrid(columns: columns, spacing: DSSpacing.md) {
                    // "New Folder" creation card — hidden during search
                    if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button {
                            showNewFolder = true
                        } label: {
                            NewFolderCard()
                        }
                        .buttonStyle(PressablePlainStyle())
                    }

                    // Existing folders
                    ForEach(displayedFolders) { folder in
                        FolderCard(
                            folder: folder,
                            fileCount: folderManager.fileCount(for: folder.id),
                            onTap: { onSelectFolder(folder.id) },
                            onEdit: { editingFolder = folder },
                            onDelete: { folderManager.delete(id: folder.id) }
                        )
                    }
                }
                .padding(.horizontal, DSSpacing.lg)

                // Empty states
                if !searchText.isEmpty && displayedFolders.isEmpty {
                    // Search yielded no results
                    VStack(spacing: DSSpacing.sm) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 40, weight: .regular))
                            .foregroundStyle(Color.dsTextTertiary)
                        Text("No folders match \u{201C}\(searchText)\u{201D}")
                            .font(DSFont.subheadline)
                            .foregroundStyle(Color.dsTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, DSSpacing.xxl)
                } else if searchText.isEmpty && displayedFolders.isEmpty {
                    // No folders created yet — nudge below the New Folder card
                    Text("Create folders to keep your documents organised")
                        .font(DSFont.subheadline)
                        .foregroundStyle(Color.dsTextTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DSSpacing.xl)
                        .padding(.top, DSSpacing.lg)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Bottom spacer — clears tab bar
                Color.clear.frame(height: DSTabBarMetrics.listContentTrailingSpacer)
            }
        }
        .autoHidesTabBarOnScroll()
        .background(Color(UIColor.systemGroupedBackground))
        // New folder sheet (replaces system alert — ensures keyboard focus + disabled Create)
        .sheet(isPresented: $showNewFolder) {
            NewFolderInputSheet { name in
                folderManager.addFolder(name: name, colorIndex: 0)
            }
            .presentationDetents([.height(160)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(DSRadius.large)
            .presentationBackground(Color.dsBackgroundPrimary)
        }
        // Rename / re-color sheet
        .sheet(item: $editingFolder) { folder in
            FolderEditSheet(folder: folder, folderManager: folderManager)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(DSRadius.large)
                .presentationBackground(Color.dsBackgroundPrimary)
        }
    }

}

// MARK: - NewFolderCard

private struct NewFolderCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(Color.dsBrandPrimary.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.dsBrandPrimary)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("New Folder")
                    .font(DSFont.subheadline.weight(.medium))
                    .foregroundStyle(Color.dsBrandPrimary)
                Text(" ")
                    .font(DSFont.caption)
                    .foregroundStyle(Color.clear)
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.dsBrandPrimary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .stroke(
                    Color.dsBrandPrimary.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
    }
}

// MARK: - FolderCard

private struct FolderCard: View {
    let folder: AppFolder
    let fileCount: Int
    var onTap: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(alignment: .top) {
                    // Folder icon with tint chip
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(folder.color.opacity(0.12))
                            .frame(width: 48, height: 48)
                        Image(systemName: "folder.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(folder.color)
                    }
                    Spacer(minLength: 0)
                    // Visible ··· menu
                    Menu {
                        Button("Rename") { onEdit() }
                        Divider()
                        Button("Delete Folder", role: .destructive) { onDelete() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.dsTextTertiary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(DSFont.subheadline.weight(.semibold))
                        .foregroundStyle(Color.dsTextPrimary)
                        .lineLimit(1)
                    Text("\(fileCount) \(fileCount == 1 ? "file" : "files")")
                        .font(DSFont.caption)
                        .foregroundStyle(Color.dsTextSecondary)
                }
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.dsBackgroundElevated,
                in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                    .strokeBorder(Color.dsBorderSubtle)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
        .buttonStyle(PressablePlainStyle())
    }
}

// MARK: - FolderEditSheet

private struct FolderEditSheet: View {
    let folder: AppFolder
    var folderManager: FolderManager

    @State private var name: String
    @State private var colorIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(folder: AppFolder, folderManager: FolderManager) {
        self.folder = folder
        self.folderManager = folderManager
        _name = State(initialValue: folder.name)
        _colorIndex = State(initialValue: folder.colorIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Handle + title
            Text("Edit Folder")
                .font(DSFont.headline)
                .foregroundStyle(Color.dsTextPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, DSSpacing.md)
                .padding(.bottom, DSSpacing.md)

            Divider()

            VStack(spacing: DSSpacing.md) {
                // Name field
                TextField("Folder name", text: $name)
                    .font(DSFont.body)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, 11)
                    .background(
                        Color.dsBackgroundElevated,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.dsBorderSubtle)
                    )

                // Color row
                HStack(spacing: DSSpacing.md) {
                    ForEach(AppFolder.colorPresets.indices, id: \.self) { idx in
                        Button {
                            colorIndex = idx
                        } label: {
                            Circle()
                                .fill(AppFolder.colorPresets[idx])
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            colorIndex == idx ? Color.white : Color.clear,
                                            lineWidth: 2.5
                                        )
                                )
                                .shadow(
                                    color: AppFolder.colorPresets[idx].opacity(colorIndex == idx ? 0.5 : 0.2),
                                    radius: colorIndex == idx ? 5 : 2,
                                    y: 2
                                )
                                .scaleEffect(colorIndex == idx ? 1.15 : 1.0)
                                .animation(.spring(response: 0.28, dampingFraction: 0.7), value: colorIndex)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, DSSpacing.xs)
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.top, DSSpacing.md)

            Spacer(minLength: DSSpacing.md)

            // Action buttons
            VStack(spacing: DSSpacing.sm) {
                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    folderManager.rename(id: folder.id, to: trimmed)
                    folderManager.updateColor(id: folder.id, to: colorIndex)
                    dismiss()
                } label: {
                    Text("Save Changes")
                        .font(DSFont.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.dsBrandPrimary, in: RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)

                Button("Cancel", role: .cancel) { dismiss() }
                    .font(DSFont.body)
                    .foregroundStyle(Color.dsTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.bottom, DSSpacing.md)
        }
    }
}

// MARK: - AssignFolderSheet

/// Bottom sheet for assigning a document to a folder — driven by
/// `folderAssignEntryID` in `LibraryView`.
struct AssignFolderSheet: View {
    let entryID: String
    var folderManager: FolderManager
    /// Called just before dismiss — `nil` means "No Folder" (removed), non-nil is the folder name.
    var onAssigned: ((String?) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var showNewFolder = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    assignRow(
                        label: "No Folder",
                        systemImage: "xmark.circle",
                        tintColor: Color.dsTextSecondary,
                        isSelected: folderManager.folderID(for: entryID) == nil
                    ) {
                        folderManager.assign(entryID: entryID, to: nil)
                        onAssigned?(nil)
                        dismiss()
                    }
                }

                Section("Folders") {
                    ForEach(folderManager.folders) { folder in
                        assignRow(
                            label: folder.name,
                            systemImage: "folder.fill",
                            tintColor: folder.color,
                            isSelected: folderManager.folderID(for: entryID) == folder.id
                        ) {
                            folderManager.assign(entryID: entryID, to: folder.id)
                            onAssigned?(folder.name)
                            dismiss()
                        }
                    }

                    // "New Folder" inline — lets users create a folder without
                    // leaving this sheet, even when no folders exist yet.
                    Button {
                        showNewFolder = true
                    } label: {
                        HStack(spacing: DSSpacing.md) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(Color.dsBrandPrimary)
                                .frame(width: 24)
                            Text("New Folder…")
                                .font(DSFont.body)
                                .foregroundStyle(Color.dsBrandPrimary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Add to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showNewFolder) {
                NewFolderInputSheet { name in
                    let newFolder = folderManager.addFolder(name: name, colorIndex: 0)
                    folderManager.assign(entryID: entryID, to: newFolder.id)
                    onAssigned?(newFolder.name)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
                }
                .presentationDetents([.height(160)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(DSRadius.large)
                .presentationBackground(Color.dsBackgroundPrimary)
            }
        }
    }

    @ViewBuilder
    private func assignRow(
        label: String,
        systemImage: String,
        tintColor: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(tintColor)
                    .frame(width: 24)
                Text(label)
                    .font(DSFont.body)
                    .foregroundStyle(Color.dsTextPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.dsBrandPrimary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NewFolderInputSheet

/// Minimal sheet for naming a new folder — replaces the system `.alert` approach,
/// which doesn't reliably present the keyboard and can't disable the Create button.
private struct NewFolderInputSheet: View {
    var onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("New Folder")
                .font(DSFont.headline)
                .foregroundStyle(Color.dsTextPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, DSSpacing.md)

            TextField("Folder name", text: $name)
                .focused($focused)
                .font(DSFont.body)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { if isValid { confirm() } }
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, 11)
                .background(
                    Color.dsBackgroundElevated,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.dsBorderSubtle)
                )

            HStack(spacing: DSSpacing.sm) {
                Button("Cancel") { dismiss() }
                    .font(DSFont.body)
                    .foregroundStyle(Color.dsTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        Color.dsTextSecondary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                    )
                    .buttonStyle(.plain)

                Button("Create") { confirm() }
                    .font(DSFont.body.weight(.semibold))
                    .foregroundStyle(isValid ? Color.white : Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        isValid ? Color.dsBrandPrimary : Color.dsBrandPrimary.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous)
                    )
                    .buttonStyle(.plain)
                    .disabled(!isValid)
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.bottom, DSSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true }
        }
    }

    private func confirm() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed)
        dismiss()
    }
}

// MARK: - PressablePlainStyle

/// Plain button style with a subtle scale + brightness press animation
/// — same visual language as other card buttons in the Library.
private struct PressablePlainStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
