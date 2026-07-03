import Foundation
import HealthKit

// MARK: - NEAT Model (Non-Exercise Activity Thermogenesis)
//
// Design: the math is a PURE, synchronous, testable function (`NEATCalculator.neat`).
// All HealthKit fetching lives in `HealthKitNEATProvider`, which assembles a
// `NEATInputs` value.
//
// IMPORTANT ASSEMBLY CONTRACT:
//   TDEE = BMR₂₄ₕ + neat(...) + EAT + TEF
// All four NEAT components are NET (above-basal). BMR for the full 24h must be
// added exactly ONCE, outside this function.

// MARK: - Inputs

/// Structured, non-overlapping inputs for NEAT.
struct NEATInputs {
    /// Steps taken OUTSIDE workout windows. Workout steps belong to EAT.
    var nonWorkoutSteps: Int
    /// Apple stand time in MINUTES (`appleStandTime`) — minutes on feet, includes walking.
    var standTimeMinutes: Double
    /// Resting heart rate (bpm).
    var restingHR: Double?
    /// Total workout duration in seconds (used only for gap subtraction; its energy is EAT).
    var workoutSeconds: Double
    /// Minute-of-day the user woke (sleep end). e.g. 07:30 -> 450.
    var wakeMinuteOfDay: Double
    /// Minute-of-day up to which we count: `now` if today, else 1440.
    var dayEndMinuteOfDay: Double
    
    // --- Two-Zone MVPA Buckets (Fix für Radfahren & schwere Alltagslast) ---
    /// Sitz-/Ruhezeit in Minuten (Normaler Alltag, Büro, Sofa).
    var sedentaryGapMinutes: Double
    /// Durchschnittlicher Puls im ruhigen Alltag.
    var sedentaryAvgHR: Double?
    /// Ungemeldete Cardio-/Anstrengungszeit in Minuten (z.B. Radfahren ohne Workout-Tracking).
    var unrecordedCardioMinutes: Double
    /// Durchschnittlicher Puls während ungemeldeter Anstrengung.
    var unrecordedCardioAvgHR: Double?
    
    // Body params
    var age: Int
    var isMale: Bool
    var weightKg: Double
    /// Dynamic BMR (kcal/day) for this specific day.
    var bmrDynamisch: Double
}

// MARK: - Pure calculator

enum NEATCalculator {

    // Net (above-basal) intensity factors, multiplied by BMR/hour.
    private static let walkNetFactor    = 2.0   // brisk walking ≈ 3 MET gross → ~2 net
    private static let standNetFactor   = 0.18  // light standing above basal
    
    // Limits für Mikro-Bewegung im Sitzen
    private static let microMaxNetMET   = 3.0   // ceiling for micro-movement net intensity
    private static let microDailyCap    = 500.0 // safety cap (kcal) für Büro-Zappeln
    
    // Limits für ungemeldetes Cardio (Radfahren, Kisten schleppen)
    private static let cardioMaxNetMET  = 10.0  // ceiling für ungemeldeten Ausdauersport

    static func neat(_ i: NEATInputs) -> Double {
        guard i.bmrDynamisch > 0 else { return 0 }
        let bmrPerHour   = i.bmrDynamisch / 24.0
        let bmrPerMinute = i.bmrDynamisch / (24.0 * 60.0)

        // --- Minutes ---
        let walkMinutes = Double(i.nonWorkoutSteps) / 100.0        // ~100 steps/min
        let standMin    = max(0, i.standTimeMinutes)

        // --- Baustein 1: Steps (walking) ---
        let neatSteps = (walkMinutes / 60.0) * walkNetFactor * bmrPerHour

        // --- Baustein 2: Pure standing (on feet but NOT walking) ---
        // standTime already contains walking, so subtract it once here.
        let pureStandMin = max(0, standMin - walkMinutes)
        let neatStand = (pureStandMin / 60.0) * standNetFactor * bmrPerHour

        // --- Baustein 3: Micro (sedentary gap via HR reserve) ---
        var neatMicro = 0.0
        if let hrRest = i.restingHR, let sedHR = i.sedentaryAvgHR,
           hrRest > 0, i.sedentaryGapMinutes > 0 {

            let hrMax   = 208.0 - 0.7 * Double(i.age)   // Tanaka
            let divisor = hrMax - hrRest

            if divisor > 0 {
                // Glättung gegen Kaffee-/Stresspuls im Sitzen (+2 bis +25 bpm über Ruhepuls)
                let cleanHR = min(max(sedHR, hrRest + 2.0), hrRest + 25.0)
                let load    = (cleanHR - hrRest) / divisor
                let kNet    = bmrPerMinute * microMaxNetMET
                neatMicro   = min(load * i.sedentaryGapMinutes * kNet, microDailyCap)
                neatMicro   = max(0, neatMicro)
            }
        }

        // --- Baustein 4: Ungemeldete Anstrengung (Unrecorded MVPA / Fahrrad) ---
        var neatUnrecordedCardio = 0.0
        if let hrRest = i.restingHR, let cardioHR = i.unrecordedCardioAvgHR,
           hrRest > 0, i.unrecordedCardioMinutes > 0 {

            let hrMax   = 208.0 - 0.7 * Double(i.age)
            let divisor = hrMax - hrRest

            if divisor > 0 {
                // KEINE Glättung auf +25! Wir erlauben echten Sportpuls (z.B. 160 bpm am Berg)
                let load = min(max((cardioHR - hrRest) / divisor, 0.0), 1.0)
                let kNetCardio = bmrPerMinute * cardioMaxNetMET
                neatUnrecordedCardio = load * i.unrecordedCardioMinutes * kNetCardio
                neatUnrecordedCardio = max(0, neatUnrecordedCardio)
            }
        }

        return max(0, neatSteps + neatStand + neatMicro + neatUnrecordedCardio)
    }
}

