//
//  DayNarrativeStore.swift
//  caloric
//
//  Caches generated day narratives in UserDefaults, pruned to the last 30 days
//  like JournalStore.
//
//  Entries are keyed by date *and* by a fingerprint of the numbers they
//  describe. A day that is still running keeps changing, and a cached text
//  that no longer matches its figures would be worse than none — so the
//  fingerprint, not the date alone, decides whether a cached entry still
//  applies.
//
//  Deliberately not a SwiftData model: one short string per day does not
//  justify a schema version and a migration stage.
//

import Foundation

@Observable
@MainActor
final class DayNarrativeStore {

    struct Entry: Codable, Equatable {
        let headline: String
        let body: String
        /// Optional so entries written before insights existed still decode —
        /// a failed decode would drop every cached narrative at once.
        let insight: String?
        let fingerprint: String
        let createdAt: Date
    }

    private static let storageKey = "dayNarrativeStore.entries.v1"
    private static let retentionDays = 30

    private var entries: [String: Entry] = [:]

    init() {
        load()
    }

    /// Returns the cached narrative only if it still describes the current
    /// numbers.
    func narrative(for summary: DayDeltaSummary) -> Entry? {
        guard let entry = entries[summary.dateKey],
              entry.fingerprint == summary.fingerprint else { return nil }
        return entry
    }

    func store(_ narrative: DayNarrativeService.Narrative, for summary: DayDeltaSummary) {
        entries[summary.dateKey] = Entry(
            headline: narrative.headline,
            body: narrative.body,
            insight: narrative.insight,
            fingerprint: summary.fingerprint,
            createdAt: Date()
        )
        persist()
    }

    func clear(dateKey: String) {
        entries.removeValue(forKey: dateKey)
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return }

        let cutoff = Calendar.current.date(
            byAdding: .day, value: -Self.retentionDays,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? .distantPast

        entries = decoded.filter { dateKey, _ in
            guard let date = DateKey.date(from: dateKey) else { return false }
            return date >= cutoff
        }
    }
}
