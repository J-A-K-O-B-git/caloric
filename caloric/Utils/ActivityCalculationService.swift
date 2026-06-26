//
//  ActivityCalculationService.swift
//  caloric
//
//  Converts raw HealthKit data into net NEAT and EAT calories.
//  All results are *net* — the resting BMR share for the same time window is
//  subtracted to prevent double-counting against the base BMR ring.
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

    // MARK: - NEAT (Non-Exercise Activity Thermogenesis)

    /// Three-component NEAT model:
    /// - Baustein 1 (Schritte): walk hours × 2.0 × (BMR/24)
    /// - Baustein 2 (Stand):    pure stand hours × 0.18 × (BMR/24)
    /// - Baustein 3 (Micro):    Keytel-scaled gap energy from continuous HR monitoring
    static func neat(
        steps: Int,
        standTimeMinutes: Double,
        restingHR: Double?,
        avgHRWaking: Double?,
        workoutSeconds: Double,
        sleepHours: Double,
        weightKg: Double,
        age: Int,
        isMale: Bool,
        bmrDynamisch: Double
    ) -> Double {
        guard bmrDynamisch > 0 else { return 0 }
        let bmrPerHour = bmrDynamisch / 24.0

        // Baustein 1 — NEAT_Schritte
        let walkMinutes = Double(steps) / 100.0   // 100 steps/min
        let walkHours   = walkMinutes / 60.0
        let neatSteps   = walkHours * 2.0 * bmrPerHour

        // Baustein 2 — NEAT_Stand (subtract walk overlap)
        let pureStandHours = max(0, standTimeMinutes - walkMinutes) / 60.0
        let neatStand      = pureStandHours * 0.18 * bmrPerHour

        // Baustein 3 — NEAT_Micro (HR-based gap filler)
        var neatMicro = 0.0
        if let hrRest = restingHR, let hrAvg = avgHRWaking,
           hrRest > 0, hrAvg > hrRest, weightKg > 0 {

            let hrMax   = 220.0 - Double(age)
            let divisor = hrMax - hrRest
            guard divisor > 0 else { return max(0, neatSteps + neatStand) }

            let wakeMinutes  = (24.0 - sleepHours) * 60.0
            let workoutMin   = workoutSeconds / 60.0
            let gapMinutes   = max(0, wakeMinutes - walkMinutes - standTimeMinutes - workoutMin)

            // Keytel outputs kJ/min — convert to kcal/min, then subtract resting share
            let k_kJ: Double = isMale
                ? -55.0969 + 0.6309 * hrMax + 0.1988 * weightKg + 0.2017 * Double(age)
                : -20.4022 + 0.4472 * hrMax - 0.1263 * weightKg + 0.0740 * Double(age)
            let k_kcal       = k_kJ / 4.184
            let bmrPerMinute = bmrDynamisch / (24.0 * 60.0)
            let k_netto      = max(0, k_kcal - bmrPerMinute)

            neatMicro = max(0, ((hrAvg - hrRest) / divisor) * gapMinutes * k_netto)
        }

        return max(0, neatSteps + neatStand + neatMicro)
    }

    // MARK: - EAT (Exercise Activity Thermogenesis)

    /// Net active calories from a single workout using the Hiilloskorpi HRR formula.
    ///
    /// Hiilloskorpi already measures the net active expenditure above rest,
    /// so no additional BMR subtraction is needed.
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

        let vo2    = (vo2Max ?? 0) > 0 ? vo2Max! : (isMale ? 45.0 : 40.0)
        let hrRst  = (hrRest ?? 0) > 0 ? hrRest! : 60.0
        let hrMax  = 220.0 - Double(age)
        let hrr    = (avgHR - hrRst) / max(1, hrMax - hrRst)

        // Hiilloskorpi formula (kJ/min → kcal/min × minutes)
        let kJperMin: Double = isMale
            ? weightKg * vo2 * (0.019  * hrr - 0.0043)
            : weightKg * vo2 * (0.0143 * hrr - 0.0038)
        var bruttoKcal = (kJperMin / 4.184) * minutes

        // EPOC — strength training: fixed ×1.20 (HR underestimates muscular load).
        // All other sports: linear 0–20 % between 60 % and 85 % of HR_max.
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

    // MARK: - Combined

    /// Computes total active calories (NEAT + EAT) for a day's HealthKit data.
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
        bmrDynamisch: Double
    ) -> ActivityResult {
        let workoutSeconds = workouts.reduce(0.0) { $0 + $1.duration }
        let neatKcal = neat(
            steps:            steps,
            standTimeMinutes: standTimeMinutes,
            restingHR:        restingHR,
            avgHRWaking:      avgHRWaking,
            workoutSeconds:   workoutSeconds,
            sleepHours:       sleepHours,
            weightKg:         weightKg,
            age:              age,
            isMale:           isMale,
            bmrDynamisch:     bmrDynamisch
        )
        let eatKcal = workouts.reduce(0.0) { sum, w in
            sum + eat(workout: w, weightKg: weightKg, vo2Max: vo2Max,
                      hrRest: restingHR, age: age, isMale: isMale)
        }
        return ActivityResult(neatKcal: neatKcal, eatKcal: eatKcal)
    }
}
