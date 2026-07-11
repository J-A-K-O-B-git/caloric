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
    var sedentaryAvgHR: Double   // 0 encodes nil
    var unrecordedCardioAvgHR: Double  // 0 encodes nil
    var cardioRatio: Double
    var vo2Max: Double           // 0 encodes nil
    var workoutSeconds: Double
    var sleepHours: Double
    var weightKg: Double         // 0 encodes nil

    // MARK: - Calculated outputs
    var bmrDynamisch: Double
    var neatSteps: Double
    var neatStand: Double
    var neatMicro: Double
    var neatUnrecordedCardio: Double
    var neatTotal: Double
    var eatCalories: Double

    init(
        dateKey: String,
        date: Date,
        steps: Int,
        standTimeMinutes: Double,
        restingHR: Double?,
        sedentaryAvgHR: Double?,
        unrecordedCardioAvgHR: Double?,
        cardioRatio: Double,
        vo2Max: Double?,
        workoutSeconds: Double,
        sleepHours: Double,
        weightKg: Double?,
        bmrDynamisch: Double,
        neatSteps: Double,
        neatStand: Double,
        neatMicro: Double,
        neatUnrecordedCardio: Double,
        neatTotal: Double,
        eatCalories: Double
    ) {
        self.dateKey = dateKey
        self.date = date
        self.steps = steps
        self.standTimeMinutes = standTimeMinutes
        self.restingHR = restingHR ?? 0
        self.sedentaryAvgHR = sedentaryAvgHR ?? 0
        self.unrecordedCardioAvgHR = unrecordedCardioAvgHR ?? 0
        self.cardioRatio = cardioRatio
        self.vo2Max = vo2Max ?? 0
        self.workoutSeconds = workoutSeconds
        self.sleepHours = sleepHours
        self.weightKg = weightKg ?? 0
        self.bmrDynamisch = bmrDynamisch
        self.neatSteps = neatSteps
        self.neatStand = neatStand
        self.neatMicro = neatMicro
        self.neatUnrecordedCardio = neatUnrecordedCardio
        self.neatTotal = neatTotal
        self.eatCalories = eatCalories
    }
}
