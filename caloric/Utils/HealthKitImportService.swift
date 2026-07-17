//
//  HealthKitImportService.swift
//  caloric
//
//  Central service for importing raw HealthKit data.
//  Provides workouts, daily activity (steps / distance), and sleep snapshots.
//  Also caches the last 30 days of activity + workouts in `history`.
//
//  Prerequisites (one-time project setup):
//    • HealthKit capability enabled in the target (Signing & Capabilities)
//    • NSHealthShareUsageDescription key in Info.plist
//

import Foundation
import HealthKit
import SwiftData

// MARK: - Domain Models

struct HKWorkoutSnapshot: Identifiable, Sendable, Equatable {
    let id: UUID
    let activityType: HKWorkoutActivityType
    let startDate: Date
    let endDate: Date
    /// Average bpm over the workout window; nil if no heart-rate data was recorded.
    let averageHeartRate: Double?
    let sourceName: String
    let sourceBundleID: String

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
}

struct HKActivitySnapshot: Sendable {
    let steps: Int
    let distanceMeters: Double
    let fetchedAt: Date
    let standTimeMinutes: Double
    let restingHeartRate: Double?
    let avgHeartRateWaking: Double?
    /// Non-workout HR segments with time weights; empty for cache-restored snapshots.
    let hrSegments: [HRSegment]
}

struct HKSleepSnapshot: Sendable {
    /// Earliest "asleep" stage start of the night window.
    let start: Date
    /// Latest "asleep" stage end of the night window.
    let end: Date

    var durationSeconds: TimeInterval { end.timeIntervalSince(start) }
}

// MARK: - HealthKitImportService

@Observable
@MainActor
final class HealthKitImportService {

    // MARK: - Historical Cache

    struct DaySnapshot: Sendable {
        let activity: HKActivitySnapshot
        let workouts: [HKWorkoutSnapshot]
    }

    // MARK: State consumed by views

    var workouts: [HKWorkoutSnapshot] = []
    var activity   = HKActivitySnapshot(steps: 0, distanceMeters: 0, fetchedAt: Date(),
                                        standTimeMinutes: 0, restingHeartRate: nil, avgHeartRateWaking: nil,
                                        hrSegments: [])
    var sleep: HKSleepSnapshot? = nil
    var isAuthorized = false
    /// Most recent VO2max estimate from Apple Health (mL/kg·min). Nil if not available.
    var vo2Max: Double? = nil
    /// Per-day history keyed by "yyyy-MM-dd". Populated for the last 30 days on launch.
    var history: [String: DaySnapshot] = [:]

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: Private

    /// Injected by MainTabView so cache reads/writes run on the same ModelContext as SwiftData.
    @ObservationIgnored
    var modelContext: ModelContext? = nil

    private let store = HKHealthStore()

    @ObservationIgnored
    private var activeObservers: [HKObserverQuery] = []

    private static let whoopBundles: Set<String> = [
        "com.whoop.main", "com.whoop.watch"
    ]

    private static let readSet: Set<HKObjectType> = [
        .workoutType(),
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.quantityType(forIdentifier: .appleStandTime)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        HKObjectType.quantityType(forIdentifier: .vo2Max)!
    ]

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - SwiftData Cache

    /// Immediately populates `history` from the on-disk SwiftData cache.
    /// Called before HealthKit authorization so the UI has data right away.
    func loadCachedHistory() {
        guard let ctx = modelContext else { return }
        let entries = (try? ctx.fetch(FetchDescriptor<DayCacheEntry>())) ?? []
        for entry in entries {
            history[entry.dateKey] = entry.toDaySnapshot()
        }
    }

    /// Persists the current `history` dictionary to SwiftData and prunes entries older than 35 days.
    /// Called after every `fetchHistory()` completes.
    func saveHistoryToCache() {
        guard let ctx = modelContext else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? .distantPast
        let existing = (try? ctx.fetch(FetchDescriptor<DayCacheEntry>())) ?? []
        for entry in existing {
            let entryDate = Self.keyFormatter.date(from: entry.dateKey) ?? .distantPast
            if entryDate < cutoff || history[entry.dateKey] != nil {
                ctx.delete(entry)
            }
        }
        for (key, snapshot) in history {
            ctx.insert(DayCacheEntry(dateKey: key, snapshot: snapshot))
        }
        try? ctx.save()
    }

