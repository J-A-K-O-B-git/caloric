import Foundation
import SwiftData

@Model
final class DailyActivityRecord {

    // MARK: - Identity
    var dateKey: String   // "yyyy-MM-dd" — logical primary key used for upsert
    var date: Date        // start of day (midnight)

    // MARK: - Raw inputs
    var steps: Int
    var standTimeMinutes: Double
    var restingHR: Double        // 0 encodes nil
    var vo2Max: Double           // 0 encodes nil
    var workoutSeconds: Double
    var sleepHours: Double
    var weightKg: Double         // 0 encodes nil

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
        self.restingHR = restingHR ?? 0
        self.vo2Max = vo2Max ?? 0
        self.workoutSeconds = workoutSeconds
        self.sleepHours = sleepHours
        self.weightKg = weightKg ?? 0
        self.bmrDynamisch = bmrDynamisch
        self.neatSteps = neatSteps
        self.neatStand = neatStand
        self.neatHR = neatHR
        self.neatTotal = neatTotal
        self.eatCalories = eatCalories
    }
}
