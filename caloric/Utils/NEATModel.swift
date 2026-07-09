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

    // --- Two-Zone MVPA Buckets ---
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

    // Conservative calibration:
    // - walking is estimated from steps, but capped by available awake non-cardio time
    // - standing is net-above-basal and intentionally small
    // - micro-NEAT is restrained to avoid inflating "coffee/stress pulse"
    // - unrecorded cardio uses sustained HR segments, not sample counts

    private static let stepsPerMinute        = 110.0  // conservative walking cadence
    private static let walkNetFactor         = 2.0    // brisk walking ≈ 3 MET gross → ~2 net
    private static let standNetFactor        = 0.14   // light standing above basal
    private static let microMaxNetMET        = 1.6    // restrained micro-movement ceiling
    private static let microDailyCap         = 300.0  // safety cap for fidgeting/desk movement
    private static let cardioMaxNetMET       = 3.2    // moderate ceiling for unrecorded cardio
    private static let cardioDailyCap        = 500.0  // safety cap for unrecorded cardio

    static func neat(_ i: NEATInputs) -> Double {
        guard i.bmrDynamisch > 0 else { return 0 }

        let bmrPerHour = i.bmrDynamisch / 24.0
        let bmrPerMinute = i.bmrDynamisch / (24.0 * 60.0)

        let awakeMinutes = max(0, i.dayEndMinuteOfDay - i.wakeMinuteOfDay)
        let workoutMinutes = max(0, i.workoutSeconds / 60.0)
        let cardioMinutes = max(0, i.unrecordedCardioMinutes)

        // --- Step minutes ---
        // Steps are capped by available awake time outside workouts and unrecorded cardio,
        // so steps cannot "reuse" time that is already attributed elsewhere.
        let availableForSteps = max(0, awakeMinutes - workoutMinutes - cardioMinutes)
        let walkMinutesRaw = Double(i.nonWorkoutSteps) / stepsPerMinute
        let walkMinutes = min(walkMinutesRaw, availableForSteps)

        let neatSteps = (walkMinutes / 60.0) * walkNetFactor * bmrPerHour

        // --- Pure standing ---
        // Standing time already includes walking; we subtract the capped walk minutes,
        // and clamp to the awake time outside workouts.
        let standWindowMinutes = min(max(0, i.standTimeMinutes), max(0, awakeMinutes - workoutMinutes))
        let pureStandMin = max(0, standWindowMinutes - walkMinutes)
        let neatStand = (pureStandMin / 60.0) * standNetFactor * bmrPerHour

        // --- Micro (sedentary gap via HR reserve) ---
        var neatMicro = 0.0
        if let hrRest = i.restingHR, let sedHR = i.sedentaryAvgHR,
           hrRest > 0, i.sedentaryGapMinutes > 0 {

            let hrMax = 208.0 - 0.7 * Double(i.age)   // Tanaka
            let divisor = hrMax - hrRest

            if divisor > 0 {
                // Keep sitting pulses tight: ignore tiny deviations, cap coffee/stress spikes.
                let cleanHR = min(max(sedHR, hrRest + 2.0), hrRest + 22.0)
                let load = (cleanHR - hrRest) / divisor

                let kNet = bmrPerMinute * microMaxNetMET
                neatMicro = min(load * i.sedentaryGapMinutes * kNet, microDailyCap)
                neatMicro = max(0, neatMicro)
            }
        }

        // --- Unrecorded cardio ---
        var neatUnrecordedCardio = 0.0
        if let hrRest = i.restingHR, let cardioHR = i.unrecordedCardioAvgHR,
           hrRest > 0, cardioMinutes > 0 {

            let hrMax = 208.0 - 0.7 * Double(i.age)
            let divisor = hrMax - hrRest

            if divisor > 0 {
                // Load relative to a stricter cardio threshold, not just to resting HR.
                let cardioThreshold = max(hrRest + 35.0, hrRest + 0.45 * divisor)
                let effectiveRange = max(1.0, hrMax - cardioThreshold)

                let normalized = (cardioHR - cardioThreshold) / effectiveRange
                let load = pow(clamp(normalized, lower: 0.0, upper: 1.0), 1.15)

                let kNetCardio = bmrPerMinute * cardioMaxNetMET
                let rawCardio = load * cardioMinutes * kNetCardio
                neatUnrecordedCardio = min(rawCardio, cardioDailyCap)
                neatUnrecordedCardio = max(0, neatUnrecordedCardio)
            }
        }

        return max(0, neatSteps + neatStand + neatMicro + neatUnrecordedCardio)
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
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
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

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
            start: dayStart,
            end: dayEnd,
            excluding: workoutWindows
        )

        // 5) Stand time MINUS workouts
        let rawStandMinutes = try await appleStandTimeMinutes(start: dayStart, end: dayEnd)
        let workoutMinutes = workoutSeconds / 60.0
        let standTimeMinutes = max(0, rawStandMinutes - workoutMinutes)

        // 6) Resting HR
        let restingHR = try await restingHeartRate(start: dayStart, end: dayEnd)

        // 7) Gap analysis
        let awakeMin = max(0, dayEndMinuteOfDay - wakeMinuteOfDay)
        let totalGapMin = max(0, awakeMin - standTimeMinutes - workoutMinutes)

        let gapAnalysis = try await analyzeGapHeartRate(
            start: wakeDate,
            end: isToday ? now : dayEnd,
            restingHR: restingHR,
            excluding: workoutWindows,
            totalGapMin: totalGapMin
        )

        return NEATInputs(
            nonWorkoutSteps: nonWorkoutSteps,
            standTimeMinutes: standTimeMinutes,
            restingHR: restingHR,
            workoutSeconds: workoutSeconds,
            wakeMinuteOfDay: wakeMinuteOfDay,
            dayEndMinuteOfDay: dayEndMinuteOfDay,
            sedentaryGapMinutes: gapAnalysis.sedentaryMinutes,
            sedentaryAvgHR: gapAnalysis.sedentaryHR,
            unrecordedCardioMinutes: gapAnalysis.cardioMinutes,
            unrecordedCardioAvgHR: gapAnalysis.cardioHR,
            age: age,
            isMale: isMale,
            weightKg: weightKg,
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
            sampleType: type,
            predicate: predicate,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)],
            limit: 1
        )
        return (samples.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
    }

    /// Analysiert die Herzfrequenz und rechnet die Samples über ein Zeit-Mapping in echte Minuten um.
    /// Cardio wird nur gezählt, wenn es als zusammenhängender Abschnitt mindestens 2 Minuten dauert.
    private func analyzeGapHeartRate(
        start: Date,
        end: Date,
        restingHR: Double?,
        excluding windows: [DateInterval],
        totalGapMin: Double
    ) async throws -> (cardioMinutes: Double, sedentaryMinutes: Double, sedentaryHR: Double?, cardioHR: Double?) {

        guard end > start, let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return (0.0, totalGapMin, nil, nil)
        }

        guard let restingHR, restingHR > 0 else {
            // Ohne Ruhepuls keine saubere Zuordnung: alles im Gap als sedentary behandeln.
            return (0.0, totalGapMin, nil, nil)
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples = try await sampleQuery(sampleType: type, predicate: predicate)
        let unit = HKUnit.count().unitDivided(by: .minute())

        let validSamples = samples
            .compactMap { $0 as? HKQuantitySample }
            .filter { s in !windows.contains { $0.intersects(DateInterval(start: s.startDate, end: s.endDate)) } }
            .sorted { $0.endDate < $1.endDate }

        guard !validSamples.isEmpty else { return (0.0, totalGapMin, nil, nil) }

        let hrMax = 208.0 - 0.7 * Double(max(1, Calendar.current.component(.year, from: Date()) - 0)) // not used directly
        let reserve = max(1.0, hrMax - restingHR)

        // A stricter threshold to avoid turning mild stress or coffee into cardio.
        let cardioThreshold = max(restingHR + 35.0, restingHR + 0.45 * reserve)
        let minCardioSegmentSeconds = 120.0

        let durations = sampleDurations(for: validSamples)

        var sedentaryValues: [Double] = []
        var cardioValues: [Double] = []

        var cardioSeconds = 0.0
        var currentSegmentSeconds = 0.0
        var currentSegmentValues: [Double] = []
        var inCardioSegment = false

        func flushCurrentSegment() {
            guard !currentSegmentValues.isEmpty else { return }

            if currentSegmentSeconds >= minCardioSegmentSeconds {
                cardioSeconds += currentSegmentSeconds
                cardioValues.append(contentsOf: currentSegmentValues)
            } else {
                sedentaryValues.append(contentsOf: currentSegmentValues)
            }

            currentSegmentSeconds = 0.0
            currentSegmentValues.removeAll(keepingCapacity: true)
            inCardioSegment = false
        }

        for (sample, dtSeconds) in zip(validSamples, durations) {
            let hr = sample.quantity.doubleValue(for: unit)
            let isCardio = hr >= cardioThreshold

            if isCardio {
                inCardioSegment = true
                currentSegmentSeconds += dtSeconds
                currentSegmentValues.append(hr)
            } else {
                if inCardioSegment {
                    flushCurrentSegment()
                }
                sedentaryValues.append(hr)
            }
        }

        if inCardioSegment {
            flushCurrentSegment()
        }

        let calculatedCardioMinutes = cardioSeconds / 60.0
        let finalCardioMinutes = min(calculatedCardioMinutes, totalGapMin)
        let finalSedentaryMinutes = max(0, totalGapMin - finalCardioMinutes)

        let sedHR = sedentaryValues.isEmpty ? nil : sedentaryValues.reduce(0, +) / Double(sedentaryValues.count)
        let cardioHR = cardioValues.isEmpty ? nil : cardioValues.reduce(0, +) / Double(cardioValues.count)

        return (finalCardioMinutes, finalSedentaryMinutes, sedHR, cardioHR)
    }

    /// Derive a duration for each HR sample from adjacent timestamps.
    /// This is much more stable than `sampleCount * fixedMinutes`.
    private func sampleDurations(for samples: [HKQuantitySample]) -> [Double] {
        guard !samples.isEmpty else { return [] }

        if samples.count == 1 {
            return [15.0] // conservative fallback for a lone sample
        }

        var deltas: [Double] = []
        deltas.reserveCapacity(samples.count)

        for i in 0..<(samples.count - 1) {
            let raw = samples[i + 1].endDate.timeIntervalSince(samples[i].endDate)
            let clamped = clamp(raw, lower: 5.0, upper: 120.0)
            deltas.append(clamped)
        }

        let fallback = median(deltas) ?? 15.0
        deltas.append(fallback) // last sample gets the typical observed interval

        return deltas
    }

    private func wakeTime(dayStart: Date, dayEnd: Date, calendar: Calendar) async throws -> Date {
        let fallback = calendar.date(byAdding: .hour, value: 7, to: dayStart)!
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return fallback }

        let searchStart = calendar.date(byAdding: .hour, value: -12, to: dayStart)!
        let predicate = HKQuery.predicateForSamples(withStart: searchStart, end: dayEnd, options: [])
        let samples = try await sampleQuery(sampleType: type, predicate: predicate)

        let asleepValues: Set<Int> = {
            if #available(iOS 16.0, *) {
                return [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                ]
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
            let q = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: sortDescriptors
            ) { _, samples, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: samples ?? [])
                }
            }
            healthStore.execute(q)
        }
    }

    private func sumStatistics(
        quantityType: HKQuantityType,
        predicate: NSPredicate
    ) async throws -> HKQuantity? {
        try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: stats?.sumQuantity())
                }
            }
            healthStore.execute(q)
        }
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        } else {
            return sorted[mid]
        }
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
