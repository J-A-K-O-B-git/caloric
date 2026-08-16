//
//  DayNarrativeStore.swift
//  caloric
//
//  Caches the generated day comparisons in UserDefaults, pruned to the last 30
//  days like JournalStore.
//
//  Keyed by date alone. An earlier version also matched a fingerprint of the
//  numbers and threw the text away as soon as they moved — right for a card
//  that regenerated itself for free, wrong here: this text is only written
//  when someone asks for it, and re-billing a generation because the day
//  ticked on another 40 kcal is exactly what the button exists to avoid.
//  Asking for a fresh one is a tap away in the sheet.
//
//  Deliberately not a SwiftData model: a handful of strings per day does not
//  justify a schema version and a migration stage.
//

import Foundation

@Observable
@MainActor
final class DayNarrativeStore {

    struct Entry: Codable, Equatable {
        let paragraphs: [String]
        let createdAt: Date
    }

    private static let storageKey = "dayNarrativeStore.entries.v2"
    private static let retentionDays = 30

    private var entries: [String: Entry] = [:]

    init() {
        load()
    }

    func deepDive(for dateKey: String) -> DayNarrativeService.DeepDive? {
        guard let entry = entries[dateKey], !entry.paragraphs.isEmpty else { return nil }
        return DayNarrativeService.DeepDive(paragraphs: entry.paragraphs)
    }

    func store(_ deepDive: DayNarrativeService.DeepDive, for dateKey: String) {
        entries[dateKey] = Entry(paragraphs: deepDive.paragraphs, createdAt: Date())
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