    // MARK: - Date Helpers

    func daySnapshot(for date: Date) -> DaySnapshot? {
        history[Self.dateKey(date)]
    }

    static func dateKey(_ date: Date) -> String {
        keyFormatter.string(from: date)
    }

    // MARK: - Authorization & Entry Point

    func requestAuthorization() async throws {
        if isSimulator {
            isAuthorized = true
            await fetchAll()
            await fetchHistory(days: 90)
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        loadCachedHistory()
        try await store.requestAuthorization(toShare: [], read: Self.readSet)
        isAuthorized = true
        await fetchAll()
        await fetchHistory(days: 90)
        saveHistoryToCache()
        startObservers()
    }

    /// Re-fetches today's data domains concurrently (workouts, activity, sleep, VO2max).
    func fetchAll() async {
        async let w = fetchWorkoutsData()
        async let a = fetchActivityData()
        async let s = fetchSleepData()
        async let v = fetchVO2Max()
        let (wData, aData, sData, vData) = await (w, a, s, v)
        workouts = wData
        activity = aData
        sleep    = sData
        vo2Max   = vData
    }

    /// Fetches and caches activity + workouts for the last `days` days.
    func fetchHistory(days: Int = 30) async {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())

        await withTaskGroup(of: (String, DaySnapshot).self) { group in
            for offset in 1...days {
                guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
                let key = Self.dateKey(date)
                group.addTask {
                    async let a = self.fetchActivityData(for: date)
                    async let w = self.fetchWorkoutsData(for: date)
                    let (activity, workouts) = await (a, w)
                    return (key, DaySnapshot(activity: activity, workouts: workouts))
                }
            }
            for await (key, snapshot) in group {
                history[key] = snapshot
            }
        }
    }

    // MARK: - Workouts

    private func fetchWorkoutsData(for date: Date = Date()) async -> [HKWorkoutSnapshot] {
        if isSimulator { return mockWorkoutsData(for: date) }
        let cal   = Calendar.current
        let start = cal.startOfDay(for: date)
        let end   = cal.isDateInToday(date) ? Date() : cal.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictStartDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let raw: [HKWorkout] = await hkSamples(
            type: .workoutType(), predicate: predicate, sort: sort
        )

        var snapshots: [HKWorkoutSnapshot] = []
        await withTaskGroup(of: HKWorkoutSnapshot.self) { group in
            for workout in raw {
                group.addTask { await self.makeSnapshot(from: workout) }
            }
            for await s in group { snapshots.append(s) }
        }

        snapshots.sort { $0.startDate < $1.startDate }
        return deduplicate(snapshots)
    }

    private func makeSnapshot(from w: HKWorkout) async -> HKWorkoutSnapshot {
        let hr = await averageHeartRate(from: w.startDate, to: w.endDate)
        return HKWorkoutSnapshot(
            id:                 w.uuid,
            activityType:       w.workoutActivityType,
            startDate:          w.startDate,
            endDate:            w.endDate,
            averageHeartRate:   hr,
            sourceName:         w.sourceRevision.source.name,
            sourceBundleID:     w.sourceRevision.source.bundleIdentifier
        )
    }

