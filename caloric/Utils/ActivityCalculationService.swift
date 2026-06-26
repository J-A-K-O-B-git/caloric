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

    /// Net calories from a single workout using the Keytel heart-rate formula.
    /// Requires heart-rate data; returns 0 for workouts without HR.
    /// Strength-training sessions receive a +20 % EPOC uplift.
    static func eat(
        workout: HKWorkoutSnapshot,
        weightKg: Double,
        age: Int,
        isMale: Bool,
        bmrDynamisch: Double
    ) -> Double {
        guard let avgHR = workout.averageHeartRate,
              avgHR > 0, bmrDynamisch > 0 else { return 0 }

        let minutes = workout.duration / 60.0
        guard minutes > 0 else { return 0 }

        // Keytel outputs kJ/min
        var bruttoKJ: Double
        if isMale {
            bruttoKJ = minutes * (-55.0969 + 0.6309 * avgHR + 0.1988 * weightKg + 0.2017 * Double(age))
        } else {
            bruttoKJ = minutes * (-20.4022 + 0.4472 * avgHR - 0.1263 * weightKg + 0.0740 * Double(age))
        }

        var bruttoKcal = bruttoKJ / 4.184

        // EPOC uplift — strength training: fixed ×1.20 (HR underestimates muscular load).
        // All other sports: linear 0–20 % between 60 % and 85 % of HR_max.
        let isStrength = workout.activityType == .functionalStrengthTraining ||
                         workout.activityType == .traditionalStrengthTraining
        if isStrength {
            bruttoKcal *= 1.20
        } else {
            let hrMax     = 220.0 - Double(age)
            let intensity = hrMax > 0 ? avgHR / hrMax : 0
            if intensity >= 0.85 {
                bruttoKcal *= 1.20
            } else if intensity > 0.60 {
                let epocFactor = (intensity - 0.60) / (0.85 - 0.60) * 0.20
                bruttoKcal *= (1.0 + epocFactor)
            }
            // intensity ≤ 0.60 → no EPOC uplift
        }

        let bmrShare = (minutes / 60.0) * (bmrDynamisch / 24.0)
        return max(0, bruttoKcal - bmrShare)
    }

    // MARK: - Combined

    /// Computes total active calories (NEAT + EAT) for a day's HealthKit data.
    static func calculate(
        steps: Int,
        standTimeMinutes: Double,
        restingHR: Double?,
        avgHRWaking: Double?,
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
            sum + eat(workout: w, weightKg: weightKg, age: age, isMale: isMale, bmrDynamisch: bmrDynamisch)
        }
        return ActivityResult(neatKcal: neatKcal, eatKcal: eatKcal)
    }
}
