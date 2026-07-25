import Foundation
import SwiftData

enum ActivityRepository {

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    static func dateKey(for date: Date) -> String {
        keyFormatter.string(from: date)
    }

    // MARK: - Upsert

    static func save(record: DailyActivityRecord, context: ModelContext) {
        upsert(record, context: context)
        try? context.save()
    }

    /// Batch upsert with a single save at the end. The per-record variant costs
    /// one store write each, which adds up fast when backfilling a full history.
    static func save(records: [DailyActivityRecord], context: ModelContext) {
        guard !records.isEmpty else { return }
        for record in records { upsert(record, context: context) }
        try? context.save()
    }

    private static func upsert(_ record: DailyActivityRecord, context: ModelContext) {
        guard let existing = fetch(key: record.dateKey, context: context) else {
            context.insert(record)
            return
        }
        existing.steps = record.steps
        existing.standTimeMinutes = record.standTimeMinutes
        existing.restingHR = record.restingHR
        existing.vo2Max = record.vo2Max
        existing.workoutSeconds = record.workoutSeconds
        existing.sleepHours = record.sleepHours
        existing.weightKg = record.weightKg
        existing.bmrDynamisch = record.bmrDynamisch
        existing.neatSteps = record.neatSteps
        existing.neatStand = record.neatStand
        existing.neatHR = record.neatHR
        existing.neatTotal = record.neatTotal
        existing.eatCalories = record.eatCalories
    }

    // MARK: - Fetch

    static func fetchLast(days: Int, context: ModelContext) -> [DailyActivityRecord] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        let descriptor = FetchDescriptor<DailyActivityRecord>(
            predicate: #Predicate { $0.date >= cutoff },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func fetchRecord(for date: Date, context: ModelContext) -> DailyActivityRecord? {
        fetch(key: dateKey(for: date), context: context)
    }

    // MARK: - Cleanup

    static func deleteOlderThan(days: Int = 90, context: ModelContext) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return }
        let descriptor = FetchDescriptor<DailyActivityRecord>(
            predicate: #Predicate { $0.date < cutoff }
        )
        if let old = try? context.fetch(descriptor) {
            old.forEach { context.delete($0) }
            try? context.save()
        }
    }

    // MARK: - Private

    private static func fetch(key: String, context: ModelContext) -> DailyActivityRecord? {
        var descriptor = FetchDescriptor<DailyActivityRecord>(
            predicate: #Predicate { $0.dateKey == key }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