    private func averageHeartRate(from start: Date, to end: Date) async -> Double? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: [.strictStartDate, .strictEndDate]
        )
        return await hkStatistic(type: hrType, predicate: predicate, options: .discreteAverage) {
            $0.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
        }
    }

    // MARK: - Deduplication

    private func deduplicate(_ sorted: [HKWorkoutSnapshot]) -> [HKWorkoutSnapshot] {
        var result:    [HKWorkoutSnapshot] = []
        var processed = Set<UUID>()

        for i in sorted.indices {
            guard !processed.contains(sorted[i].id) else { continue }
            processed.insert(sorted[i].id)
            var best = sorted[i]

            for j in sorted.indices.dropFirst(i + 1) {
                let diff = abs(sorted[j].startDate.timeIntervalSince(sorted[i].startDate))
                guard diff <= 60 else { break }
                processed.insert(sorted[j].id)
                
                let jIsWhoop    = Self.whoopBundles.contains(sorted[j].sourceBundleID)
                let bestIsWhoop = Self.whoopBundles.contains(best.sourceBundleID)
                
                // If the new one (j) is NOT Whoop, but the current best IS Whoop, prefer the new one (Apple Watch/Other).
                if !jIsWhoop && bestIsWhoop {
                    best = sorted[j]
                }
            }
            result.append(best)
        }
        return result
    }

    // MARK: - Activity (steps + distance + stand + HR)

    private func fetchActivityData(for date: Date = Date()) async -> HKActivitySnapshot {
        if isSimulator { return mockActivityData(for: date) }
        let cal   = Calendar.current
        let start = cal.startOfDay(for: date)
        let end   = cal.isDateInToday(date) ? Date() : cal.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictStartDate
        )
        // Waking HR window: 6 am → end of period
        let wakeStart = cal.date(bySettingHour: 6, minute: 0, second: 0, of: start) ?? start

        async let steps   = hkSum(.stepCount,              unit: .count(),  predicate: predicate, requireWatch: false)
        async let dist    = hkSum(.distanceWalkingRunning, unit: .meter(),  predicate: predicate, requireWatch: false)
        async let stand   = hkSum(.appleStandTime,         unit: .minute(), predicate: predicate, requireWatch: false)
        async let resting = fetchRestingHeartRate(for: date)
        async let avgHR   = fetchAvgHeartRate(from: wakeStart, to: end)
        
        let workouts = await fetchWorkoutsData(for: date)
        let workoutWindows = workouts.map { DateInterval(start: $0.startDate, end: $0.endDate) }

        let hrSegments = await fetchHRSegments(from: wakeStart, to: end, excluding: workoutWindows)

        return await HKActivitySnapshot(
            steps:              Int(steps ?? 0),
            distanceMeters:     dist ?? 0,
            fetchedAt:          date,
            standTimeMinutes:   stand ?? 0,
            restingHeartRate:   resting,
            avgHeartRateWaking: avgHR,
            hrSegments:         hrSegments
        )
    }

    /// Fetches non-workout HR samples and converts them to time-weighted segments.
    private func fetchHRSegments(
        from start: Date,
        to end: Date,
        excluding windows: [DateInterval]
    ) async -> [HRSegment] {
        guard end > start,
              let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return []
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
        let samples: [HKQuantitySample] = await hkSamples(type: type, predicate: predicate, sort: sort)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let valid = samples.filter { s in
            !windows.contains { $0.intersects(DateInterval(start: s.startDate, end: s.endDate)) }
        }
        guard !valid.isEmpty else { return [] }
        let durations = hrSampleDurations(for: valid)
        return zip(valid, durations).map { (s, d) in
            HRSegment(hr: s.quantity.doubleValue(for: unit), durationSeconds: d)
        }
    }

    private func hrSampleDurations(for samples: [HKQuantitySample]) -> [Double] {
        guard samples.count > 1 else { return samples.isEmpty ? [] : [15.0] }
        var deltas = [Double]()
        deltas.reserveCapacity(samples.count)
        for i in 0..<(samples.count - 1) {
            let raw = samples[i + 1].endDate.timeIntervalSince(samples[i].endDate)
            deltas.append(min(max(raw, 5.0), 120.0))
        }
        let sorted   = deltas.sorted()
        let fallback = sorted[sorted.count / 2]
        deltas.append(fallback)
        return deltas
    }

    private func fetchRestingHeartRate(for date: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        let cal   = Calendar.current
        let start = cal.startOfDay(for: date)
        let end   = cal.isDateInToday(date) ? Date() : cal.date(byAdding: .day, value: 1, to: start)!
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        // Resting HR is a system-calculated metric, it might not always have the "Watch" device model metadata.
        // We disable requireWatch here to ensure we get this value for historical data.
        return await hkStatistic(type: type, predicate: pred, options: .discreteAverage, requireWatch: false) {
            $0.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
        }
    }

    private func fetchAvgHeartRate(from start: Date, to end: Date) async -> Double? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await hkStatistic(type: hrType, predicate: pred, options: .discreteAverage) {
            $0.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
        }
    }

    /// Returns the most recent VO2max estimate recorded by Apple Health (mL/kg·min).
    private func fetchVO2Max() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return nil }
        let cal   = Calendar.current
        let end   = Date()
        let start = cal.date(byAdding: .day, value: -90, to: end) ?? end
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        // VO2Max is often a system-estimated metric, it might not always have the "Watch" device model metadata.
        // We disable requireWatch here to ensure we get this value for calculations.
        return await hkStatistic(type: type, predicate: pred, options: .discreteAverage, requireWatch: false) {
            $0.averageQuantity()?.doubleValue(for: HKUnit(from: "ml/kg*min"))
        }
    }

    // MARK: - Sleep Analysis

    private func fetchSleepData() async -> HKSleepSnapshot? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let cal = Calendar.current
        let now = Date()

        let windowStart = cal.date(
            bySettingHour: 18, minute: 0, second: 0,
            of: cal.date(byAdding: .day, value: -1, to: now)!
        )!
        let windowEnd = cal.date(bySettingHour: 14, minute: 0, second: 0, of: now)!

        let predicate = HKQuery.predicateForSamples(
            withStart: windowStart, end: windowEnd, options: .strictStartDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        // Sleep data can come from Phone or Watch. Usually, Watch data is better.
        // If the user ONLY wants Watch activities, we might want to filter sleep too, 
        // but the request specifically mentioned "Aktivitäten" (Activities).
        // I'll keep requireWatch: true for consistency if the user wants Apple Watch only.
        let samples: [HKCategorySample] = await hkSamples(
            type: sleepType, predicate: predicate, sort: sort, requireWatch: true
        )

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        let asleep = samples.filter { asleepValues.contains($0.value) }

        guard let start = asleep.map(\.startDate).min(),
              let end   = asleep.map(\.endDate).max()
        else { return nil }

        return HKSleepSnapshot(start: start, end: end)
    }

    // MARK: - Observer Queries (Live Sync)

    private func startObservers() {
        stopObservers()

        let observedTypes: [HKSampleType] = [
            .workoutType(),
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        for sampleType in observedTypes {
            store.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { _, _ in }

            let observer = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, done, _ in
                Task { @MainActor [weak self] in
                    await self?.handleUpdate(for: sampleType)
                    done()
                }
            }
            store.execute(observer)
            activeObservers.append(observer)
        }
    }

    private func handleUpdate(for type: HKSampleType) async {
        if type == HKObjectType.workoutType() {
            workouts = await fetchWorkoutsData()
        } else if type.identifier == HKQuantityTypeIdentifier.stepCount.rawValue {
            activity = await fetchActivityData()
        } else if type.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue {
            sleep = await fetchSleepData()
        }
    }

    private func stopObservers() {
        activeObservers.forEach { store.stop($0) }
        activeObservers.removeAll()
    }

    // MARK: - HealthKit Query Helpers

    // HealthKit does not support raw NSPredicate key-path queries on sourceRevision.source.bundleIdentifier.
    // Use HKSourceQuery first to discover valid sources in the time window, then build a supported predicate.
    private func appleWatchPredicate(base: NSPredicate, type: HKSampleType) async -> NSPredicate {
        // Capture @MainActor value before crossing into the nonisolated HKSourceQuery completion handler.
        let whoopBundles = Self.whoopBundles
        let appleSources: Set<HKSource> = await withCheckedContinuation { continuation in
            let sourceQuery = HKSourceQuery(sampleType: type, samplePredicate: base) { _, sources, _ in
                let valid = sources?.filter { source in
                    source.bundleIdentifier.hasPrefix("com.apple.") &&
                    !whoopBundles.contains(source.bundleIdentifier)
                } ?? []
                continuation.resume(returning: Set(valid))
            }
            self.store.execute(sourceQuery)
        }

        let watchDevicePredicate = HKQuery.predicateForObjects(
            withDeviceProperty: HKDevicePropertyKeyModel, allowedValues: ["Watch"]
        )

        if appleSources.isEmpty {
            return NSCompoundPredicate(andPredicateWithSubpredicates: [base, watchDevicePredicate])
        }

        let sourcePredicate = HKQuery.predicateForObjects(from: appleSources)
        let combinedSource = NSCompoundPredicate(orPredicateWithSubpredicates: [watchDevicePredicate, sourcePredicate])
        return NSCompoundPredicate(andPredicateWithSubpredicates: [base, combinedSource])
    }

    private func hkSamples<T: HKSample>(
        type: HKSampleType,
        predicate: NSPredicate,
        sort: NSSortDescriptor,
        requireWatch: Bool = true
    ) async -> [T] {
        let finalPredicate = requireWatch
            ? await appleWatchPredicate(base: predicate, type: type)
            : predicate
        return await withCheckedContinuation { continuation in
            let q = HKSampleQuery(
                sampleType: type,
                predicate: finalPredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [T]) ?? [])
            }
            store.execute(q)
        }
    }

    private func hkStatistic(
        type: HKQuantityType,
        predicate: NSPredicate,
        options: HKStatisticsOptions,
        requireWatch: Bool = true,
        extract: @escaping (HKStatistics) -> Double?
    ) async -> Double? {
        let finalPredicate = requireWatch
            ? await appleWatchPredicate(base: predicate, type: type)
            : predicate
        return await withCheckedContinuation { continuation in
            let q = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: finalPredicate,
                options: options
            ) { _, stats, _ in
                continuation.resume(returning: stats.flatMap(extract))
            }
            store.execute(q)
        }
    }

    private func hkSum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        predicate: NSPredicate,
        requireWatch: Bool = true
    ) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        return await hkStatistic(type: type, predicate: predicate, options: .cumulativeSum, requireWatch: requireWatch) {
            $0.sumQuantity()?.doubleValue(for: unit)
        }
    }

    private func mockActivityData(for date: Date) -> HKActivitySnapshot {
        let seed = Double(date.timeIntervalSince1970).truncatingRemainder(dividingBy: 1000)
        let steps = 4000 + Int(abs(sin(seed)) * 8000)
        let dist = Double(steps) * 0.75
        let stand = 300.0 + abs(cos(seed)) * 400.0
        let resting = 55.0 + abs(sin(seed * 0.5)) * 15.0
        let avgHR = resting + 15.0 + abs(cos(seed * 0.8)) * 25.0
        
        return HKActivitySnapshot(
            steps: steps,
            distanceMeters: dist,
            fetchedAt: date,
            standTimeMinutes: stand,
            restingHeartRate: resting,
            avgHeartRateWaking: avgHR,
            hrSegments: []
        )
    }

    private func mockWorkoutsData(for date: Date) -> [HKWorkoutSnapshot] {
        let seed = Int(Double(date.timeIntervalSince1970).truncatingRemainder(dividingBy: 10000))
        let cal = Calendar.current

        func snap(_ type: HKWorkoutActivityType, hour: Int, minute: Int = 0, minutes: Double, hr: Double) -> HKWorkoutSnapshot {
            let start = cal.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
            return HKWorkoutSnapshot(
                id: UUID(),
                activityType: type,
                startDate: start,
                endDate: start.addingTimeInterval(minutes * 60),
                averageHeartRate: hr,
                sourceName: "Simulator",
                sourceBundleID: "com.apple.Health"
            )
        }

        switch seed % 10 {
        case 0, 1:
            return []
        case 2:
            return [snap(.running,                       hour: 7,  minute: 0,  minutes: 42, hr: 158)]
        case 3:
            return [snap(.cycling,                       hour: 18, minute: 15, minutes: 65, hr: 138)]
        case 4:
            return [snap(.swimming,                      hour: 8,  minute: 0,  minutes: 38, hr: 126)]
        case 5:
            return [snap(.highIntensityIntervalTraining, hour: 17, minute: 30, minutes: 28, hr: 171)]
        case 6:
            return [snap(.yoga,                          hour: 7,  minute: 15, minutes: 52, hr: 94)]
        case 7:
            return [snap(.functionalStrengthTraining,    hour: 19, minute: 0,  minutes: 55, hr: 124)]
        case 8:
            return [snap(.rowing,                        hour: 6,  minute: 30, minutes: 36, hr: 154)]
        default: // 9 – zwei Workouts
            return [
                snap(.running,                    hour: 7,  minute: 0,  minutes: 35, hr: 162),
                snap(.functionalStrengthTraining, hour: 19, minute: 30, minutes: 45, hr: 118)
            ]
        }
    }
}
