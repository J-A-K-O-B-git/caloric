//
//  DayCacheEntry.swift
//  caloric
//
//  SwiftData model that caches one day of HealthKit activity + workouts on disk.
//  Populated after every fetchHistory() call; read immediately on launch so the
//  dashboard has data before HealthKit responds.
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
    var averageHeartRate: Double   // 0 encodes nil
    var sourceName: String
    var sourceBundleID: String

    func toSnapshot() -> HKWorkoutSnapshot {
        HKWorkoutSnapshot(
            id: UUID(uuidString: id) ?? UUID(),
            activityType: HKWorkoutActivityType(rawValue: activityTypeRaw) ?? .other,
            startDate: startDate,
            endDate: endDate,
            averageHeartRate: averageHeartRate > 0 ? averageHeartRate : nil,
            sourceName: sourceName,
            sourceBundleID: sourceBundleID
        )
    }
}

// MARK: - SwiftData model

@Model
final class DayCacheEntry {
    var dateKey: String            // "yyyy-MM-dd" — used as logical primary key
    var steps: Int
    var distanceMeters: Double
    var standTimeMinutes: Double
    var restingHeartRate: Double   // 0 encodes nil
    var avgHeartRateWaking: Double // 0 encodes nil
    
    var workoutsData: Data         // JSON-encoded [CachedWorkout]
    var cachedAt: Date

    init(dateKey: String, snapshot: HealthKitImportService.DaySnapshot) {
        self.dateKey             = dateKey
        self.steps               = snapshot.activity.steps
        self.distanceMeters      = snapshot.activity.distanceMeters
        self.standTimeMinutes    = snapshot.activity.standTimeMinutes
        self.restingHeartRate    = snapshot.activity.restingHeartRate ?? 0
        self.avgHeartRateWaking  = snapshot.activity.avgHeartRateWaking ?? 0
        
        self.cachedAt            = Date()

        let items = snapshot.workouts.map { w in
            CachedWorkout(
                id: w.id.uuidString,
                activityTypeRaw: w.activityType.rawValue,
                startDate: w.startDate,
                endDate: w.endDate,
                averageHeartRate: w.averageHeartRate ?? 0,
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
                restingHeartRate: restingHeartRate > 0 ? restingHeartRate : nil,
                avgHeartRateWaking: avgHeartRateWaking > 0 ? avgHeartRateWaking : nil,
                hrSegments: []
            ),
            workouts: workouts
        )
    }
}
