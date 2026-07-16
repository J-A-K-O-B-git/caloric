//
//  DayCacheEntry.swift
//  caloric
//
//  SwiftData model that caches one day of HealthKit activity + workouts on disk.
//  Populated after every fetchHistory() call; read immediately on launch so the
//  dashboard has data before HealthKit responds.
//
//  CHANGES v2:
//  - @Attribute(.unique) on dateKey → upsert enforced at store level.
//  - Real optionals instead of "0 encodes nil" sentinels.
//    NOTE: schema change — bump schema version / test migration. Since this is
//    only a cache, wiping and refetching on migration failure is also fine.
//

import Foundation
import SwiftData
import HealthKit

// MARK: - Workout serialization helper

struct CachedWorkout: Codable {
    var id: String
    var activityTypeRaw: UInt
    var startDate: Date
    var endDate: Date
    var averageHeartRate: Double?   // JSON encodes nil natively
    var sourceName: String
    var sourceBundleID: String

    func toSnapshot() -> HKWorkoutSnapshot {
        // Legacy cache entries encoded nil as 0 — map that back to nil.
        let hr: Double? = {
            guard let v = averageHeartRate, v > 0 else { return nil }
            return v
        }()
        return HKWorkoutSnapshot(
            id: UUID(uuidString: id) ?? UUID(),
            activityType: HKWorkoutActivityType(rawValue: activityTypeRaw) ?? .other,
            startDate: startDate,
            endDate: endDate,
            averageHeartRate: hr,
            sourceName: sourceName,
            sourceBundleID: sourceBundleID
        )
    }
}

// MARK: - SwiftData model

@Model
final class DayCacheEntry {
    @Attribute(.unique) var dateKey: String   // "yyyy-MM-dd" — primary key
    var steps: Int
    var distanceMeters: Double
    var standTimeMinutes: Double
    var restingHeartRate: Double?
    var avgHeartRateWaking: Double?

    var workoutsData: Data         // JSON-encoded [CachedWorkout]
    var cachedAt: Date

    init(dateKey: String, snapshot: HealthKitImportService.DaySnapshot) {
        self.dateKey             = dateKey
        self.steps               = snapshot.activity.steps
        self.distanceMeters      = snapshot.activity.distanceMeters
        self.standTimeMinutes    = snapshot.activity.standTimeMinutes
        self.restingHeartRate    = snapshot.activity.restingHeartRate
        self.avgHeartRateWaking  = snapshot.activity.avgHeartRateWaking

        self.cachedAt            = Date()

        let items = snapshot.workouts.map { w in
            CachedWorkout(
                id: w.id.uuidString,
                activityTypeRaw: w.activityType.rawValue,
                startDate: w.startDate,
                endDate: w.endDate,
                averageHeartRate: w.averageHeartRate,
                sourceName: w.sourceName,
                sourceBundleID: w.sourceBundleID
            )
        }
        self.workoutsData = (try? JSONEncoder().encode(items)) ?? Data()
    }

    func toDaySnapshot() -> HealthKitImportService.DaySnapshot {
        let workouts = (try? JSONDecoder().decode([CachedWorkout].self, from: workoutsData))?
            .map { $0.toSnapshot() } ?? []
        return HealthKitImportService.DaySnapshot(
            activity: HKActivitySnapshot(
                steps: steps,
                distanceMeters: distanceMeters,
                fetchedAt: cachedAt,
                standTimeMinutes: standTimeMinutes,
                restingHeartRate: restingHeartRate,
                avgHeartRateWaking: avgHeartRateWaking,
                hrSegments: []
            ),
            workouts: workouts
        )
    }
}
