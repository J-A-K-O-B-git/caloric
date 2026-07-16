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
//
// Double-counting protection (v2):
//   1. Walking bouts (cadence ≥ 80/min) are excluded from HR segments at
//      provider level → a walk is counted in neatSteps OR neatHR, never both.
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
        // Walking bouts are already excluded at provider level. As a second
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

// MARK: - HealthKit provider

/// Standalone async provider that builds a fully populated `NEATInputs`
/// value directly from HealthKit. The dashboard currently uses
/// `ActivityCalculationService.calculate()` instead, but this provider
/// remains available for batch or background NEAT computations.
struct HealthKitNEATProvider {

    let healthStore: HKHealthStore

    /// Step samples with cadence at or above this are treated as walking bouts
    /// and excluded from the HR block (anti double-counting).
    private static let walkCadenceThreshold = 80.0   // steps/min

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

        // Workouts: fetch everything OVERLAPPING the day (not .strictStartDate)
        // and clip to the day, so a session crossing midnight is attributed to
        // both days proportionally instead of only its start day.
        let workouts = try await workouts(start: dayStart, end: dayEnd)
        let workoutWindows = Self.merge(
            workouts.compactMap {
                Self.clip(DateInterval(start: $0.startDate, end: $0.endDate),
                          toStart: dayStart, end: dayEnd)
            }
        )
        let workoutSeconds = workoutWindows.reduce(0.0) { $0 + $1.duration }

        let wakeDate        = try await wakeTime(dayStart: dayStart, dayEnd: dayEnd, calendar: calendar)
        let wakeMinuteOfDay = minuteOfDay(wakeDate, dayStart: dayStart)

        let now               = Date()
        let isToday           = calendar.isDate(day, inSameDayAs: now)
        let dayEndMinuteOfDay = isToday ? minuteOfDay(now, dayStart: dayStart) : 1440.0
        let windowEnd         = isToday ? now : dayEnd

        // Steps & distance: statistics queries deduplicate overlapping samples
        // from multiple sources (iPhone + Watch). Manually summing
        // HKQuantitySamples would double-count when both devices record.
        let nonWorkoutSteps = Int((try await nonWorkoutSum(
            .stepCount, unit: .count(),
            start: dayStart, end: dayEnd, excluding: workoutWindows
        )).rounded())

        let nonWorkoutDistance = try await nonWorkoutSum(
            .distanceWalkingRunning, unit: .meter(),
            start: dayStart, end: dayEnd, excluding: workoutWindows
        )

        // Stand time: sample-level filtering instead of "raw − workoutMinutes".
        // Seated workouts (e.g. cycling) produce no stand time, so a flat
        // subtraction over-corrects.
        let standTimeMinutes = try await nonWorkoutStandMinutes(
            start: dayStart, end: dayEnd, excluding: workoutWindows
        )

        let restingHR = try await restingHeartRate(start: dayStart, end: dayEnd)

        // Anti double-counting: exclude walking bouts from the HR block.
        let walkWindows  = try await walkingWindows(start: dayStart, end: windowEnd)
        let hrExclusions = Self.merge(workoutWindows + walkWindows)

        let hrSegments = try await fetchHRSegments(
            start: wakeDate, end: windowEnd, excluding: hrExclusions
        )

