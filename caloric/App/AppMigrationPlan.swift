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

// MARK: - V2  (current — HRSegment NEAT model)

enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    // References the production models directly — no re-definition needed.
    static var models: [any PersistentModel.Type] {
        [UserProfile.self, DailyActivityRecord.self, DayCacheEntry.self]
    }
}

// MARK: - Migration plan

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AppSchemaV1.self, AppSchemaV2.self] }
    static var stages:  [MigrationStage]           { [migrateV1toV2] }

    // Lightweight: SwiftData drops the old columns and adds neatHR (default 0.0).
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: AppSchemaV1.self,
        toVersion:   AppSchemaV2.self
    )
}
