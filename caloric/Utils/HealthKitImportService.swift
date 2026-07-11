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
    
    let sedentaryAvgHR: Double?
    let unrecordedCardioAvgHR: Double?
    let cardioRatio: Double
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
                                        sedentaryAvgHR: nil, unrecordedCardioAvgHR: nil, cardioRatio: 0.0)
    var sleep: HKSleepSnapshot? = nil
    var isAuthorized = false
    /// Most recent VO2max estimate from Apple Health (mL/kg·min). Nil if not available.
    var vo2Max: Double? = nil
    /// Per-day history keyed by "yyyy-MM-dd". Populated for the last 30 days on launch.
    var history: [String: DaySnapshot] = [:]

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
                if jIsWhoop && !bestIsWhoop { best = sorted[j] }
            }
            result.append(best)
        }
        return result
    }

    // MARK: - Activity (steps + distance + stand + HR)

    private func fetchActivityData(for date: Date = Date()) async -> HKActivitySnapshot {
        let cal   = Calendar.current
        let start = cal.startOfDay(for: date)
        let end   = cal.isDateInToday(date) ? Date() : cal.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictStartDate
        )
        // Waking HR window: 6 am → end of period
        let wakeStart = cal.date(bySettingHour: 6, minute: 0, second: 0, of: start) ?? start

        async let steps   = hkSum(.stepCount,              unit: .count(),  predicate: predicate)
        async let dist    = hkSum(.distanceWalkingRunning, unit: .meter(),  predicate: predicate)
        async let stand   = hkSum(.appleStandTime,         unit: .minute(), predicate: predicate)
        async let resting = fetchRestingHeartRate(for: date)
        async let avgHR   = fetchAvgHeartRate(from: wakeStart, to: end)
        
        // Fetch workouts for this date to exclude them from gap analysis
        let workouts = await fetchWorkoutsData(for: date)
        let workoutWindows = workouts.map { DateInterval(start: $0.startDate, end: $0.endDate) }
        
        // Perform Gap Analysis (sedentary vs unrecorded cardio)
        let restHRForAnalysis = await resting ?? 60.0
        let gapAnalysis = await analyzeGapHeartRate(start: wakeStart, end: end, restingHR: restHRForAnalysis, excluding: workoutWindows)

        return await HKActivitySnapshot(
            steps:              Int(steps ?? 0),
            distanceMeters:     dist ?? 0,
            fetchedAt:          date,
            standTimeMinutes:   stand ?? 0,
            restingHeartRate:   resting,
            avgHeartRateWaking: avgHR,
            sedentaryAvgHR:     gapAnalysis.sedentaryHR,
            unrecordedCardioAvgHR: gapAnalysis.cardioHR,
            cardioRatio:        gapAnalysis.cardioRatio
        )
    }

    private func analyzeGapHeartRate(
        start: Date, end: Date, restingHR: Double, excluding windows: [DateInterval]
    ) async -> (cardioRatio: Double, sedentaryHR: Double?, cardioHR: Double?) {
        guard end > start, let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return (0.0, nil, nil)
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples: [HKQuantitySample] = await hkSamples(type: type, predicate: predicate, sort: NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true))
        let unit = HKUnit.count().unitDivided(by: .minute())
        
        let validSamples = samples
            .filter { s in !windows.contains { $0.intersects(DateInterval(start: s.startDate, end: s.endDate)) } }
        
        guard !validSamples.isEmpty else { return (0.0, nil, nil) }
        
        // Schwelle für ungemeldeten Sport: Ruhepuls + 30 bpm
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

    private func fetchRestingHeartRate(for date: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        let cal   = Calendar.current
        let start = cal.startOfDay(for: date)
        let end   = cal.isDateInToday(date) ? Date() : cal.date(byAdding: .day, value: 1, to: start)!
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await hkStatistic(type: type, predicate: pred, options: .discreteAverage) {
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
        return await hkStatistic(type: type, predicate: pred, options: .discreteAverage) {
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
        let samples: [HKCategorySample] = await hkSamples(
            type: sleepType, predicate: predicate, sort: sort
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

    private func hkSamples<T: HKSample>(
        type: HKSampleType,
        predicate: NSPredicate,
        sort: NSSortDescriptor
    ) async -> [T] {
        await withCheckedContinuation { continuation in
            let q = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
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
        extract: @escaping (HKStatistics) -> Double?
    ) async -> Double? {
        await withCheckedContinuation { continuation in
            let q = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
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
        predicate: NSPredicate
    ) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        return await hkStatistic(type: type, predicate: predicate, options: .cumulativeSum) {
            $0.sumQuantity()?.doubleValue(for: unit)
        }
    }
}
