//
//  HealthKitImportService.swift
//  caloric
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
    /// Detailed stages
    let stages: [HKSleepStage]

    var durationSeconds: TimeInterval { end.timeIntervalSince(start) }
    
    var totalAsleepSeconds: TimeInterval {
        stages.filter { $0.type != .awake && $0.type != .inBed }.reduce(0) { $0 + $1.duration }
    }
}

struct HKSleepStage: Sendable, Identifiable {
    let id = UUID()
    let type: HKSleepType
    let start: Date
    let end: Date
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

enum HKSleepType: String, Sendable, CaseIterable {
    case awake, rem, core, deep, inBed
    
    init(hkValue: Int) {
        switch hkValue {
        case HKCategoryValueSleepAnalysis.awake.rawValue: self = .awake
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: self = .rem
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: self = .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: self = .deep
        case HKCategoryValueSleepAnalysis.inBed.rawValue: self = .inBed
        default: self = .core
        }
    }
}

struct HKHeartRateSample: Identifiable, Sendable {
    let id = UUID()
    let bpm: Double
    let date: Date
}

// MARK: - HealthKitImportService

@Observable
@MainActor
final class HealthKitImportService {

    // MARK: - Historical Cache

    struct DaySnapshot: Sendable {
        let activity: HKActivitySnapshot
        let workouts: [HKWorkoutSnapshot]
        let sleep: HKSleepSnapshot?
    }

    // MARK: State consumed by views

    var workouts: [HKWorkoutSnapshot] = []
    var activity   = HKActivitySnapshot(steps: 0, distanceMeters: 0, fetchedAt: Date(),
                                        standTimeMinutes: 0, restingHeartRate: nil, avgHeartRateWaking: nil,
                                        hrSegments: [])
    var sleep: HKSleepSnapshot? = nil
    var recentHR: [HKHeartRateSample] = []
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

    // MARK: - SwiftData Cache (Note: Sleep detailed stages not cached for simplicity here, can be added to model if needed)

    func loadCachedHistory() {
        guard let ctx = modelContext else { return }
        let entries = (try? ctx.fetch(FetchDescriptor<DayCacheEntry>())) ?? []
        for entry in entries {
            // Re-map to include sleep if we had it in the old model (needs migration or handling)
            // For now, history uses simple duration-based sleep from cache if available
            history[entry.dateKey] = entry.toDaySnapshot()
        }
    }

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
        async let h = fetchRecentHeartRate(limit: 50)
        
        let (wData, aData, sData, vData, hData) = await (w, a, s, v, h)
        workouts = wData
        activity = aData
        sleep    = sData
        vo2Max   = vData
        recentHR = hData
    }

    /// Fetches and caches activity + workouts + sleep for the last `days` days.
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
                    async let s = self.fetchSleepData(for: date)
                    let (activity, workouts, sleep) = await (a, w, s)
                    return (key, DaySnapshot(activity: activity, workouts: workouts, sleep: sleep))
                }
            }
            for await (key, snapshot) in group {
                history[key] = snapshot
            }
        }
    }

    // MARK: - Recent Heart Rate (Log)

    private func fetchRecentHeartRate(limit: Int = 50) async -> [HKHeartRateSample] {
        if isSimulator { return mockHRLog() }
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: nil, limit: limit, sortDescriptors: [sort]) { _, res, _ in
                continuation.resume(returning: (res as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
        
        let unit = HKUnit(from: "count/min")
        return samples.map { HKHeartRateSample(bpm: $0.quantity.doubleValue(for: unit), date: $0.endDate) }
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

    private func fetchVO2Max() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return nil }
        let cal   = Calendar.current
        let end   = Date()
        let start = cal.date(byAdding: .day, value: -90, to: end) ?? end
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await hkStatistic(type: type, predicate: pred, options: .discreteAverage, requireWatch: false) {
            $0.averageQuantity()?.doubleValue(for: HKUnit(from: "ml/kg*min"))
        }
    }

    // MARK: - Sleep Analysis

    private func fetchSleepData(for date: Date = Date()) async -> HKSleepSnapshot? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let cal = Calendar.current
        
        let startOfTarget = cal.startOfDay(for: date)
        let windowStart = cal.date(bySettingHour: 18, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: startOfTarget)!)!
        let windowEnd = cal.date(bySettingHour: 14, minute: 0, second: 0, of: startOfTarget)!

        if isSimulator { return mockSleepData(for: date) }

        let predicate = HKQuery.predicateForSamples(
            withStart: windowStart, end: windowEnd, options: .strictStartDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples: [HKCategorySample] = await hkSamples(
            type: sleepType, predicate: predicate, sort: sort, requireWatch: true
        )

        let stages = samples.map { HKSleepStage(type: HKSleepType(hkValue: $0.value), start: $0.startDate, end: $0.endDate) }
        
        guard let start = stages.map(\.start).min(),
              let end   = stages.map(\.end).max()
        else { return nil }

        return HKSleepSnapshot(start: start, end: end, stages: stages)
    }

    // MARK: - Observer Queries (Live Sync)

    private func startObservers() {
        stopObservers()

        let observedTypes: [HKSampleType] = [
            .workoutType(),
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
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
        } else if type.identifier == HKQuantityTypeIdentifier.heartRate.rawValue {
            recentHR = await fetchRecentHeartRate(limit: 50)
        } else if type.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue {
            sleep = await fetchSleepData()
        }
    }

    private func stopObservers() {
        activeObservers.forEach { store.stop($0) }
        activeObservers.removeAll()
    }

    // MARK: - HealthKit Query Helpers

    private func appleWatchPredicate(base: NSPredicate, type: HKSampleType) async -> NSPredicate {
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

    // MARK: - Mocks

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
    
    private func mockHRLog() -> [HKHeartRateSample] {
        var log = [HKHeartRateSample]()
        let now = Date()
        for i in 0..<40 {
            log.append(HKHeartRateSample(bpm: 60 + Double(i % 10) * 5, date: now.addingTimeInterval(Double(-i * 300))))
        }
        return log
    }
    
    private func mockSleepData(for date: Date) -> HKSleepSnapshot {
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 23, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: date)!)!
        var stages = [HKSleepStage]()
        var current = start
        let types: [HKSleepType] = [.inBed, .awake, .rem, .core, .deep, .core, .rem, .core, .deep, .core, .awake]
        for t in types {
            let duration: TimeInterval = t == .awake ? 600 : (t == .rem ? 1800 : (t == .deep ? 2400 : 3600))
            stages.append(HKSleepStage(type: t, start: current, end: current.addingTimeInterval(duration)))
            current = current.addingTimeInterval(duration)
        }
        return HKSleepSnapshot(start: start, end: current, stages: stages)
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
        case 0, 1: return []
        case 2: return [snap(.running, hour: 7, minutes: 42, hr: 158)]
        default: return [snap(.cycling, hour: 18, minutes: 65, hr: 138)]
        }
    }
}
