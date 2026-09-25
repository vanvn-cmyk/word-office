import Foundation
import SwiftUI

struct AppFolder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var colorIndex: Int = 0
    var createdAt: Date = Date()
}

// MARK: - Preset colors

extension AppFolder {
    static let colorPresets: [Color] = [
        .blue, .indigo, .purple, .pink,
        .orange, .yellow, .green, .teal,
    ]

    var color: Color { AppFolder.colorPresets[colorIndex % AppFolder.colorPresets.count] }
}

// MARK: - FolderManager

/// Persists folders + doc-to-folder assignments in UserDefaults.
/// Keyed by `LibraryEntry.id` (stable across scans).
@Observable
final class FolderManager {
    static let shared = FolderManager()

    var folders: [AppFolder] = []
    /// entryID → folderID
    var assignments: [String: UUID] = [:]

    private let foldersKey      = "app.folders.v1"
    private let assignmentsKey  = "app.folder_assignments.v1"

    init() { load() }

    // MARK: Queries

    func folderID(for entryID: String) -> UUID? { assignments[entryID] }

    func folder(for entryID: String) -> AppFolder? {
        guard let fid = folderID(for: entryID) else { return nil }
        return folders.first { $0.id == fid }
    }

    func fileCount(for folderID: UUID) -> Int {
        assignments.values.filter { $0 == folderID }.count
    }

    // MARK: Mutations

    @discardableResult
    func addFolder(name: String, colorIndex: Int = 0) -> AppFolder {
        let folder = AppFolder(name: name, colorIndex: colorIndex)
        folders.append(folder)
        save()
        return folder
    }

    func rename(id: UUID, to name: String) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[idx].name = name
        save()
    }

    func delete(id: UUID) {
        folders.removeAll { $0.id == id }
        assignments = assignments.filter { $0.value != id }
        save()
    }

    func updateColor(id: UUID, to colorIndex: Int) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[idx].colorIndex = colorIndex
        save()
    }

    func assign(entryID: String, to folderID: UUID?) {
        if let folderID { assignments[entryID] = folderID }
        else { assignments.removeValue(forKey: entryID) }
        save()
    }

    // MARK: Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: foldersKey)
        }
        if let data = try? JSONEncoder().encode(assignments) {
            UserDefaults.standard.set(data, forKey: assignmentsKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: foldersKey),
           let decoded = try? JSONDecoder().decode([AppFolder].self, from: data) {
            folders = decoded
        }
        if let data = UserDefaults.standard.data(forKey: assignmentsKey),
           let decoded = try? JSONDecoder().decode([String: UUID].self, from: data) {
            assignments = decoded
        }
    }
}
