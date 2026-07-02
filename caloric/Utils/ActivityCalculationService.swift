//
//  ActivityCalculationService.swift
//  caloric
//
//  Converts raw HealthKit data into net NEAT and EAT calories.
//  All results are *net* — the resting BMR share for the same window is
//  subtracted to prevent double-counting against the base BMR ring.
//
//  NEAT math lives in NEATModel.swift (NEATCalculator/NEATInputs).
//  This service stays SYNCHRONOUS so it can be used from SwiftUI computed
//  properties. It maps the already-fetched HealthKit aggregates into NEATInputs.
//

import Foundation
import HealthKit

struct ActivityCalculationService {

    // MARK: - Output

    struct ActivityResult {
        let neatKcal: Double
        let eatKcal: Double
        var totalActiveKcal: Double { neatKcal + eatKcal }
    }

    // MARK: - EAT (Exercise Activity Thermogenesis)

    /// Net active calories from a single workout using the Hiilloskorpi HRR formula.
    /// Hiilloskorpi already measures net expenditure above rest — no extra BMR subtraction.
    /// VO2max fallback: 45 mL/kg·min (male) / 40 mL/kg·min (female).
    static func eat(
        workout: HKWorkoutSnapshot,
        weightKg: Double,
        vo2Max: Double?,
        hrRest: Double?,
        age: Int,
        isMale: Bool
    ) -> Double {
        guard let avgHR = workout.averageHeartRate,
              avgHR > 0, weightKg > 0 else { return 0 }

        let minutes = workout.duration / 60.0
        guard minutes > 0 else { return 0 }

        let vo2   = (vo2Max ?? 0) > 0 ? vo2Max! : (isMale ? 45.0 : 40.0)
        let hrRst = (hrRest ?? 0) > 0 ? hrRest! : 60.0
        let hrMax = 208.0 - 0.7 * Double(age)          // Tanaka — aligned with NEAT
        let hrr   = (avgHR - hrRst) / max(1, hrMax - hrRst)

        let kJperMin: Double = isMale
            ? weightKg * vo2 * (0.019  * hrr - 0.0043)
            : weightKg * vo2 * (0.0143 * hrr - 0.0038)
        var bruttoKcal = (kJperMin / 4.184) * minutes

        // EPOC — strength: fixed ×1.20. Others: linear 0–20 % between 60 % and 85 % HR_max.
        let isStrength = workout.activityType == .functionalStrengthTraining ||
                         workout.activityType == .traditionalStrengthTraining
        if isStrength {
            bruttoKcal *= 1.20
        } else {
            let intensity = hrMax > 0 ? avgHR / hrMax : 0
            if intensity >= 0.85 {
                bruttoKcal *= 1.20
            } else if intensity > 0.60 {
                bruttoKcal *= 1.0 + (intensity - 0.60) / (0.85 - 0.60) * 0.20
            }
        }

        return max(0, bruttoKcal)
    }

    // MARK: - Combined (synchronous)

    /// Same signature as before + an optional `referenceDate`.
    /// Pass the day you're computing (defaults to today) so past days use the
    /// full 24h window instead of clamping to the current clock time.
    static func calculate(
        steps: Int,
        standTimeMinutes: Double,
        restingHR: Double?,
        avgHRWaking: Double?,
        vo2Max: Double?,
        workouts: [HKWorkoutSnapshot],
        weightKg: Double,
        age: Int,
        isMale: Bool,
        sleepHours: Double,
        bmrDynamisch: Double,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ActivityResult {

        let workoutSeconds = workouts.reduce(0.0) { $0 + $1.duration }
        let workoutMin     = workoutSeconds / 60.0

        // Stand minutes inside workouts belong to EAT, not NEAT.
        let netStandMin = max(0, standTimeMinutes - workoutMin)

        // Wake / day-end window (minutes of day).
        let isToday   = calendar.isDateInToday(referenceDate)
        let dayStart  = calendar.startOfDay(for: referenceDate)
        let dayEndMin = isToday ? referenceDate.timeIntervalSince(dayStart) / 60.0 : 1440.0
        let wakeMin   = (sleepHours > 0 ? sleepHours : 8.0) * 60.0

        let inputs = NEATInputs(
            nonWorkoutSteps: steps,        // aggregate steps; see note below
            standTimeMinutes: netStandMin,
            restingHR: restingHR,
            gapAvgHR: avgHRWaking,         // clamp [rest+2, rest+25] isolates the sedentary pulse
            workoutSeconds: workoutSeconds,
            wakeMinuteOfDay: wakeMin,
            dayEndMinuteOfDay: max(wakeMin, dayEndMin),
            age: age, isMale: isMale, weightKg: weightKg,
            bmrDynamisch: bmrDynamisch
        )

        let neatKcal = NEATCalculator.neat(inputs)
        let eatKcal  = workouts.reduce(0.0) { sum, w in
            sum + eat(workout: w, weightKg: weightKg, vo2Max: vo2Max,
                      hrRest: restingHR, age: age, isMale: isMale)
        }
        return ActivityResult(neatKcal: neatKcal, eatKcal: eatKcal)
    }
}

