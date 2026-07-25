//
//  AppMigrationPlan.swift
//  caloric
//
//  Versioned SwiftData schemas + migration plan.
//
//  V1 → V2: removes the old split-HR NEAT fields from DailyActivityRecord and
//  DayCacheEntry; adds DailyActivityRecord.neatHR (default 0.0).
//  UserProfile is identical in both versions — it survives every migration.
//
//  To add future schema changes:
//    1. Copy the CURRENT @Model classes into a new AppSchemaVN enum.
//    2. Modify the production models as needed.
//    3. Add a new lightweight (or custom) MigrationStage.
//    4. Append the new schema to AppMigrationPlan.schemas and .stages.
//

import SwiftData
import Foundation

// MARK: - V1  (pre-HRSegment NEAT model)

enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [UserProfile.self, DailyActivityRecord.self, DayCacheEntry.self]
    }

    // Old DailyActivityRecord — had sedentaryAvgHR, unrecordedCardioAvgHR,
    // cardioRatio, neatMicro, neatUnrecordedCardio instead of neatHR.
    @Model final class DailyActivityRecord {
        var dateKey:                String
        var date:                   Date
        var steps:                  Int
        var standTimeMinutes:       Double
        var restingHR:              Double
        var vo2Max:                 Double
        var workoutSeconds:         Double
        var sleepHours:             Double
        var weightKg:               Double
        var bmrDynamisch:           Double
        var neatSteps:              Double
        var neatStand:              Double
        var sedentaryAvgHR:         Double
        var unrecordedCardioAvgHR:  Double
        var cardioRatio:            Double
        var neatMicro:              Double
        var neatUnrecordedCardio:   Double
        var neatTotal:              Double
        var eatCalories:            Double

        init() {
            dateKey = ""; date = Date(); steps = 0
            standTimeMinutes = 0; restingHR = 0; vo2Max = 0
            workoutSeconds = 0; sleepHours = 0; weightKg = 0
            bmrDynamisch = 0; neatSteps = 0; neatStand = 0
            sedentaryAvgHR = 0; unrecordedCardioAvgHR = 0; cardioRatio = 0
            neatMicro = 0; neatUnrecordedCardio = 0; neatTotal = 0; eatCalories = 0
        }
    }

    // Old DayCacheEntry — had sedentaryAvgHR, unrecordedCardioAvgHR, cardioRatio.
    @Model final class DayCacheEntry {
        var dateKey:               String
        var steps:                 Int
        var distanceMeters:        Double
        var standTimeMinutes:      Double
        var restingHeartRate:      Double
        var avgHeartRateWaking:    Double
        var sedentaryAvgHR:        Double
        var unrecordedCardioAvgHR: Double
        var cardioRatio:           Double
        var workoutsData:          Data
        var cachedAt:              Date

        init() {
            dateKey = ""; steps = 0; distanceMeters = 0
            standTimeMinutes = 0; restingHeartRate = 0; avgHeartRateWaking = 0
            sedentaryAvgHR = 0; unrecordedCardioAvgHR = 0; cardioRatio = 0
            workoutsData = Data(); cachedAt = Date()
        }
    }
}

// MARK: - V2  (HRSegment NEAT model)
//
// Frozen snapshot. This enum previously pointed at the production models,
// which meant every later edit to those models silently rewrote the meaning
// of V2 and left the store without a matching migration stage. Versioned
// schemas must describe a fixed point in time — see the header for the
// procedure when adding V4.

enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [UserProfile.self, DailyActivityRecord.self, DayCacheEntry.self]
    }

    @Model final class DailyActivityRecord {
        @Attribute(.unique) var dateKey: String
        var date:               Date
        var steps:              Int
        var standTimeMinutes:   Double
        var restingHR:          Double?
        var vo2Max:             Double?
        var workoutSeconds:     Double
        var sleepHours:         Double
        var weightKg:           Double?
        var bmrDynamisch:       Double
        var neatSteps:          Double
        var neatStand:          Double
        var neatHR:             Double
        var neatTotal:          Double
        var eatCalories:        Double

        init() {
            dateKey = ""; date = Date(); steps = 0
            standTimeMinutes = 0; workoutSeconds = 0; sleepHours = 0
            bmrDynamisch = 0; neatSteps = 0; neatStand = 0; neatHR = 0
            neatTotal = 0; eatCalories = 0
        }
    }

    // Pre-dates the non-workout aggregates and the sleep-derived wake minute.
    @Model final class DayCacheEntry {
        @Attribute(.unique) var dateKey: String
        var steps:              Int
        var distanceMeters:     Double
        var standTimeMinutes:   Double
        var restingHeartRate:   Double?
        var avgHeartRateWaking: Double?
        var workoutsData:       Data
        var cachedAt:           Date

        init() {
            dateKey = ""; steps = 0; distanceMeters = 0
            standTimeMinutes = 0; workoutsData = Data(); cachedAt = Date()
        }
    }
}

// MARK: - V3  (current — non-workout aggregates + sleep-derived wake time)

enum AppSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

    // References the production models directly. Freeze this into a snapshot
    // (as V2 above) before changing any @Model, and add a V4 alongside it.
    static var models: [any PersistentModel.Type] {
        [UserProfile.self, DailyActivityRecord.self, DayCacheEntry.self]
    }
}

// MARK: - Migration plan

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppSchemaV1.self, AppSchemaV2.self, AppSchemaV3.self]
    }
    static var stages: [MigrationStage] { [migrateV1toV2, migrateV2toV3] }

    // Lightweight: SwiftData drops the old columns and adds neatHR (default 0.0).
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: AppSchemaV1.self,
        toVersion:   AppSchemaV2.self
    )

    // Lightweight: adds DayCacheEntry.nonWorkoutSteps / nonWorkoutDistanceMeters /
    // nonWorkoutStandMinutes / wakeMinuteOfDay. All optional, so existing rows
    // migrate to nil and the calculation falls back to its estimates until the
    // next HealthKit fetch refills them.
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: AppSchemaV2.self,
        toVersion:   AppSchemaV3.self
    )
}
