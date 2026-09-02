import Foundation

// MARK: - UC16 view helpers (first-scan familiarity)
//
// Pure computed views on top of `store` state — no mutation, no service calls,
// safe from view render passes. Kept out of `LibraryViewModel.swift` so the main
// file stays focused on load / mutate.
//
// See `TuHoSo-Flow-Review.md` §5 UC16.

extension LibraryViewModel {
    /// Adaptive hero copy computed from current store state.
    var heroCopy: LibraryHeroCopy {
        let total = store.entries.count
        let drafts = store.draftCount
        if total == 0 { return .empty }
        if drafts == 0 { return .celebration(total: total) }
        if drafts == total { return .welcoming(total: total) }
        return .zeigarnik(draft: drafts, total: total)
    }

    /// Entries with `remindAt <= now`, sorted by remindAt ascending (soonest first).
    /// Rendered as the "Needs attention" section on top of `LibraryView`.
    /// Reads `filteredEntries` (not `store.entries`) so the active type/status
    /// filter narrows the set before due-sorting runs — see `+Filtering`.
    func dueReminderEntries(now: Date = .now) -> [LibraryEntry] {
        filteredEntries
            .filter { entry in
                guard let remindAt = entry.metadata.remindAt else { return false }
                return remindAt <= now
            }
            .sorted { lhs, rhs in
                (lhs.metadata.remindAt ?? .distantFuture) < (rhs.metadata.remindAt ?? .distantFuture)
            }
    }

    /// Non-due entries (from `filteredEntries`) grouped by `DateBucket`, sorted by
    /// `modifiedAt` descending inside each bucket. Empty buckets are dropped —
    /// view iterates only what it renders.
    func groupedEntries(now: Date = .now) -> [(bucket: DateBucket, entries: [LibraryEntry])] {
        let dueIDs = Set(dueReminderEntries(now: now).map(\.id))
        let nonDue = filteredEntries
            .filter { !dueIDs.contains($0.id) }
            .sorted { $0.document.modifiedAt > $1.document.modifiedAt }

        let grouped = Dictionary(grouping: nonDue) { entry in
            DateBucket.bucket(for: entry.document.modifiedAt, now: now)
        }

        return DateBucket.allCases.compactMap { bucket in
            guard let entries = grouped[bucket], !entries.isEmpty else { return nil }
            return (bucket, entries)
        }
    }
}
