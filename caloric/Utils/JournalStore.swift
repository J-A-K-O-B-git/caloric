//
//  JournalStore.swift
//  caloric
//
//  Per-date journal state shared between DailyJournalView and DashboardView.
//  Entries are persisted to UserDefaults and pruned to the last 30 days.
//

import Foundation

@Observable
final class JournalStore {

    typealias SickEnergyLevel = TDEECalculationService.JournalInputs.SickEnergyLevel
    typealias FeverLevel      = TDEECalculationService.JournalInputs.FeverLevel

    struct CustomDrink: Codable, Identifiable, Hashable {
        let id: UUID
        var name: String
        var caffeineMg: Int
    }

    struct DayEntry: Codable {
        var menstruationActive: Bool?            = nil
        var sickActive:         Bool             = false
        var sickEnergyLevel:    SickEnergyLevel? = nil
        var feverLevel:         FeverLevel       = .none
        var caffeineMg:         Double           = 0
        var proteinByMeal:      [String: Double] = [:]
        var carbsByMeal:        [String: Double] = [:]
        var fatByMeal:          [String: Double] = [:]
        var manualWorkouts:     [ManualWorkout]  = []
    }

    struct ManualWorkout: Codable, Identifiable, Hashable {
        let id: UUID
        var name: String
        var kcal: Double
    }

    private static let storageKey = "journalStore.entries.v1"
    private static let libraryKey = "journalStore.customDrinks.v1"
    private static let retentionDays = 30

    private var entries: [String: DayEntry] = [:]
    var customDrinks: [CustomDrink] = []

    init() {
        load()
    }

    func addCustomDrink(name: String, caffeineMg: Int) {
        let drink = CustomDrink(id: UUID(), name: name, caffeineMg: caffeineMg)
        customDrinks.append(drink)
        persist()
    }

    func removeCustomDrink(id: UUID) {
        customDrinks.removeAll { $0.id == id }
        persist()
    }

    func entry(for date: Date) -> DayEntry {
        entries[key(for: date)] ?? DayEntry()
    }

    func update(for date: Date, _ mutate: (inout DayEntry) -> Void) {
        var e = entry(for: date)
        mutate(&e)
        entries[key(for: date)] = e
        persist()
    }

    func journalInputs(for date: Date, palFactor: Double = 1.0) -> TDEECalculationService.JournalInputs {
        let e = entry(for: date)
        return .init(
            sickActive:         e.sickActive,
            sickEnergyLevel:    e.sickEnergyLevel,
            feverLevel:         e.feverLevel,
            menstruationActive: e.menstruationActive,
            caffeineMg:         e.caffeineMg,
            palFactor:          palFactor,
            proteinGramsByMeal: e.proteinByMeal,
            carbsGramsByMeal:   e.carbsByMeal,
            fatGramsByMeal:     e.fatByMeal
        )
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        if let libData = try? JSONEncoder().encode(customDrinks) {
            UserDefaults.standard.set(libData, forKey: Self.libraryKey)
        }
    }

    private func load() {
        // Load entries
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: DayEntry].self, from: data) {
            let cutoff = Calendar.current.date(
                byAdding: .day, value: -Self.retentionDays, to: Calendar.current.startOfDay(for: Date())
            ) ?? .distantPast
            entries = decoded.filter { dateKey, _ in
                guard let date = Self.keyFormatter.date(from: dateKey) else { return false }
                return date >= cutoff
            }
        }
        
        // Load custom drinks
        if let libData = UserDefaults.standard.data(forKey: Self.libraryKey),
           let decodedLib = try? JSONDecoder().decode([CustomDrink].self, from: libData) {
            customDrinks = decodedLib
        }
    }

    // MARK: - Date Key

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func key(for date: Date) -> String {
        JournalStore.keyFormatter.string(from: date)
    }
}
