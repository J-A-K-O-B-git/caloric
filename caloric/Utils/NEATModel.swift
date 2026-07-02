import Foundation
import HealthKit

// MARK: - NEAT Model (Non-Exercise Activity Thermogenesis)
//
// Design: the math is a PURE, synchronous, testable function (`NEATCalculator.neat`).
// All HealthKit fetching lives in `HealthKitNEATProvider`, which assembles a
// `NEATInputs` value. This lets you unit-test the calculation with fixed numbers
// and swap the data source without touching the model.
//
// IMPORTANT ASSEMBLY CONTRACT:
//   TDEE = BMR₂₄ₕ + neat(...) + EAT + TEF
// All three NEAT components are NET (above-basal). BMR for the full 24h must be
// added exactly ONCE, outside this function. Do not also add basal inside the
// active minutes, or you double-count.

// MARK: - Inputs

/// Structured, (mostly) non-overlapping inputs for NEAT.
/// Build via `HealthKitNEATProvider` or by hand for tests.
struct NEATInputs {
    /// Steps taken OUTSIDE workout windows. Workout steps belong to EAT. (Fix #3)
    var nonWorkoutSteps: Int
    /// Apple stand time in MINUTES (`appleStandTime`) — minutes on feet, includes walking.
    var standTimeMinutes: Double
    /// Resting heart rate (bpm).
    var restingHR: Double?
    /// Mean HR (bpm) over awake, NON-workout samples — the "gap"/sedentary pulse. (Fix #5)
    var gapAvgHR: Double?
    /// Total workout duration in seconds (used only for gap subtraction; its energy is EAT).
    var workoutSeconds: Double
    /// Minute-of-day the user woke (sleep end). e.g. 07:30 -> 450. (Fixes morning wake window)
    var wakeMinuteOfDay: Double
    /// Minute-of-day up to which we count: `now` if today, else 1440. (Fix #1 — no future calories, works for past days)
    var dayEndMinuteOfDay: Double
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
    private static let walkNetFactor  = 2.0   // brisk walking ≈ 3 MET gross → ~2 net
    private static let standNetFactor = 0.18  // light standing above basal
    private static let microMaxNetMET = 3.0   // ceiling for micro-movement net intensity
    private static let microDailyCap  = 500.0 // safety cap (kcal)

    static func neat(_ i: NEATInputs) -> Double {
        guard i.bmrDynamisch > 0 else { return 0 }
        let bmrPerHour   = i.bmrDynamisch / 24.0
        let bmrPerMinute = i.bmrDynamisch / (24.0 * 60.0)

        // --- Minutes ---
        let walkMinutes = Double(i.nonWorkoutSteps) / 100.0        // ~100 steps/min
        let standMin    = max(0, i.standTimeMinutes)
        let workoutMin  = i.workoutSeconds / 60.0
        let awakeMin    = max(0, i.dayEndMinuteOfDay - i.wakeMinuteOfDay)

        // --- Baustein 1: Steps (walking) ---
        let neatSteps = (walkMinutes / 60.0) * walkNetFactor * bmrPerHour

        // --- Baustein 2: Pure standing (on feet but NOT walking) ---
        // standTime already contains walking, so subtract it once here.
        let pureStandMin = max(0, standMin - walkMinutes)
        let neatStand = (pureStandMin / 60.0) * standNetFactor * bmrPerHour

        // --- Baustein 3: Micro (sedentary gap via HR reserve) ---
        // Awake time partitions as: walk + pureStand + workout + gap.
        // Since standTime = walk + pureStand, the sedentary gap is:
        //     gap = awake − standTime − workout        (Fix #2: no double-subtracting walk)
        let gapMinutes = max(0, awakeMin - standMin - workoutMin)

        var neatMicro = 0.0
        if let hrRest = i.restingHR, let gapHR = i.gapAvgHR,
           hrRest > 0, gapMinutes > 0 {

            let hrMax   = 208.0 - 0.7 * Double(i.age)   // Tanaka (tighter than 220−age)
            let divisor = hrMax - hrRest

            if divisor > 0 {
                // gapHR is already averaged over awake, non-workout samples, so the
                // arbitrary "−15 if workout" hack is gone. Just clamp to a plausible
                // sedentary band to reject residual spikes.
                let cleanHR = min(max(gapHR, hrRest + 2.0), hrRest + 25.0)
                let load    = (cleanHR - hrRest) / divisor        // 0…1 HR-reserve utilisation
                let kNet    = bmrPerMinute * microMaxNetMET       // net kcal/min at full micro load
                neatMicro   = min(load * gapMinutes * kNet, microDailyCap)
                neatMicro   = max(0, neatMicro)
            }
        }

        return max(0, neatSteps + neatStand + neatMicro)
    }
}

