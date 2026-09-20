import Foundation

/// Type/date filtering for `LibraryView` — narrows `store.entries` *before*
/// `LibraryViewModel+Grouping` runs status grouping on top of it.
/// Kept out of `LibraryViewModel.swift` for the same reason as `+Grouping`.
extension LibraryViewModel {
    var filteredEntries: [LibraryEntry] {
        let now = Date.now
        return store.entries.filter { entry in
            typeFilter.matches(entry.document.kind)
                && (dateFilter == nil || DateBucket.bucket(for: entry.document.modifiedAt, now: now) == dateFilter)
                && (!favouritesOnly || entry.metadata.isFavourite)
        }
    }

    var isFiltering: Bool {
        typeFilter != .all || dateFilter != nil || favouritesOnly
    }

    /// Count for a type tab. Computed against the full entry set (ignoring
    /// `typeFilter` itself, but respecting `dateFilter`/`favouritesOnly`) so
    /// switching tabs doesn't change the numbers shown on the other tabs.
    func count(for filter: DocumentTypeFilter) -> Int {
        let now = Date.now
        return store.entries.count { entry in
            filter.matches(entry.document.kind)
                && (dateFilter == nil || DateBucket.bucket(for: entry.document.modifiedAt, now: now) == dateFilter)
                && (!favouritesOnly || entry.metadata.isFavourite)
        }
    }

    /// Flat, unbucketed matches for the search field — `.searchable()` intentionally
    /// bypasses due/date-bucket grouping (Library-Home-v10 mockup Frame 3: search
    /// results read as one flat list, not sections).
    var searchResults: [LibraryEntry] {
        guard !searchText.isEmpty else { return [] }
        return filteredEntries.filter {
            $0.document.name.localizedCaseInsensitiveContains(searchText)
        }
    }
}