// MARK: - HealthKit provider

struct HealthKitNEATProvider {

    let healthStore: HKHealthStore

    func makeInputs(
        for day: Date,
        age: Int,
        isMale: Bool,
        weightKg: Double,
        bmrDynamisch: Double,
        calendar: Calendar = .current
    ) async throws -> NEATInputs {

        let dayStart = calendar.startOfDay(for: day)
        let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        // 1) Workout windows
        let workouts = try await workouts(start: dayStart, end: dayEnd)
        let workoutWindows: [DateInterval] = workouts.map {
            DateInterval(start: $0.startDate, end: $0.endDate)
        }
        let workoutSeconds = workouts.reduce(0.0) { $0 + $1.duration }

        // 2) Wake time
        let wakeDate = try await wakeTime(dayStart: dayStart, dayEnd: dayEnd, calendar: calendar)
        let wakeMinuteOfDay = minuteOfDay(wakeDate, dayStart: dayStart)

        // 3) Day-end minute
        let now = Date()
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let dayEndMinuteOfDay = isToday ? minuteOfDay(now, dayStart: dayStart) : 1440.0

        // 4) Non-workout steps
        let nonWorkoutSteps = try await nonWorkoutStepCount(
            start: dayStart, end: dayEnd, excluding: workoutWindows)

        // 5) Stand time MINUS workouts
        let rawStandMinutes = try await appleStandTimeMinutes(start: dayStart, end: dayEnd)
        let workoutMinutes  = workoutSeconds / 60.0
        let standTimeMinutes = max(0, rawStandMinutes - workoutMinutes)

        // 6) Resting HR
        let restingHR = try await restingHeartRate(start: dayStart, end: dayEnd)

        // 7) Two-Zone MVPA Split (Analyse der verbleibenden Wachzeit)
        let awakeMin   = max(0, dayEndMinuteOfDay - wakeMinuteOfDay)
        let totalGapMin = max(0, awakeMin - standTimeMinutes - workoutMinutes)
        
        let gapAnalysis = try await analyzeGapHeartRate(
            start: wakeDate,
            end: isToday ? now : dayEnd,
            restingHR: restingHR ?? 60.0,
            excluding: workoutWindows
        )
        
        // Die Gap-Minuten proportional aufteilen in Ruhezeit vs. ungemeldetes Cardio
        let cardioMinutes = totalGapMin * gapAnalysis.cardioRatio
        let sedentaryMinutes = totalGapMin * (1.0 - gapAnalysis.cardioRatio)

        return NEATInputs(
            nonWorkoutSteps: nonWorkoutSteps,
            standTimeMinutes: standTimeMinutes,
            restingHR: restingHR,
            workoutSeconds: workoutSeconds,
            wakeMinuteOfDay: wakeMinuteOfDay,
            dayEndMinuteOfDay: dayEndMinuteOfDay,
            sedentaryGapMinutes: sedentaryMinutes,
            sedentaryAvgHR: gapAnalysis.sedentaryHR,
            unrecordedCardioMinutes: cardioMinutes,
            unrecordedCardioAvgHR: gapAnalysis.cardioHR,
            age: age, isMale: isMale, weightKg: weightKg,
            bmrDynamisch: bmrDynamisch
        )
    }

    // MARK: - Individual fetches & MVPA Split

