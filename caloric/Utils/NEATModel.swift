import Foundation
import HealthKit

// MARK: - NEAT Model (Non-Exercise Activity Thermogenesis)
//
// Design: pure, synchronous, testable math in NEATCalculator.
// HealthKit fetching lives in HealthKitNEATProvider, which builds NEATInputs
// from time-weighted HR segments — no pre-aggregated zone averages.
//
// Assembly contract:
//   TDEE = BMR₂₄ₕ + neat + EAT + TEF
// All NEAT components are NET (above-basal). BMR for the full 24 h must be
// added exactly ONCE, outside this function.

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
    /// Apple Stand Time in minutes (includes walking).
    var standTimeMinutes: Double
    /// Resting heart rate (bpm); nil when unavailable.
    var restingHR: Double?
    /// Total workout duration in seconds (EAT window; excluded from NEAT time budget).
    var workoutSeconds: Double
    /// Minute-of-day the user woke (sleep end). e.g. 07:30 → 450.
    var wakeMinuteOfDay: Double
    /// Minute-of-day up to which we count: clock time if today, else 1440.
    var dayEndMinuteOfDay: Double
    /// Non-workout HR samples with time weights from real sample gaps.
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
    private static let stepsPerMinute = 110.0   // walking cadence for step→time conversion
    private static let walkNetFactor  = 2.0     // brisk walk ≈ 3 MET gross → ~2 net above basal
    private static let standNetFactor = 0.14    // light standing above basal

    // HR block parameters
    private static let hrDeadband    = 5.0      // ignore ≤ 5 bpm above resting (noise / breathing)
    private static let hrCeiling     = 55.0     // clamp spikes above +55 bpm (coffee, stress, artefact)
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
        // nonWorkoutSteps already excludes workout windows, so no time-budget cap needed.
        let walkMinutes = Double(i.nonWorkoutSteps) / stepsPerMinute
        let neatSteps   = (walkMinutes / 60.0) * walkNetFactor * bmrPerHour

        // --- Standing ---
        // standTimeMinutes is Apple Stand Time (≈1 min per stand-hour, already net of workouts).
        let neatStand = (max(0, i.standTimeMinutes) / 60.0) * standNetFactor * bmrPerHour

        // --- Continuous HR block ---
        // Process every non-workout segment with its real time weight.
        // A deadband suppresses near-resting noise; a ceiling absorbs
        // transient spikes without discarding the full segment duration.
        var neatHR = 0.0
        if let hrRest = i.restingHR, hrRest > 0, !i.hrSegments.isEmpty {
            let hrMax   = 208.0 - 0.7 * Double(i.age)   // Tanaka formula
            let reserve = max(1.0, hrMax - hrRest)

            for seg in i.hrSegments {
                let durationMin = seg.durationSeconds / 60.0
                guard durationMin > 0, seg.hr > hrRest + hrDeadband else { continue }

                let cleanHR = min(seg.hr, hrRest + hrCeiling)
                let hrr     = (cleanHR - hrRest) / reserve
                let load    = pow(min(hrr, 1.0), hrPower)

                neatHR += load * durationMin * bmrPerMinute * hrMaxNetMET
            }

            neatHR = min(neatHR, hrDailyCap)
            neatHR = max(0, neatHR)
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

// MARK: - HealthKit provider

/// Standalone async provider that builds a fully populated `NEATInputs`
/// value directly from HealthKit. The dashboard currently uses
/// `ActivityCalculationService.calculate()` instead, but this provider
/// remains available for batch or background NEAT computations.
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

        let workouts       = try await workouts(start: dayStart, end: dayEnd)
        let workoutWindows = workouts.map { DateInterval(start: $0.startDate, end: $0.endDate) }
        let workoutSeconds = workouts.reduce(0.0) { $0 + $1.duration }

        let wakeDate         = try await wakeTime(dayStart: dayStart, dayEnd: dayEnd, calendar: calendar)
        let wakeMinuteOfDay  = minuteOfDay(wakeDate, dayStart: dayStart)

        let now               = Date()
        let isToday           = calendar.isDate(day, inSameDayAs: now)
        let dayEndMinuteOfDay = isToday ? minuteOfDay(now, dayStart: dayStart) : 1440.0

        let nonWorkoutSteps = try await nonWorkoutStepCount(
            start: dayStart, end: dayEnd, excluding: workoutWindows
        )

        let rawStandMinutes  = try await appleStandTimeMinutes(start: dayStart, end: dayEnd)
        let workoutMinutes   = workoutSeconds / 60.0
        let standTimeMinutes = max(0, rawStandMinutes - workoutMinutes)

        let restingHR  = try await restingHeartRate(start: dayStart, end: dayEnd)
        let windowEnd  = isToday ? now : dayEnd
        let hrSegments = try await fetchHRSegments(
            start: wakeDate, end: windowEnd, excluding: workoutWindows
        )

        return NEATInputs(
            nonWorkoutSteps:   nonWorkoutSteps,
            standTimeMinutes:  standTimeMinutes,
            restingHR:         restingHR,
            workoutSeconds:    workoutSeconds,
            wakeMinuteOfDay:   wakeMinuteOfDay,
            dayEndMinuteOfDay: dayEndMinuteOfDay,
            hrSegments:        hrSegments,
            age:          age,
            isMale:       isMale,
            weightKg:     weightKg,
            bmrDynamisch: bmrDynamisch
        )
    }

    // MARK: - HR Segment Fetch

    /// Fetches non-workout HR samples and converts them into time-weighted segments.
    private func fetchHRSegments(
        start: Date,
        end: Date,
        excluding windows: [DateInterval]
    ) async throws -> [HRSegment] {
        guard end > start,
              let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return []
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples   = try await sampleQuery(sampleType: type, predicate: predicate)
        let unit      = HKUnit.count().unitDivided(by: .minute())

        let valid = samples
            .compactMap { $0 as? HKQuantitySample }
            .filter { s in
                !windows.contains { $0.intersects(DateInterval(start: s.startDate, end: s.endDate)) }
            }
            .sorted { $0.endDate < $1.endDate }

        guard !valid.isEmpty else { return [] }

        let durations = sampleDurations(for: valid)
        return zip(valid, durations).map { (s, d) in
            HRSegment(hr: s.quantity.doubleValue(for: unit), durationSeconds: d)
        }
    }

    // MARK: - Individual fetches

    private func workouts(start: Date, end: Date) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let samples   = try await sampleQuery(sampleType: .workoutType(), predicate: predicate)
        return samples.compactMap { $0 as? HKWorkout }
    }

    private func nonWorkoutStepCount(
        start: Date, end: Date, excluding windows: [DateInterval]
    ) async throws -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples   = try await sampleQuery(sampleType: stepType, predicate: predicate)
        let total = samples
            .compactMap { $0 as? HKQuantitySample }
            .filter { s in
                !windows.contains { $0.intersects(DateInterval(start: s.startDate, end: s.endDate)) }
            }
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
            limit: 1
        )
        return (samples.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
    }

    private func wakeTime(dayStart: Date, dayEnd: Date, calendar: Calendar) async throws -> Date {
        let fallback    = calendar.date(byAdding: .hour, value: 7, to: dayStart)!
        guard let type  = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return fallback }
        let searchStart = calendar.date(byAdding: .hour, value: -12, to: dayStart)!
        let predicate   = HKQuery.predicateForSamples(withStart: searchStart, end: dayEnd, options: [])
        let samples     = try await sampleQuery(sampleType: type, predicate: predicate)

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

        let wake = samples
            .compactMap { $0 as? HKCategorySample }
            .filter { asleepValues.contains($0.value) }
            .map { $0.endDate }
            .filter { $0 >= dayStart && $0 <= dayEnd }
            .max()

        return wake ?? fallback
    }

    // MARK: - Duration helper

    /// Derives per-sample durations from adjacent end-date gaps, clamped to [5, 120] s.
    private func sampleDurations(for samples: [HKQuantitySample]) -> [Double] {
        guard !samples.isEmpty else { return [] }
        if samples.count == 1 { return [15.0] }

        var deltas = [Double]()
        deltas.reserveCapacity(samples.count)

        for i in 0..<(samples.count - 1) {
            let raw = samples[i + 1].endDate.timeIntervalSince(samples[i].endDate)
            deltas.append(min(max(raw, 5.0), 120.0))
        }
        let fallback = median(deltas) ?? 15.0
        deltas.append(fallback)
        return deltas
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
        let mid    = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2.0 : sorted[mid]
    }
}