        return NEATInputs(
            nonWorkoutSteps:          nonWorkoutSteps,
            nonWorkoutDistanceMeters: nonWorkoutDistance > 0 ? nonWorkoutDistance : nil,
            standTimeMinutes:         standTimeMinutes,
            restingHR:                restingHR,
            workoutSeconds:           workoutSeconds,
            wakeMinuteOfDay:          wakeMinuteOfDay,
            dayEndMinuteOfDay:        dayEndMinuteOfDay,
            hrSegments:               hrSegments,
            age:          age,
            isMale:       isMale,
            weightKg:     weightKg,
            bmrDynamisch: bmrDynamisch
        )
    }

    // MARK: - HR Segment Fetch

    /// Fetches non-workout, non-walking HR samples and converts them into
    /// time-weighted segments. Each segment's duration is clamped at the start
    /// of the next excluded window so it can't bleed into a workout or walk.
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

        var durations = sampleDurations(for: valid)

        // Clamp durations at the next excluded window edge.
        let sortedWindows = windows.sorted { $0.start < $1.start }
        for (i, s) in valid.enumerated() {
            if let next = sortedWindows.first(where: { $0.start > s.endDate }) {
                durations[i] = min(durations[i], next.start.timeIntervalSince(s.endDate))
            }
        }

        return zip(valid, durations).compactMap { (s, d) in
            d > 0 ? HRSegment(hr: s.quantity.doubleValue(for: unit), durationSeconds: d) : nil
        }
    }

    // MARK: - Individual fetches

    private func workouts(start: Date, end: Date) async throws -> [HKWorkout] {
        // options: [] → include workouts overlapping the day boundary.
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples   = try await sampleQuery(sampleType: .workoutType(), predicate: predicate)
        return samples.compactMap { $0 as? HKWorkout }
    }

    /// Deduplicated daily sum minus deduplicated sums inside (merged, hence
    /// non-overlapping) workout windows.
    private func nonWorkoutSum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date,
        excluding windows: [DateInterval]
    ) async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }

        let totalPredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let total = try await sumStatistics(quantityType: type, predicate: totalPredicate)?
            .doubleValue(for: unit) ?? 0

        var inWorkouts = 0.0
        for w in windows {
            let p = HKQuery.predicateForSamples(withStart: w.start, end: w.end, options: [])
            inWorkouts += try await sumStatistics(quantityType: type, predicate: p)?
                .doubleValue(for: unit) ?? 0
        }
        return max(0, total - inWorkouts)
    }

    private func nonWorkoutStandMinutes(
        start: Date, end: Date, excluding windows: [DateInterval]
    ) async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleStandTime) else { return 0 }
        // Stand time comes from the Watch only → summing samples is safe here.
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples   = try await sampleQuery(sampleType: type, predicate: predicate)
        return samples
            .compactMap { $0 as? HKQuantitySample }
            .filter { s in
                !windows.contains { $0.intersects(DateInterval(start: s.startDate, end: s.endDate)) }
            }
            .reduce(0.0) { $0 + $1.quantity.doubleValue(for: .minute()) }
    }

    /// Builds walking-bout windows from step samples with cadence ≥ threshold.
    /// Duplicate windows from multiple sources are harmless — they get merged.
    private func walkingWindows(start: Date, end: Date) async throws -> [DateInterval] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples   = try await sampleQuery(sampleType: type, predicate: predicate)

        let windows = samples
            .compactMap { $0 as? HKQuantitySample }
            .compactMap { s -> DateInterval? in
                let minutes = s.endDate.timeIntervalSince(s.startDate) / 60.0
                guard minutes >= 0.5 else { return nil }
                let cadence = s.quantity.doubleValue(for: .count()) / minutes
                return cadence >= Self.walkCadenceThreshold
                    ? DateInterval(start: s.startDate, end: s.endDate)
                    : nil
            }
        return Self.merge(windows)
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

    /// Wake time = end of the LONGEST contiguous sleep block ending within the
    /// day. `max(endDate)` over all samples would pick up an afternoon nap and
    /// push "wake" into the evening.
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

        let asleep = samples
            .compactMap { $0 as? HKCategorySample }
            .filter { asleepValues.contains($0.value) }
            .sorted { $0.startDate < $1.startDate }

        guard !asleep.isEmpty else { return fallback }

        // Merge samples into contiguous blocks (gap tolerance 45 min).
        var blocks: [(start: Date, end: Date)] = []
        for s in asleep {
            if let last = blocks.last, s.startDate.timeIntervalSince(last.end) <= 45 * 60 {
                blocks[blocks.count - 1].end = max(last.end, s.endDate)
            } else {
                blocks.append((s.startDate, s.endDate))
            }
        }

        let main = blocks
            .filter { $0.end >= dayStart && $0.end <= dayEnd }
            .max { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }

        return main?.end ?? fallback
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

    // MARK: - Interval helpers

    private static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for iv in sorted {
            if let last = result.last, iv.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start,
                                                        end: max(last.end, iv.end))
            } else {
                result.append(iv)
            }
        }
        return result
    }

    private static func clip(_ interval: DateInterval, toStart start: Date, end: Date) -> DateInterval? {
        let s = max(interval.start, start)
        let e = min(interval.end, end)
        return e > s ? DateInterval(start: s, end: e) : nil
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
