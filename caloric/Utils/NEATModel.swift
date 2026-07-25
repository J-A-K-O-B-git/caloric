import Foundation
import HealthKit

// MARK: - NEAT Model (Non-Exercise Activity Thermogenesis)
//
// Design: pure, synchronous, testable math in NEATCalculator.
// HealthKit fetching lives in HealthKitImportService, which builds the
// non-workout aggregates and time-weighted HR segments that
// ActivityCalculationService maps into NEATInputs.
//
// Assembly contract:
//   TDEE = BMR₂₄ₕ + neat + EAT + TEF
// All NEAT components are NET (above-basal). BMR for the full 24 h must be
// added exactly ONCE, outside this function.
//
// Double-counting protection (v2):
//   1. Walking bouts (cadence ≥ 80/min) are excluded from HR segments at
//      fetch level (HealthKitImportService) → a walk is counted in neatSteps
//      OR neatHR, never both.
//   2. Stand minutes subtract estimated walking minutes (Stand Time includes
//      walking).
//   3. The HR block is capped by a time budget:
//      awake − workouts − walking. This finally uses wakeMinuteOfDay /
//      dayEndMinuteOfDay, which were previously dead inputs.

// MARK: - HR Segment

/// One heart-rate sample with a duration derived from adjacent timestamps.
struct HRSegment: Sendable {
    let hr: Double              // bpm
    let durationSeconds: Double
}

// MARK: - Inputs

struct NEATInputs {
    /// Steps taken OUTSIDE workout windows.
    var nonWorkoutSteps: Int
    /// Walking/running distance OUTSIDE workout windows (meters).
    /// nil → fixed cadence/MET fallback.
    var nonWorkoutDistanceMeters: Double?
    /// Apple Stand Time in minutes (workout windows already filtered out).
    var standTimeMinutes: Double
    /// Resting heart rate (bpm); nil when unavailable.
    var restingHR: Double?
    /// Total workout duration in seconds (EAT window; excluded from NEAT time budget).
    var workoutSeconds: Double
    /// Minute-of-day the user woke (sleep end). e.g. 07:30 → 450.
    var wakeMinuteOfDay: Double
    /// Minute-of-day up to which we count: clock time if today, else 1440.
    var dayEndMinuteOfDay: Double
    /// Non-workout, non-walking HR samples with time weights from real sample gaps.
    var hrSegments: [HRSegment]
    // Body params
    var age: Int
    var isMale: Bool
    var weightKg: Double
    /// Dynamic BMR (kcal/day) for this specific day.
    var bmrDynamisch: Double
}

// MARK: - Breakdown

struct NEATBreakdown {
    let neatSteps: Double
    let neatStand: Double
    /// Unified continuous HR component (replaces the old sedentary + unrecorded-cardio split).
    let neatHR: Double
    var total: Double { neatSteps + neatStand + neatHR }
}

// MARK: - Calculator

enum NEATCalculator {

    // Calibration constants — conservative by design.
    private static let stepsPerMinute   = 110.0  // walking cadence for step→time conversion
    private static let defaultWalkNetMET = 2.0   // fallback when no distance is available
    private static let minWalkNetMET     = 1.5   // slow stroll
    private static let maxWalkNetMET     = 3.0   // brisk walk
    private static let standNetFactor    = 0.14  // light standing above basal

    // HR block parameters
    private static let hrDeadband    = 8.0      // raised from 5: caffeine, stress and
                                                // digestion (TEF is counted separately!)
                                                // lift HR without extra NEAT
    private static let hrCeiling     = 55.0     // clamp spikes above +55 bpm
    private static let hrPower       = 1.1      // sub-linear: penalises very-low-load segments
    private static let hrMaxNetMET   = 1.5      // max net MET the HR block can assign per minute
    private static let hrDailyCap    = 350.0    // hard kcal cap for the HR component

    static func neatDetailed(_ i: NEATInputs) -> NEATBreakdown {
        guard i.bmrDynamisch > 0 else {
            return NEATBreakdown(neatSteps: 0, neatStand: 0, neatHR: 0)
        }

        let bmrPerHour   = i.bmrDynamisch / 24.0
        let bmrPerMinute = i.bmrDynamisch / (24.0 * 60.0)

        // --- Steps ---
        // nonWorkoutSteps already excludes workout windows.
        let walkMinutes = Double(i.nonWorkoutSteps) / stepsPerMinute

        // Speed-adjusted net MET when distance is available: a brisk 6 km/h walk
        // costs more than a 3 km/h stroll. Bounded so outliers can't explode it.
        var walkNetMET = defaultWalkNetMET
        if let dist = i.nonWorkoutDistanceMeters, dist > 0, walkMinutes > 1 {
            let speedKmh = (dist / 1000.0) / (walkMinutes / 60.0)
            walkNetMET = min(max(speedKmh * 0.55, minWalkNetMET), maxWalkNetMET)
        }
        let neatSteps = (walkMinutes / 60.0) * walkNetMET * bmrPerHour

        // --- Standing ---
        // Apple Stand Time includes walking → subtract estimated walking minutes
        // so the same minutes aren't paid twice (steps + stand).
        let standMinutes = max(0, i.standTimeMinutes - walkMinutes)
        let neatStand    = (standMinutes / 60.0) * standNetFactor * bmrPerHour

        // --- Continuous HR block ---
        // Walking bouts are already excluded at fetch level. As a second
        // safety net, the total counted HR time is capped by the plausible
        // budget: awake time − workouts − walking. If sparse sampling ever
        // over-attributes durations, the component is scaled down.
        var neatHR = 0.0
        if let hrRest = i.restingHR, hrRest > 0, !i.hrSegments.isEmpty {
            let hrMax   = 208.0 - 0.7 * Double(i.age)   // Tanaka formula
            let reserve = max(1.0, hrMax - hrRest)

            var hrMinutesCounted = 0.0
            for seg in i.hrSegments {
                let durationMin = seg.durationSeconds / 60.0
                guard durationMin > 0, seg.hr > hrRest + hrDeadband else { continue }

                let cleanHR = min(seg.hr, hrRest + hrCeiling)
                let hrr     = (cleanHR - hrRest) / reserve
                let load    = pow(min(hrr, 1.0), hrPower)

                neatHR += load * durationMin * bmrPerMinute * hrMaxNetMET
                hrMinutesCounted += durationMin
            }

            let awakeMinutes = max(0, i.dayEndMinuteOfDay - i.wakeMinuteOfDay)
            let hrBudget = max(0, awakeMinutes - i.workoutSeconds / 60.0 - walkMinutes)
            if hrMinutesCounted > hrBudget, hrMinutesCounted > 0 {
                neatHR *= hrBudget / hrMinutesCounted
            }

            neatHR = min(max(0, neatHR), hrDailyCap)
        }

        return NEATBreakdown(
            neatSteps: max(0, neatSteps),
            neatStand: max(0, neatStand),
            neatHR:    neatHR
        )
    }

    static func neat(_ i: NEATInputs) -> Double {
        neatDetailed(i).total
    }
}