// MARK: - HealthKit provider

/// Fetches raw samples and assembles `NEATInputs`.
/// Adapt to your existing HealthStore/authorization if you already have one.
struct HealthKitNEATProvider {

    let healthStore: HKHealthStore

    /// Build inputs for a given calendar day.
    /// - Parameters:
    ///   - day: any Date within the target day.
    ///   - profile: values you already collect from the user / profile.
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

        // 1) Workout windows (to exclude their steps/HR and to subtract their minutes).
        let workouts = try await workouts(start: dayStart, end: dayEnd)
        let workoutWindows: [DateInterval] = workouts.map {
            DateInterval(start: $0.startDate, end: $0.endDate)
        }
        let workoutSeconds = workouts.reduce(0.0) { $0 + $1.duration }

        // 2) Wake time (sleep end of the night ending on this day) → minute of day.
        let wakeDate = try await wakeTime(dayStart: dayStart, dayEnd: dayEnd, calendar: calendar)
        let wakeMinuteOfDay = minuteOfDay(wakeDate, dayStart: dayStart)

        // 3) Day-end minute: now if today (no future calories), else full day. (Fix #1)
        let now = Date()
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let dayEndMinuteOfDay = isToday ? minuteOfDay(now, dayStart: dayStart) : 1440.0

        // 4) Non-workout steps. (Fix #3)
        let nonWorkoutSteps = try await nonWorkoutStepCount(
            start: dayStart, end: dayEnd, excluding: workoutWindows)

        // 5) Stand time (minutes on feet), MINUS stand minutes inside workouts.
        // Those belong to EAT, not NEAT — same double-count fix as steps. (Fix #3, stand side)
        let rawStandMinutes = try await appleStandTimeMinutes(start: dayStart, end: dayEnd)
        let workoutMinutes  = workoutSeconds / 60.0
        let standTimeMinutes = max(0, rawStandMinutes - workoutMinutes)

        // 6) Resting HR.
        let restingHR = try await restingHeartRate(start: dayStart, end: dayEnd)

        // 7) Gap-window average HR: awake, non-workout HR samples. (Fix #5)
        let gapAvgHR = try await averageGapHeartRate(
            start: wakeDate, end: isToday ? now : dayEnd, excluding: workoutWindows)

        return NEATInputs(
            nonWorkoutSteps: nonWorkoutSteps,
            standTimeMinutes: standTimeMinutes,
            restingHR: restingHR,
            gapAvgHR: gapAvgHR,
            workoutSeconds: workoutSeconds,
            wakeMinuteOfDay: wakeMinuteOfDay,
            dayEndMinuteOfDay: dayEndMinuteOfDay,
            age: age, isMale: isMale, weightKg: weightKg,
            bmrDynamisch: bmrDynamisch
        )
    }

    // MARK: - Individual fetches

    private func workouts(start: Date, end: Date) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let samples = try await sampleQuery(sampleType: .workoutType(), predicate: predicate)
        return samples.compactMap { $0 as? HKWorkout }
    }

    /// Sum step samples for the day, dropping any sample overlapping a workout window.
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
        // Most recent resting HR reading in the day.
        let samples = try await sampleQuery(
            sampleType: type, predicate: predicate,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)],
            limit: 1)
        return (samples.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
    }

    /// Average HR over awake, non-workout samples.
    private func averageGapHeartRate(start: Date, end: Date, excluding windows: [DateInterval]) async throws -> Double? {
        guard end > start,
              let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples = try await sampleQuery(sampleType: type, predicate: predicate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let values = samples
            .compactMap { $0 as? HKQuantitySample }
            .filter { s in !windows.contains { $0.intersects(DateInterval(start: s.startDate, end: s.endDate)) } }
            .map { $0.quantity.doubleValue(for: unit) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Wake time = end of the last "asleep" sleep block before/at this day's morning.
    /// Falls back to 07:00 if no sleep data. (Adapt source dedup to your setup.)
    private func wakeTime(dayStart: Date, dayEnd: Date, calendar: Calendar) async throws -> Date {
        let fallback = calendar.date(byAdding: .hour, value: 7, to: dayStart)!
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return fallback }
        // Look back into the previous night.
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

        // Wake = latest end among sleep blocks that finish on this morning.
        let wake = asleepBlocks
            .map { $0.endDate }
            .filter { $0 >= dayStart && $0 <= dayEnd }
            .max()

        return wake ?? fallback
    }

    // MARK: - Query helpers (continuation wrappers)

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


