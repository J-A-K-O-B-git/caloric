import Foundation
import SwiftData

// CHANGES v2:
// - @Attribute(.unique) on dateKey → upsert is enforced at store level.
// - Real optionals instead of "0 encodes nil" sentinels (SwiftData supports
//   Double? natively). NOTE: this is a schema change — bump your schema
//   version / test lightweight migration before shipping.

@Model
final class DailyActivityRecord {

    // MARK: - Identity
    @Attribute(.unique) var dateKey: String   // "yyyy-MM-dd" — primary key used for upsert
    var date: Date                            // start of day (midnight)

    // MARK: - Raw inputs
    var steps: Int
    var standTimeMinutes: Double
    var restingHR: Double?
    var vo2Max: Double?
    var workoutSeconds: Double
    var sleepHours: Double
    var weightKg: Double?

    // MARK: - Calculated outputs
    var bmrDynamisch: Double
    var neatSteps: Double
    var neatStand: Double
    var neatHR: Double
    var neatTotal: Double
    var eatCalories: Double

    init(
        dateKey: String,
        date: Date,
        steps: Int,
        standTimeMinutes: Double,
        restingHR: Double?,
        vo2Max: Double?,
        workoutSeconds: Double,
        sleepHours: Double,
        weightKg: Double?,
        bmrDynamisch: Double,
        neatSteps: Double,
        neatStand: Double,
        neatHR: Double,
        neatTotal: Double,
        eatCalories: Double
    ) {
        self.dateKey = dateKey
        self.date = date
        self.steps = steps
        self.standTimeMinutes = standTimeMinutes
        self.restingHR = restingHR
        self.vo2Max = vo2Max
        self.workoutSeconds = workoutSeconds
        self.sleepHours = sleepHours
        self.weightKg = weightKg
        self.bmrDynamisch = bmrDynamisch
        self.neatSteps = neatSteps
        self.neatStand = neatStand
        self.neatHR = neatHR
        self.neatTotal = neatTotal
        self.eatCalories = eatCalories
    }
}
