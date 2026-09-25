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
    /// Reads `filteredEntries` (not `store.entries`) so the active type/date
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

    /// Entries the user explicitly flagged "Still in progress" from the editor
    /// Done sheet. Sorted by `lastModifiedAt` descending. Rendered as the
    /// "Continue Working" section at the very top of Home — above Needs Attention
    /// and the status groups. Cleared by `recordOpen` / `setStatus`.
    func continueWorkingEntries() -> [LibraryEntry] {
        filteredEntries
            .filter { $0.metadata.isContinueWorking }
            .sorted { $0.metadata.lastModifiedAt > $1.metadata.lastModifiedAt }
    }

    /// Non-due entries (from `filteredEntries`) grouped by `DocumentStatus`
    /// (2026-09-13 — was `DateBucket`; status is now Home's primary grouping,
    /// date moved to `dateFilter` in `+Filtering`), sorted by `modifiedAt`
    /// descending inside each status. Empty sections are dropped — view
    /// iterates only what it renders. Section order follows
    /// `DocumentStatus.allCases` (Draft → Reviewed → Done), the natural
    /// lifecycle progression, not entry recency.
    /// Excludes entries already shown in `continueWorkingEntries()` so a file
    /// never appears twice on the same screen.
    func groupedByStatus(now: Date = .now) -> [(status: DocumentStatus, entries: [LibraryEntry])] {
        let dueIDs = Set(dueReminderEntries(now: now).map(\.id))
        let continueIDs = Set(continueWorkingEntries().map(\.id))
        let nonDue = filteredEntries
            .filter { !dueIDs.contains($0.id) && !continueIDs.contains($0.id) }
            .sorted { $0.document.modifiedAt > $1.document.modifiedAt }

        let grouped = Dictionary(grouping: nonDue) { entry in
            entry.metadata.status
        }

        return DocumentStatus.allCases.compactMap { status in
            guard let entries = grouped[status], !entries.isEmpty else { return nil }
            return (status, entries)
        }
    }
}