    private func workouts(start: Date, end: Date) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let samples = try await sampleQuery(sampleType: .workoutType(), predicate: predicate)
        return samples.compactMap { $0 as? HKWorkout }
    }

    private func nonWorkoutStepCount(start: Date, end: Date, excluding windows: [DateInterval]) async throws -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples = try await sampleQuery(sampleType: stepType, predicate: predicate)
        let total = samples
            .compactMap { $0 as? HKQuantitySample }
            .filter { s in !windows.contains { $0.intersects(DateInterval(start: s.startDate, end: s.endDate)) } }
            .reduce(0.0) { $0 + $1.quantity.doubleValue(for: .count()) }
        return Int(total.rounded())
    }

    private func appleStandTimeMinutes(start: Date, end: Date) async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleStandTime) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sum = try await sumStatistics(quantityType: type, predicate: predicate)
        return sum?.doubleValue(for: .minute()) ?? 0
    }

    private func restingHeartRate(start: Date, end: Date) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let unit = HKUnit.count().unitDivided(by: .minute())
        let samples = try await sampleQuery(
            sampleType: type, predicate: predicate,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)],
            limit: 1)
        return (samples.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
    }

    /// Teilt die Nicht-Workout-Herzfrequenz in Ruhezeit und ungemeldete Anstrengung (MVPA) auf.
    private func analyzeGapHeartRate(
        start: Date, end: Date, restingHR: Double, excluding windows: [DateInterval]
    ) async throws -> (cardioRatio: Double, sedentaryHR: Double?, cardioHR: Double?) {
        guard end > start, let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return (0.0, nil, nil)
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples = try await sampleQuery(sampleType: type, predicate: predicate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        
        let validSamples = samples
            .compactMap { $0 as? HKQuantitySample }
            .filter { s in !windows.contains { $0.intersects(DateInterval(start: s.startDate, end: s.endDate)) } }
        
        guard !validSamples.isEmpty else { return (0.0, nil, nil) }
        
        // Schwelle für ungemeldeten Sport: Ruhepuls + 30 bpm (z.B. ab ~85 bpm bei Ruhepuls 55)
        let cardioThreshold = restingHR + 30.0
        
        var sedValues: [Double] = []
        var cardioValues: [Double] = []
        
        for s in validSamples {
            let hr = s.quantity.doubleValue(for: unit)
            if hr >= cardioThreshold {
                cardioValues.append(hr)
            } else {
                sedValues.append(hr)
            }
        }
        
        let totalCount = Double(validSamples.count)
        let cardioRatio = Double(cardioValues.count) / totalCount
        
        let sedHR = sedValues.isEmpty ? nil : sedValues.reduce(0, +) / Double(sedValues.count)
        let cardioHR = cardioValues.isEmpty ? nil : cardioValues.reduce(0, +) / Double(cardioValues.count)
        
        return (cardioRatio, sedHR, cardioHR)
    }

    private func wakeTime(dayStart: Date, dayEnd: Date, calendar: Calendar) async throws -> Date {
        let fallback = calendar.date(byAdding: .hour, value: 7, to: dayStart)!
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return fallback }
        let searchStart = calendar.date(byAdding: .hour, value: -12, to: dayStart)!
        let predicate = HKQuery.predicateForSamples(withStart: searchStart, end: dayEnd, options: [])
        let samples = try await sampleQuery(sampleType: type, predicate: predicate)

        let asleepValues: Set<Int> = {
            if #available(iOS 16.0, *) {
                return [HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                        HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue]
            } else {
                return [HKCategoryValueSleepAnalysis.asleep.rawValue]
            }
        }()

        let asleepBlocks = samples
            .compactMap { $0 as? HKCategorySample }
            .filter { asleepValues.contains($0.value) }

        let wake = asleepBlocks
            .map { $0.endDate }
            .filter { $0 >= dayStart && $0 <= dayEnd }
            .max()

        return wake ?? fallback
    }

    // MARK: - Query helpers

    private func minuteOfDay(_ date: Date, dayStart: Date) -> Double {
        max(0, date.timeIntervalSince(dayStart) / 60.0)
    }

    private func sampleQuery(
        sampleType: HKSampleType,
        predicate: NSPredicate,
        sortDescriptors: [NSSortDescriptor]? = nil,
        limit: Int = HKObjectQueryNoLimit
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: sampleType, predicate: predicate,
                                  limit: limit, sortDescriptors: sortDescriptors) { _, samples, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: samples ?? []) }
            }
            healthStore.execute(q)
        }
    }

    private func sumStatistics(
        quantityType: HKQuantityType,
        predicate: NSPredicate
    ) async throws -> HKQuantity? {
        try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { _, stats, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: stats?.sumQuantity()) }
            }
            healthStore.execute(q)
        }
    }
}
