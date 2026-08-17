//
//  DashboardView.swift
//  caloric
//
//  Übersichtsseite: Kalorienring + Chart + einblendbare Anpassen-Seitenleiste
//

import SwiftUI
import Charts
import HealthKit
import SwiftData
import Combine   // Timer.publish, für die Uhr hinter nowFraction

struct DashboardView: View {
    let accentBlue: Color
    let language: String
    let userAge: Int
    let selectedGender: String?
    let noConditionText: String
    let femaleText: String
    
    @Binding var accountUsername: String
    @Binding var birthDate: Date
    @Binding var weightText: String
    @Binding var weightUnit: String
    @Binding var heightText: String
    @Binding var heightUnit: String
    @Binding var bodyFatText: String
    @Binding var knowsBodyFat: Bool?
    @Binding var sleepHours: Double
    @Binding var selectedConditions: Set<String>
    @Binding var metabolismFactor: Double
    @Binding var selectedDate: Date
    /// Lets the info sheet hand off to Meine Daten, where the same sources are
    /// listed in full.
    @Binding var selectedTab: Int
    
    @State private var editingField: String? = nil
    @State private var showProfileSidebar = false
    @State private var showActivityBreakdown = false
    @State private var ringProgress: Double = 0
    @State private var animatedBurn: Double = 0
    /// Mittel der 14 Tage vor dem gewählten — färbt den Ring ein.
    /// Gecached, weil die Berechnung pro Tag eine volle NEAT/EAT-Auswertung
    /// kostet und eine computed property bei jedem Render 14-mal liefe.
    @State private var trailingAverage: Double? = nil
    /// Same basis, seven days — feeds the optional "vs. Ø 7 Tage" tile.
    @State private var sevenDayAverage: Double? = nil
    /// Average steps over the same seven days, for the narrative's insights.
    @State private var sevenDayAverageSteps: Int? = nil
    @State private var sevenDayCount: Int = 0

    /// Which KPI tiles the user keeps on the dashboard, in order.
    /// Stored as raw values so adding a case never invalidates a saved layout —
    /// unknown entries are simply dropped on read.
    @AppStorage("dashboard.kpiTiles") private var kpiTilesRaw: String = DashboardKPI.defaultRaw
    @State private var isEditingKPIs = false
    @State private var jiggleUp = false
    @State private var showKPIPicker = false
    /// Which tile is currently explaining itself, if any.
    @State private var kpiInfoShown: DashboardKPI? = nil
    /// Day picked in that tile's history chart, if the user is touching it.
    @State private var kpiChartSelection: Date? = nil
    /// One-time move: PAL was pulled out of the day narrative and belongs on
    /// the dashboard instead. Changing the default alone would never reach a
    /// layout the user has already saved.
    @AppStorage("dashboard.kpiPalMigrated") private var kpiPalMigrated = false
    /// Where the weight behind the BMR comes from — typed in, or whatever
    /// Apple Health last recorded.
    @AppStorage("settings.weightSource") private var weightSource = WeightSource.manual.rawValue
    /// Optional target for the day's burn. Zero means no goal, and the ring
    /// falls back to comparing the day against its own 14-day average.
    @AppStorage("settings.dailyGoalKcal") private var dailyGoalKcal: Double = 0
    @State private var exportURL: URL? = nil
    @State private var editWeightKg: Int = 70
    @State private var editWeightLb: Int = 154
    @State private var editHeightCm: Int = 170
    @State private var editHeightFeet: Int = 5
    @State private var editHeightInches: Int = 9
    @State private var showBodyFatHelp = false
    @State private var showRefreshBadge = false
    @State private var thyroidCondition: String? = nil
    @State private var thyroidWellControlled: Bool? = nil
    @State private var selectedHypoSymptoms: Set<String> = []
    @State private var selectedHyperSymptoms: Set<String> = []
    @State private var hasPCOS: Bool? = nil
    @State private var pcosInsulinResistance: Bool? = nil
    @State private var selectedPCOSSymptoms: Set<String> = []
    @State private var nameDraft: String = ""
    @State private var showResetConfirmation = false
    @State private var showCalendarPicker = false
    /// 0 = full header, 1 = collapsed to the pinned row. Driven by scrolling.
    @State private var headerCollapseProgress: Double = 0
    /// Drives every time-dependent figure — see `nowFraction`.
    @State private var clockTick = Date()

    // Tagesvergleich — nur auf Knopfdruck
    @State private var deepDiveStore = DayNarrativeStore()
    @State private var showDeepDive = false
    @State private var deepDive: DayNarrativeService.DeepDive? = nil
    @State private var deepDiveIsLoading = false
    @State private var deepDiveError: String? = nil
    /// Day the shown text belongs to. Kept per day rather than per
    /// fingerprint: the numbers move all afternoon, and re-billing a long
    /// generation every time the sheet is reopened is exactly what the button
    /// exists to avoid. Asking again is one tap away.
    @State private var deepDiveDateKey: String? = nil

    @State private var showCalorieDetail = false
    @Query private var profiles: [UserProfile]
    @Environment(JournalStore.self)           private var store
    @Environment(HealthKitImportService.self) private var healthKit
    
    
    
    /// The stored record every screen reads its language from.
    private var storedProfile: UserProfile? {
        profiles.first(where: { $0.isOnboardingCompleted }) ?? profiles.first
    }

    /// Written once when the panel opens.
    ///
    /// As a computed property this rebuilt the file on every render of the
    /// panel, which puts a disk write behind a scroll — and ShareLink needs
    /// the URL before the tap, so it cannot wait for one either.
    private func prepareExport() {
        guard !healthKit.history.isEmpty else {
            exportURL = nil
            return
        }
        exportURL = HistoryExport.writeCSV(history: healthKit.history)
    }

    /// Pulls the weight from Health into the field the calculations read.
    ///
    /// The manual entry is not overwritten in place until the source is set to
    /// Health, and a value that already matches is left alone — otherwise the
    /// write would loop through onChange back into itself.
    private func syncWeightFromHealth() {
        guard weightSource == WeightSource.health.rawValue,
              let kg = healthKit.bodyMassKg, kg > 0 else { return }
        let shown = weightUnit == "kg" ? kg : kg / 0.453592
        let text  = String(format: "%.1f", shown)
        if weightText != text { weightText = text }
    }

    private var ringSize: CGFloat { LayoutMetrics.ringSize }
    
    private var topSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 50
    }
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase)  private var scenePhase
    private var isDark: Bool { colorScheme == .dark }
    private var cardAlpha: Double { isDark ? 0.17 : 0.07 }
    private var controlAlpha: Double { isDark ? 0.22 : 0.10 }
    private var borderAlpha: Double { isDark ? 0.35 : 0.15 }
    
    private var heightInCm: Double {
        if heightUnit == "cm" {
            return Double(heightText.replacingOccurrences(of: ",", with: ".")) ?? 0
        } else {
            let parts = heightText.components(separatedBy: CharacterSet(charactersIn: "'\"")).compactMap { Int($0) }
            let feet = parts.first ?? 5
            let inches = parts.dropFirst().first ?? 9
            return Double(feet * 12 + inches) * 2.54
        }
    }
    
    private var computedThyroidFactor: Double {
        guard let cond = thyroidCondition, cond != "none" else { return 1.0 }
        guard thyroidWellControlled == false else { return 1.0 }
        if cond == "hypo" {
            let count = selectedHypoSymptoms.count
            let hasFatigue = selectedHypoSymptoms.contains(t.hypoSymptomFatigue)
            let hasWeightGain = selectedHypoSymptoms.contains(t.hypoSymptomWeightGain)
            if count >= 4 || (hasFatigue && hasWeightGain) { return 0.85 }
            if count >= 2 { return 0.92 }
            if count >= 1 { return 0.97 }
        } else {
            let count = selectedHyperSymptoms.count
            let hasWeightLoss = selectedHyperSymptoms.contains(t.hyperSymptomWeightLoss)
            if count >= 3 || hasWeightLoss { return 1.15 }
            if count >= 1 { return 1.07 }
        }
        return 1.0
    }
    
    private var computedPCOSFactor: Double {
        guard selectedGender == femaleText, hasPCOS == true else { return 1.0 }
        if pcosInsulinResistance == true { return 0.85 }
        let count = selectedPCOSSymptoms.count
        let hasBlocked = selectedPCOSSymptoms.contains(t.pcosSymptomBlocked)
        let hasCarbFatigue = selectedPCOSSymptoms.contains(t.pcosSymptomCarbFatigue)
        if count >= 3 || (hasBlocked && hasCarbFatigue) { return 0.85 }
        return 1.0
    }
    
    private var computedConditionFactor: Double {
        let tf = computedThyroidFactor
        let pf = computedPCOSFactor
        return abs(tf - 1.0) >= abs(pf - 1.0) ? tf : pf
    }
    
    private var conditionQuestionnaireDone: Bool {
        guard thyroidCondition != nil else { return false }
        if thyroidCondition != "none" { guard thyroidWellControlled != nil else { return false } }
        if selectedGender == femaleText {
            guard hasPCOS != nil else { return false }
            if hasPCOS == true { guard pcosInsulinResistance != nil else { return false } }
        }
        return true
    }
    
    private var metabolismSliderRange: ClosedRange<Double> {
        if selectedConditions.contains(t.hyperthyroidism) { return 1.0...1.3 }
        if !selectedConditions.isEmpty && !selectedConditions.contains(noConditionText) { return 0.7...1.0 }
        return 0.7...1.3
    }
    
    private var t: Translations { Translations(language: language) }
    
    private var weightInKg: Double {
        MeasurementParsing.weightKg(text: weightText, unit: weightUnit)
    }

    private var bodyFatPercent: Double {
        MeasurementParsing.percent(bodyFatText)
    }

    // Reactive BMR — recomputes whenever the user edits weight, bodyFat, conditions, or sleep.
    private var activeFinalBMR: Double {
        BMRCalculationService.finalBMR(
            weightKg:         weightInKg,
            bodyFatPercent:   bodyFatPercent,
            age:              userAge,
            metabolismFactor: metabolismFactor,
            sleepHours:       sleepHours
        )
    }

    private var hourlyBMR: Double {
        BMRCalculationService.hourlyRate(finalBMR: activeFinalBMR, sleepHours: sleepHours)
    }
    
    private var calorieSlots: [CalorieSlot] {
        let now = nowFraction
        let dayStart = Calendar.current.startOfDay(for: selectedDate)
        /// How far into the day the drawing goes: the clock today, else midnight.
        let dayCutoff = isSelectedFuture ? 0.0 : (isSelectedToday ? now : 24.0)

        // Each session carries its own two figures rather than a flat rate
        // across all workout minutes — with two sessions of different
        // intensity, the flat rate credited the calmer one too much.
        // Ends are clamped to midnight; a session running past it spreads its
        // energy over the part that belongs to this day.
        let sessions: [(start: Double, end: Double, during: Double, after: Double)] =
            (healthKit.isAuthorized && !isSelectedFuture ? activityResult.workoutDetails : [])
                .compactMap { d in
                    let s = d.startDate.timeIntervalSince(dayStart) / 3600.0
                    let e = min(d.endDate.timeIntervalSince(dayStart) / 3600.0, 24.0)
                    guard e > s else { return nil }
                    return (s, e, d.duringKcal, d.afterburnKcal)
                }

        // NEAT was missing from this chart entirely — the bars showed the
        // resting share plus workouts and therefore summed to a few hundred
        // kcal below the day the ring reports. It is spread here together with
        // the digestion and caffeine bonuses, over the waking, non-workout
        // time that has actually elapsed: that is precisely the window the
        // NEAT model itself budgets over, and keeping it out of the workout
        // windows is what stops it being counted twice against EAT.
        let neatKcal = healthKit.isAuthorized && !isSelectedFuture ? activityResult.neatKcal : 0.0
        let bonusKcal = isSelectedFuture
            ? 0.0
            : (tdeeResult.tefKcal + tdeeResult.koffeinBonus) * (isSelectedToday ? now / 24.0 : 1.0)
        let activeToSpread = neatKcal + bonusKcal

        let hours = Array(stride(from: 0.0, to: 24.0, by: 0.5))

        /// Hours of each slot spent awake, elapsed and outside a workout.
        let awakeShares: [Double] = hours.map { hour in
            let slotEnd = hour + 0.5
            let cutoff  = min(slotEnd, dayCutoff)
            let start   = max(hour, sleepHours)
            var share   = max(0, cutoff - start)
            for s in sessions {
                share -= max(0, min(cutoff, s.end) - max(start, s.start))
            }
            return max(0, share)
        }
        let awakeTotal = awakeShares.reduce(0, +)

        return hours.enumerated().map { index, hour in
            let slotEnd = hour + 0.5
            let sleeping = hour < sleepHours
            let isFuture = isSelectedFuture || (isSelectedToday && hour >= now)

            var workoutKcal = 0.0
            var afterburnKcal = 0.0
            var isWorkout = false
            for s in sessions {
                let overlap = max(0, min(slotEnd, s.end) - max(hour, s.start))
                if overlap > 0 {
                    isWorkout = true
                    workoutKcal += s.during * (overlap / (s.end - s.start))
                }
                afterburnKcal += Self.afterburnShare(
                    session: s, slotStart: hour, slotEnd: slotEnd, dayCutoff: dayCutoff
                )
            }

            let activeKcal = awakeTotal > 0 ? activeToSpread * (awakeShares[index] / awakeTotal) : 0

            var mult: Double = sleeping ? 0.88 : 1.0
            if !sleeping {
                switch hour {
                case sleepHours..<(sleepHours + 1.5): mult = 0.94
                case 8.0..<10.0:  mult = 1.12
                case 12.0..<13.5: mult = 1.06
                case 14.0..<15.5: mult = 0.96
                case 18.0..<20.5: mult = 1.14
                case 21.5..<23.5: mult = 0.90
                default:          mult = 1.0
                }
            }
            return CalorieSlot(
                hour: hour,
                calories: hourlyBMR * 0.5 * mult,
                activeKcal: activeKcal,
                workoutKcal: workoutKcal,
                afterburnKcal: afterburnKcal,
                isSleep: sleeping,
                isWorkout: isWorkout,
                isFuture: isFuture
            )
        }
    }
    
    // MARK: - Nachbrenneffekt (EPOC)

    /// Hours over which the afterburn is drawn before it is treated as spent.
    private static let epocSpanHours = 3.0
    /// Time constant of the decay. At τ = 1 h about 95 % lands inside the span.
    private static let epocTauHours = 1.0

    /// ∫ exp(−(t − origin)/τ) dt between `a` and `b`.
    private static func decayIntegral(origin: Double, from a: Double, to b: Double) -> Double {
        guard b > a else { return 0 }
        let tau = epocTauHours
        return tau * (exp(-(a - origin) / tau) - exp(-(b - origin) / tau))
    }

    /// How much of a session's afterburn falls into one half hour.
    ///
    /// EPOC decays exponentially once the session ends. The window is clamped
    /// to midnight and, today, to the current time — the ring credits a
    /// session's afterburn the moment it ends, so spreading it across hours
    /// that have not happened yet would leave the bars summing to less than
    /// the ring above them. Normalising over whatever window is available
    /// keeps the two in step; a session that has only just finished therefore
    /// shows its afterburn concentrated, and it spreads out as the day runs on.
    private static func afterburnShare(
        session: (start: Double, end: Double, during: Double, after: Double),
        slotStart: Double,
        slotEnd: Double,
        dayCutoff: Double
    ) -> Double {
        guard session.after > 0 else { return 0 }

        let windowEnd = min(session.end + epocSpanHours, min(24.0, dayCutoff))
        guard windowEnd > session.end else {
            // Nowhere to spread it yet: keep it in the half hour the session
            // ended in rather than dropping it and undershooting the ring.
            return (session.end >= slotStart && session.end < slotEnd) ? session.after : 0
        }

        let whole = decayIntegral(origin: session.end, from: session.end, to: windowEnd)
        guard whole > 0 else { return 0 }
        let part = decayIntegral(origin: session.end,
                                 from: max(slotStart, session.end),
                                 to:   min(slotEnd, windowEnd))
        return session.after * (part / whole)
    }

    /// Hour of day as a fraction, read from `clockTick` rather than `Date()`.
    ///
    /// Everything time-dependent on this screen hangs off this one value — the
    /// elapsed BMR, the "now" line in the chart, how far a partial day has
    /// run. Reading the wall clock directly made all of it freeze at whatever
    /// moment the view last happened to render, so a dashboard left open drifted
    /// quietly out of date. Tied to state, a tick brings the whole page along.
    private var nowFraction: Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: clockTick)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0
    }
    
    private var bmrBurnedSoFar: Double {
        calorieSlots.filter { $0.hour < nowFraction }.reduce(0) { $0 + $1.calories }
    }
    
    private var burnedSoFar: Double {
        let activeKcal = healthKit.isAuthorized ? activityResult.totalActiveKcal : 0
        let fractionalBonuses = (tdeeResult.tefKcal + tdeeResult.koffeinBonus) * (nowFraction / 24.0)
        return bmrBurnedSoFar + activeKcal + fractionalBonuses
    }
    
    private var tdeeResult: TDEECalculationService.TDEEResult {
        TDEECalculationService.calculate(
            bmrStandard: activeFinalBMR,
            inputs: store.journalInputs(for: selectedDate),
            isFemale: selectedGender == femaleText
        )
    }
    
    private var activityResult: ActivityCalculationService.ActivityResult {
        let act = selectedActivity
        return ActivityCalculationService.calculate(
            steps:            act.steps,
            nonWorkoutSteps:  act.nonWorkoutSteps,
            nonWorkoutDistanceMeters: act.nonWorkoutDistanceMeters,
            standTimeMinutes: act.standTimeMinutes,
            nonWorkoutStandMinutes: act.nonWorkoutStandMinutes,
            restingHR:        act.restingHeartRate,
            hrSegments:       act.hrSegments,
            wakeMinuteOfDay:  act.wakeMinuteOfDay,
            vo2Max:           healthKit.vo2Max,
            workouts:         selectedWorkouts,
            weightKg:         weightInKg,
            age:              userAge,
            isMale:           selectedGender != femaleText,
            sleepHours:       sleepHours,
            bmrDynamisch:     tdeeResult.bmrDynamisch,
            referenceDate:    selectedDate
        )
    }
    
    // MARK: - Tageserklärung

    /// Assembles everything the narrative may mention. Pure computation — the
    /// numbers are finished here and the model only puts them into words.
    private var dayDeltaSummary: DayDeltaSummary {
        let prevDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!

        // Both days cut at the same point on the clock. Against a finished
        // previous day every morning would read as a collapse, and the text
        // would keep explaining a gap that is only the time of day.
        let today = componentsSoFar(for: selectedDate)
        let prev  = componentsAtSameTime(
            dayComponents(for: prevDate),
            on: prevDate,
            workouts: previousActivityResult.workoutDetails
        )
        // Derived from exactly these two figures rather than taken from the
        // KPI tile: that one projects both days to midnight, and a percentage
        // computed on one basis next to totals from another is the kind of
        // mismatch the text would faithfully repeat.
        let percent = prev.total > 0 ? (today.total - prev.total) / prev.total * 100 : 0

        let components: [DayDeltaSummary.ComponentDelta] = [
            .init(key: "bmr",      todayKcal: today.bmr,      previousKcal: prev.bmr),
            .init(key: "neat",     todayKcal: today.neat,     previousKcal: prev.neat),
            .init(key: "eat",      todayKcal: today.eat,      previousKcal: prev.eat),
            .init(key: "tef",      todayKcal: today.tef,      previousKcal: prev.tef),
            .init(key: "caffeine", todayKcal: today.caffeine, previousKcal: prev.caffeine)
        ]

        // NEAT sub-parts, previous day trimmed to the same slice as its total.
        let todayNeat = activityResult.neatBreakdown
        let prevNeat  = previousActivityResult.neatBreakdown
        let share     = elapsedActivityFraction
        let neatBreakdown: [DayDeltaSummary.ComponentDelta] = [
            .init(key: "steps",     todayKcal: todayNeat.neatSteps, previousKcal: prevNeat.neatSteps * share),
            .init(key: "standing",  todayKcal: todayNeat.neatStand, previousKcal: prevNeat.neatStand * share),
            .init(key: "heartRate", todayKcal: todayNeat.neatHR,    previousKcal: prevNeat.neatHR * share)
        ]

        // BMR only moves for a reason — illness or cycle. Without one, any delta
        // it shows is modelling noise and must not become the headline.
        let prevTDEE = TDEECalculationService.calculate(
            bmrStandard: activeFinalBMR,
            inputs: store.journalInputs(for: prevDate),
            isFemale: selectedGender == femaleText
        )
        let bmrFactorsChanged =
            abs(tdeeResult.krankheitsFaktor - prevTDEE.krankheitsFaktor) > 0.001 ||
            abs(tdeeResult.zyklusFaktor - prevTDEE.zyklusFaktor) > 0.001

        let prevSnapshot = healthKit.history[HealthKitImportService.dateKey(prevDate)]

        return DayDeltaSummary(
            dateKey: HealthKitImportService.dateKey(selectedDate),
            percentVsPreviousDay: percent,
            todayTotalKcal: today.total,
            previousTotalKcal: prev.total,
            isPartialDay: isSelectedToday,
            elapsedFractionOfWakingDay: elapsedActivityFraction,
            components: components,
            neatBreakdown: neatBreakdown,
            bmrFactorsChanged: bmrFactorsChanged,
            context: DayDeltaSummary.Context(
                steps: selectedActivity.steps,
                // Raw counts get the same treatment as the kcal they drive.
                // Steps and standing minutes are day totals with no intraday
                // resolution, so they are scaled; workout minutes have real
                // timestamps and are clipped exactly.
                stepsPrevious: Int((Double(prevSnapshot?.activity.steps ?? 0) * share).rounded()),
                standMinutes: selectedActivity.standTimeMinutes,
                standMinutesPrevious: (prevSnapshot?.activity.standTimeMinutes ?? 0) * share,
                workoutMinutes: selectedWorkouts.reduce(0.0) { $0 + $1.duration } / 60.0,
                workoutMinutesPrevious: minutesFromSessions(prevSnapshot?.workouts ?? [],
                                                            on: prevDate, before: nowFraction),
                sleepHours: sleepHours,
                foodLoggedToday: hasLoggedFood(on: selectedDate),
                foodLoggedPrevious: hasLoggedFood(on: prevDate)
            ),
            weekly: narrativeWeekly,
            highlights: narrativeHighlights,
            goalKcal: dailyGoalKcal > 0 ? dailyGoalKcal : nil
        )
    }

    /// How the day stands against the last seven, when there are enough of them.
    private var narrativeWeekly: DayDeltaSummary.Weekly? {
        guard let average = sevenDayAverage, average > 0,
              let steps = sevenDayAverageSteps else { return nil }
        return DayDeltaSummary.Weekly(
            // averageKcal already comes from comparableTotal, so it covers the
            // same hours as today. The step average does not, and left raw it
            // would put a morning's steps against seven whole days.
            averageKcal: average,
            percentVsAverage: (displayBurnedSoFar - average) / average * 100,
            averageSteps: Int((Double(steps) * elapsedActivityFraction).rounded()),
            daysCounted: sevenDayCount
        )
    }

    /// Derived figures the narrative may quote. Computed here so the model
    /// never has to divide anything itself.
    private var narrativeHighlights: DayDeltaSummary.Highlights {
        let parts = componentsSoFar(for: selectedDate)
        let steps = selectedActivity.steps
        return DayDeltaSummary.Highlights(
            activeSharePercent: parts.total > 0 ? (parts.neat + parts.eat) / parts.total * 100 : 0,
            afterburnKcal: afterburnKcalToday,
            kcalPerThousandSteps: steps > 0 ? parts.neat / Double(steps) * 1000 : 0,
            wakingHours: wakingHoursElapsed
        )
    }

    /// TEF is derived from logged macros, so a day without entries yields 0 —
    /// indistinguishable from "ate nothing" unless the fact is passed along.
    private func hasLoggedFood(on date: Date) -> Bool {
        let entry = store.entry(for: date)
        let byMeal = [entry.proteinByMeal, entry.carbsByMeal, entry.fatByMeal]
        return byMeal.contains { $0.values.contains { $0 > 0 } }
    }

    /// Switching days must not leave the previous day's comparison behind.
    @MainActor
    private func resetDeepDive() {
        deepDive = nil
        deepDiveDateKey = nil
        deepDiveError = nil
    }

    /// Generates the long comparison. Called when the sheet opens without a
    /// text for this day, and again whenever the user asks for a fresh one.
    @MainActor
    private func loadDeepDive(force: Bool = false) async {
        let key = HealthKitImportService.dateKey(selectedDate)
        if !force, deepDive != nil, deepDiveDateKey == key { return }
        if deepDiveIsLoading { return }

        // Survives a restart, so yesterday's comparison is never paid for
        // twice.
        if !force, let cached = deepDiveStore.deepDive(for: key) {
            deepDive = cached
            deepDiveDateKey = key
            deepDiveError = nil
            return
        }

        deepDiveIsLoading = true
        deepDiveError = nil
        if force { deepDive = nil }
        defer { deepDiveIsLoading = false }

        do {
            let result = try await DayNarrativeService.deepDive(
                dayDeltaSummary,
                language: language,
                name: accountUsername
            )
            withAnimation(.easeInOut(duration: 0.25)) {
                deepDive = result
            }
            deepDiveDateKey = key
            deepDiveStore.store(result, for: key)
        } catch {
            print("DayDeepDive failed: \(error.localizedDescription)")
            deepDiveError = error.localizedDescription
        }
    }

    /// How full the ring is drawn.
    ///
    /// Without a goal the ring fills against the day's own projection, so a
    /// finished day always ends full — it shows progress through the day, not
    /// achievement. A goal replaces that reference with a fixed line, which is
    /// the only thing that makes a full ring mean something.
    ///
    /// The tint is not touched either way: that still comes from the 14-day
    /// average, and two different meanings on one ring would be one too many.
    private var burnProgress: Double {
        let target = dailyGoalKcal > 0 ? dailyGoalKcal : todayProjected
        guard target > 0 else { return 0 }
        return min(1.0, burnedSoFar / target)
    }
    
    private var isSelectedToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    private var isSelectedFuture: Bool { selectedDate > Calendar.current.startOfDay(for: Date()) }
    
    private var selectedActivity: HKActivitySnapshot {
        if isSelectedToday { return healthKit.activity }
        let key = HealthKitImportService.dateKey(selectedDate)
        return healthKit.history[key]?.activity ?? healthKit.activity
    }
    
    private var selectedWorkouts: [HKWorkoutSnapshot] {
        if isSelectedToday { return healthKit.workouts }
        let key = HealthKitImportService.dateKey(selectedDate)
        return healthKit.history[key]?.workouts ?? []
    }
    
    private var displayBurnedSoFar: Double {
        if isSelectedToday {
            return burnedSoFar
        } else if isSelectedFuture {
            return 0
        } else {
            return dayComponents(for: selectedDate).total
        }
    }
    
    private var displayBurnProgress: Double {
        if isSelectedToday {
            return burnProgress
        } else if isSelectedFuture {
            return 0
        } else if dailyGoalKcal > 0 {
            // A past day against the goal, not automatically full: with a line
            // to reach, "finished" and "reached" stop being the same thing.
            return min(1.0, dayComponents(for: selectedDate).total / dailyGoalKcal)
        } else {
            return 1.0
        }
    }

    // MARK: - Ring-Einfärbung nach 14-Tage-Schnitt

    /// Ab dieser relativen Abweichung ist die Rampe ausgereizt.
    ///
    /// ±15 %, nicht ±20 %: bei der weiteren Spanne blieben normale Tage im
    /// mittleren Drittel der Skala hängen und sahen alle gleich aus. Mit ±15 %
    /// trennt schon eine Abweichung von zwei Prozentpunkten zwei Tage sichtbar.
    private static let ringDeviationSpan = 0.15

    /// Wo der gewählte Tag gegenüber seinem 14-Tage-Schnitt steht, 0…1.
    /// 0.5 heißt "auf dem Schnitt" — auch dann, wenn noch kein Schnitt vorliegt.
    private var ringPosition: Double {
        guard !isSelectedFuture, let average = trailingAverage, average > 0 else { return 0.5 }
        let relative = (displayBurnedSoFar - average) / average
        let span = Self.ringDeviationSpan
        return min(max((relative + span) / (2 * span), 0), 1)
    }

    /// Ein vergangener Tag so, wie er zur aktuellen Uhrzeit dagestanden hätte.
    ///
    /// Der Ring zeigt heute die bisher verbrannten Kalorien. Gegen volle
    /// Vortage gerechnet stünde jeder Vormittag zwangsläufig weit unter dem
    /// Schnitt. Die Komponenten werden deshalb genauso skaliert wie in
    /// `previousValue(for:)`, damit beide Seiten dieselbe Tagesscheibe meinen.
    private func comparableTotal(_ c: DayComponents) -> Double {
        componentsAtSameTime(c).total
    }

    /// The same slice, component by component.
    ///
    /// `comparableTotal` only ever needed the sum; the day comparison needs
    /// the parts, because it says *which* of them explains the difference.
    /// Both go through here so the two can never drift apart.
    ///
    /// Sessions are clipped by their real timestamps where they are available:
    /// scaling a past day's EAT by the elapsed share would credit a third of
    /// an evening workout to a morning, which is the one comparison this text
    /// is most likely to be asked about. Steps and standing minutes have no
    /// intraday resolution, so they keep the proportional treatment.
    private func componentsAtSameTime(
        _ c: DayComponents,
        on date: Date? = nil,
        workouts: [ActivityCalculationService.WorkoutDetail] = []
    ) -> DayComponents {
        guard isSelectedToday else { return c }
        let bmrRatio = tdeeResult.bmrDynamisch > 0 ? bmrBurnedSoFar / tdeeResult.bmrDynamisch : 1
        let active   = elapsedActivityFraction
        let clock    = nowFraction / 24.0

        let eat: Double
        if let date, !workouts.isEmpty {
            eat = kcalFromSessions(workouts, on: date, before: nowFraction)
        } else {
            eat = c.eat * active
        }

        return DayComponents(
            bmr:      c.bmr * bmrRatio,
            neat:     c.neat * active,
            eat:      eat,
            tef:      c.tef * clock,
            caffeine: c.caffeine * clock
        )
    }

    /// How many workout minutes a day had accumulated by a given hour.
    private func minutesFromSessions(
        _ workouts: [HKWorkoutSnapshot],
        on date: Date,
        before hour: Double
    ) -> Double {
        guard isSelectedToday else {
            return workouts.reduce(0.0) { $0 + $1.duration } / 60.0
        }
        let dayStart = Calendar.current.startOfDay(for: date)
        return workouts.reduce(0.0) { sum, w in
            let start = w.startDate.timeIntervalSince(dayStart) / 3600.0
            let end   = w.endDate.timeIntervalSince(dayStart) / 3600.0
            return sum + max(0, min(hour, end) - start) * 60.0
        }
    }

    /// What a day's sessions had cost by a given hour.
    ///
    /// A session straddling the cutoff contributes the share of itself that
    /// had happened; its afterburn only counts once it is over, since EPOC
    /// cannot precede the session that owes it.
    private func kcalFromSessions(
        _ details: [ActivityCalculationService.WorkoutDetail],
        on date: Date,
        before hour: Double
    ) -> Double {
        let dayStart = Calendar.current.startOfDay(for: date)
        return details.reduce(0.0) { sum, d in
            let start = d.startDate.timeIntervalSince(dayStart) / 3600.0
            let end   = d.endDate.timeIntervalSince(dayStart) / 3600.0
            guard end > start else { return sum }
            let share = min(1, max(0, (min(hour, end) - start) / (end - start)))
            return sum + d.duringKcal * share + (hour >= end ? d.afterburnKcal : 0)
        }
    }

    /// Nur Tage zählen, für die HealthKit tatsächlich Daten hat — ein Lücken-Tag
    /// käme sonst als reiner Grundumsatz in den Schnitt und würde jeden echten
    /// Tag besser aussehen lassen, als er war. Unter drei Tagen ist der
    /// "Schnitt" Rauschen, dann bleibt der Ring neutral.
    private func updateTrailingAverage() {
        let calendar = Calendar.current
        var totals: [Double] = []
        var lastSeven: [Double] = []
        var lastSevenSteps: [Int] = []
        for offset in 1...14 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: selectedDate),
                  let snap = healthKit.history[HealthKitImportService.dateKey(day)] else { continue }
            let value = comparableTotal(dayComponents(for: day))
            totals.append(value)
            if offset <= 7 {
                lastSeven.append(value)
                lastSevenSteps.append(snap.activity.steps)
            }
        }
        trailingAverage  = totals.count    >= 3 ? totals.reduce(0, +)    / Double(totals.count)    : nil
        sevenDayAverage  = lastSeven.count >= 3 ? lastSeven.reduce(0, +) / Double(lastSeven.count) : nil
        sevenDayCount    = lastSeven.count
        sevenDayAverageSteps = lastSevenSteps.count >= 3
            ? lastSevenSteps.reduce(0, +) / lastSevenSteps.count
            : nil
    }

    /// Same basis as the ring's average, over seven days instead of fourteen.
    private var vsSevenDayPercent: Double? {
        guard !isSelectedFuture, let average = sevenDayAverage, average > 0 else { return nil }
        return (displayBurnedSoFar - average) / average * 100
    }

    /// The ring's own average, expressed as a percentage for a tile.
    private var vsFourteenDayPercent: Double? {
        guard !isSelectedFuture, let average = trailingAverage, average > 0 else { return nil }
        return (displayBurnedSoFar - average) / average * 100
    }

    /// The five parts of one day's total, in the exact composition the KPI tile
    /// compares. Having a single implementation is what lets the narrative
    /// decompose the percentage the user actually sees instead of a number of
    /// its own.
    struct DayComponents {
        var bmr = 0.0
        var neat = 0.0
        var eat = 0.0
        var tef = 0.0
        var caffeine = 0.0

        var total: Double { bmr + neat + eat + tef + caffeine }
    }

    /// Everything a tile needs for one day, for any date in the history.
    ///
    /// `dayComponents` throws away the activity result it computes internally,
    /// which is all the tiles that are not pure kcal need — steps, afterburn,
    /// the waking window. Rather than compute a day twice, this returns the
    /// lot; `dayComponents` is left alone since half the screen calls it.
    private struct KPIDay {
        let components: DayComponents
        let steps: Int
        let afterburnKcal: Double
        let wakingHours: Double
        /// False when HealthKit has nothing for the day — the tile then has no
        /// honest answer rather than a confident zero.
        let hasActivity: Bool
    }

    private func kpiDay(for date: Date) -> KPIDay {
        let calendar = Calendar.current
        let components = dayComponents(for: date)

        if calendar.isDate(date, inSameDayAs: selectedDate) {
            return KPIDay(
                components: components,
                steps: selectedActivity.steps,
                afterburnKcal: afterburnKcalToday,
                wakingHours: wakingHoursElapsed,
                hasActivity: healthKit.isAuthorized && !isSelectedFuture
            )
        }

        guard let snap = healthKit.history[HealthKitImportService.dateKey(date)] else {
            return KPIDay(components: components, steps: 0, afterburnKcal: 0,
                          wakingHours: 0, hasActivity: false)
        }

        let tdee = TDEECalculationService.calculate(
            bmrStandard: activeFinalBMR,
            inputs: store.journalInputs(for: date),
            isFemale: selectedGender == femaleText
        )
        let active = ActivityCalculationService.calculate(
            steps: snap.activity.steps,
            nonWorkoutSteps: snap.activity.nonWorkoutSteps,
            nonWorkoutDistanceMeters: snap.activity.nonWorkoutDistanceMeters,
            standTimeMinutes: snap.activity.standTimeMinutes,
            nonWorkoutStandMinutes: snap.activity.nonWorkoutStandMinutes,
            restingHR: snap.activity.restingHeartRate,
            hrSegments: snap.activity.hrSegments,
            wakeMinuteOfDay: snap.activity.wakeMinuteOfDay,
            vo2Max: healthKit.vo2Max,
            workouts: snap.workouts,
            weightKg: weightInKg,
            age: userAge,
            isMale: selectedGender != femaleText,
            sleepHours: sleepHours,
            bmrDynamisch: tdee.bmrDynamisch,
            referenceDate: date
        )

        return KPIDay(
            components: components,
            steps: snap.activity.steps,
            afterburnKcal: active.workoutDetails.reduce(0) { $0 + $1.afterburnKcal },
            wakingHours: max(0, 24.0 - sleepHours),
            hasActivity: true
        )
    }

    /// The tile's figure for a past day, or nil when the day cannot answer it.
    /// Deliberately numeric — the table needs to scale bars against it, which
    /// the formatted strings in `kpiReading` cannot support.
    private func kpiNumericValue(_ kpi: DashboardKPI, on date: Date) -> Double? {
        let day = kpiDay(for: date)
        let c = day.components
        guard c.total > 0 else { return nil }
        let hasActivity = day.hasActivity

        switch kpi {
        case .dayEstimate:  return c.total
        case .bmr:          return c.bmr
        case .activeBurn:   return hasActivity ? c.neat + c.eat : nil
        case .neat:         return hasActivity ? c.neat : nil
        case .eat:          return hasActivity ? c.eat : nil
        case .afterburn:    return hasActivity ? day.afterburnKcal : nil

        case .bmrShare:     return c.bmr / c.total * 100
        case .tefShare:     return c.tef / c.total * 100
        case .activeShare:  return hasActivity ? (c.neat + c.eat) / c.total * 100 : nil
        case .neatShare:    return hasActivity ? c.neat / c.total * 100 : nil
        case .eatShare:     return hasActivity ? c.eat / c.total * 100 : nil
        case .afterburnShareOfWorkout:
            guard hasActivity, c.eat > 0 else { return nil }
            return day.afterburnKcal / c.eat * 100

        case .palFactor:    return c.bmr > 0 ? c.total / c.bmr : nil
        case .kcalPerKg:    return weightInKg > 0 ? c.total / weightInKg : nil
        case .burnPerWakingHour:
            return day.wakingHours > 0.5 ? c.total / day.wakingHours : nil
        case .neatPerThousandSteps:
            guard hasActivity, day.steps > 0 else { return nil }
            return c.neat / Double(day.steps) * 1000

        // Comparisons against a moving baseline. A fortnight of "% vs. the day
        // before" would be a table of second derivatives — true, and unreadable.
        // These tiles show their own history as the underlying total instead.
        case .vsYesterday, .vsSevenDayAverage, .vsFourteenDayAverage, .vsGoal:
            return c.total
        }
    }

    private func dayComponents(for date: Date) -> DayComponents {
        let calendar = Calendar.current

        // The selected day is already computed for the rest of the dashboard.
        if calendar.isDate(date, inSameDayAs: selectedDate) {
            let active = healthKit.isAuthorized ? activityResult : nil
            return DayComponents(
                bmr:      tdeeResult.bmrDynamisch,
                neat:     active?.neatKcal ?? 0,
                eat:      active?.eatKcal ?? 0,
                tef:      tdeeResult.tefKcal,
                caffeine: tdeeResult.koffeinBonus
            )
        }

        let tdee = TDEECalculationService.calculate(
            bmrStandard: activeFinalBMR,
            inputs: store.journalInputs(for: date),
            isFemale: selectedGender == femaleText
        )

        guard let snap = healthKit.history[HealthKitImportService.dateKey(date)] else {
            return DayComponents(bmr: tdee.bmrDynamisch, tef: tdee.tefKcal, caffeine: tdee.koffeinBonus)
        }

        let active = ActivityCalculationService.calculate(
            steps: snap.activity.steps,
            nonWorkoutSteps: snap.activity.nonWorkoutSteps,
            nonWorkoutDistanceMeters: snap.activity.nonWorkoutDistanceMeters,
            standTimeMinutes: snap.activity.standTimeMinutes,
            nonWorkoutStandMinutes: snap.activity.nonWorkoutStandMinutes,
            restingHR: snap.activity.restingHeartRate,
            hrSegments: snap.activity.hrSegments,
            wakeMinuteOfDay: snap.activity.wakeMinuteOfDay,
            vo2Max: healthKit.vo2Max,
            workouts: snap.workouts,
            weightKg: weightInKg,
            age: userAge,
            isMale: selectedGender != femaleText,
            sleepHours: sleepHours,
            bmrDynamisch: tdee.bmrDynamisch,
            referenceDate: date
        )

        return DayComponents(
            bmr:      tdee.bmrDynamisch,
            neat:     active.neatKcal,
            eat:      active.eatKcal,
            tef:      tdee.tefKcal,
            caffeine: tdee.koffeinBonus
        )
    }

    /// A day as far as it has actually come, not as it will end up.
    ///
    /// `dayComponents` returns the day's full BMR, TEF and caffeine — right
    /// for the tiles, which project to midnight, wrong for a text that sits
    /// next to the ring: it put the running day several hundred kcal above the
    /// figure in the middle of the ring. NEAT and EAT need no adjustment, they
    /// only ever cover the hours already measured.
    private func componentsSoFar(for date: Date) -> DayComponents {
        let full = dayComponents(for: date)
        // bmrBurnedSoFar reads the selected day's slots, so this only holds
        // when the day asked about is the one on screen and that day is today.
        guard isSelectedToday,
              Calendar.current.isDate(date, inSameDayAs: selectedDate) else { return full }

        let share = min(max(nowFraction / 24.0, 0), 1)
        return DayComponents(
            bmr:      bmrBurnedSoFar,
            neat:     full.neat,
            eat:      full.eat,
            tef:      full.tef * share,
            caffeine: full.caffeine * share
        )
    }

    private var todayProjected: Double {
        dayComponents(for: selectedDate).total
    }
    
    private var yesterdayProjected: Double {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        return dayComponents(for: yesterday).total
    }

    private var vsYesterdayPercent: Double {
        guard yesterdayProjected > 0 else { return 0 }
        return (todayProjected - yesterdayProjected) / yesterdayProjected * 100
    }
    
    private var vsYesterdayColor: Color {
        vsYesterdayPercent >= 0 ? .green : .red
    }
    
    private var previousDayTotal: Double {
        if isSelectedToday { return yesterdayProjected }
        let prevDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
        return dayComponents(for: prevDate).total
    }

    private var vsSelectedDayPercent: Double {
        if isSelectedToday { return vsYesterdayPercent }
        let prev = previousDayTotal
        guard prev > 0 else { return 0 }
        return (displayBurnedSoFar - prev) / prev * 100
    }
    
    private var vsSelectedDayColor: Color { vsSelectedDayPercent >= 0 ? .green : .red }
    
    private var hkLastUpdatedText: String {
        guard healthKit.isAuthorized else {
            return language == "de" ? "Nicht verbunden" : "Not connected"
        }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        let time = f.string(from: healthKit.activity.fetchedAt)
        return "🔄 " + (language == "de" ? "Zuletzt: " : "Updated: ") + time
    }
    
    private var selectedDateString: String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.locale = Locale(identifier: language == "de" ? "de_DE" : "en_US")
        return f.string(from: selectedDate)
    }
    
    private var currentTimeString: String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.locale = Locale(identifier: language == "de" ? "de_DE" : "en_US")
        return f.string(from: Date())
    }
    
    private var calendarPickerSheet: some View {
        NavigationStack {
            ZStack {
                CaloricBackground()
                VStack(spacing: 0) {
                    DatePicker(
                        "",
                        selection: $selectedDate,
                        in: ...Calendar.current.date(byAdding: .day, value: 7, to: Date())!,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .tint(accentBlue)
                    .padding()
                    .glassCard(20)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            selectedDate = Calendar.current.startOfDay(for: Date())
                        }
                    } label: {
                        HStack {
                            Text(language == "de" ? "Zurück zu Heute" : "Back to Today")
                        }
                        .font(.poppins(size: 16, weight: .semibold))
                        .foregroundStyle(accentBlue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(accentBlue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accentBlue.opacity(0.2), lineWidth: 1))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    Spacer()
                }
            }
            .navigationTitle(language == "de" ? "Datum wählen" : "Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: Binding(
                get: { infoSegmentType.map { InfoSegment(type: $0) } },
                set: { infoSegmentType = $0?.type }
            )) { info in
                infoSheet(for: info.type)
                    .presentationBackground(Theme.canvas)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(t.done) {
                        showCalendarPicker = false
                    }
                    .foregroundStyle(accentBlue)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.visible)
    }
    
    struct SpringyButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .opacity(configuration.isPressed ? 0.8 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
    
    init(
        accentBlue: Color,
        language: String,
        userAge: Int,
        selectedGender: String?,
        noConditionText: String,
        femaleText: String,
        accountUsername: Binding<String>,
        birthDate: Binding<Date>,
        weightText: Binding<String>,
        weightUnit: Binding<String>,
        heightText: Binding<String>,
        heightUnit: Binding<String>,
        bodyFatText: Binding<String>,
        knowsBodyFat: Binding<Bool?>,
        sleepHours: Binding<Double>,
        selectedConditions: Binding<Set<String>>,
        metabolismFactor: Binding<Double>,
        selectedDate: Binding<Date>,
        selectedTab: Binding<Int>
    ) {
        self.accentBlue = accentBlue
        self.language = language
        self.userAge = userAge
        self.selectedGender = selectedGender
        self.noConditionText = noConditionText
        self.femaleText = femaleText
        self._accountUsername = accountUsername
        self._birthDate = birthDate
        self._weightText = weightText
        self._weightUnit = weightUnit
        self._heightText = heightText
        self._heightUnit = heightUnit
        self._bodyFatText = bodyFatText
        self._knowsBodyFat = knowsBodyFat
        self._sleepHours = sleepHours
        self._selectedConditions = selectedConditions
        self._metabolismFactor = metabolismFactor
        self._selectedDate = selectedDate
        self._selectedTab = selectedTab
    }
    
    private var dateNavigationRow: some View {
        let maxDate = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date()))!
        return HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(Theme.card)
                            .overlay(Circle().strokeBorder(Theme.cardStroke, lineWidth: 1))
                    )
            }
            .buttonStyle(SpringyButtonStyle())
            
            Button {
                showCalendarPicker = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentBlue)
                    Text(selectedDateString)
                        .font(.poppins(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(Theme.card)
                        .overlay(Capsule().strokeBorder(Theme.cardStroke, lineWidth: 1))
                        .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 3)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(SpringyButtonStyle())
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                    if next <= maxDate {
                        selectedDate = next
                    }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selectedDate >= maxDate ? Theme.textPrimary.opacity(0.25) : Theme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(Theme.card)
                            .overlay(Circle().strokeBorder(Theme.cardStroke, lineWidth: 1))
                    )
            }
            .buttonStyle(SpringyButtonStyle())
            .disabled(selectedDate >= maxDate)
        }
    }
    
    // MARK: - Collapsing header

    /// Scroll distance over which the full header gives way to the pinned row.
    /// Roughly the height of the title plus the date strip, so the swap is
    /// finished about when they have left the screen.
    private static let headerCollapseDistance: CGFloat = 76

    /// Steps the progress is rounded to before it reaches state.
    ///
    /// This body is large, and a raw offset would re-evaluate all of it on
    /// every scroll frame. Twenty steps is fine enough that the eye reads it
    /// as continuous, especially with the short easing on the affected views,
    /// and it cuts the re-render count by an order of magnitude.
    private static let headerCollapseSteps: Double = 20

    /// Compact stand-in for the date strip: appears pinned top-left once the
    /// full strip has scrolled away, and opens the same picker.
    ///
    /// Deliberately the same capsule, fill and hairline as the strip it
    /// replaces, only smaller and without the two arrows — so it reads as that
    /// control shrunk down rather than as a different one.
    private var compactDateButton: some View {
        Button {
            showCalendarPicker = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentBlue)
                Text(selectedDateString)
                    .font(.poppins(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    // The written-out date is long; on a narrow screen it
                    // shrinks rather than crowding the profile button.
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Theme.card)
                    .overlay(Capsule().strokeBorder(Theme.cardStroke, lineWidth: 1))
                    .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 3)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(SpringyButtonStyle())
    }

    /// Sits above the scroll content. The profile button never moves — it keeps
    /// the exact position it had in the flowing header, which is why this row
    /// carries the same height and padding as the title row below it.
    private var pinnedHeaderRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                compactDateButton
                    .opacity(headerCollapseProgress)
                    // Anchored left so the bar grows out of the corner it is
                    // pinned to instead of drifting sideways into place.
                    .scaleEffect(0.9 + 0.1 * headerCollapseProgress, anchor: .leading)
                    // Untappable while it is still mostly transparent, so a tap
                    // meant for the content below never lands here.
                    .allowsHitTesting(headerCollapseProgress > 0.6)
                Spacer(minLength: 12)
                profileIconButton
            }
            .frame(height: 40)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.12), value: headerCollapseProgress)
    }

    private var profileIconButton: some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                showProfileSidebar = true
            }
        } label: {
            Image(systemName: "person.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(colors: [Theme.accentSky, accentBlue],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: accentBlue.opacity(0.30), radius: 8, x: 0, y: 4)
                )
        }
    }
    
    var body: some View {
        ZStack {
            CaloricBackground()

            // Header scrolls with the content instead of sitting above the
            // ScrollView, so the page simply runs top to bottom.
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(language == "de" ? "Dein Überblick" : "Your Overview")
                                .font(.poppins(size: LayoutMetrics.titleFontSize, weight: .heavy))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        // Fixed height, and the profile button lifted out into
                        // pinnedHeaderRow: both so the pinned copy lands on the
                        // exact pixel this one occupied.
                        .frame(height: 40)
                        dateNavigationRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                    // Fades and drifts up as it goes, rather than only sliding
                    // out of frame — that is what makes the swap read as one
                    // movement instead of two things happening at once.
                    .opacity(1 - headerCollapseProgress)
                    .offset(y: -headerCollapseProgress * 10)
                    .scaleEffect(1 - headerCollapseProgress * 0.04, anchor: .topLeading)
                    .allowsHitTesting(headerCollapseProgress < 0.5)
                    .animation(.easeOut(duration: 0.12), value: headerCollapseProgress)

                    VStack(spacing: LayoutMetrics.cardSpacing) {
                        calorieRingWidget
                            .padding(.horizontal, 20)

                        if !isSelectedFuture {
                            DayDeepDiveButton(
                                language: language,
                                accentBlue: accentBlue,
                                action: { showDeepDive = true }
                            )
                            .padding(.horizontal, 20)
                        }

                        kpiRow
                            .padding(.horizontal, 20)

                        caloriesChartSection

                        Spacer().frame(height: 20)
                    }
                }
            }
            // Progress is derived and clamped here rather than in the body, so
            // state only changes when the rounded value actually moves — and
            // scrolling back up reverses the whole effect for free.
            // Attached before the mask so it sits directly on the scroll view.
            .onScrollGeometryChange(for: Double.self) { geometry in
                let travelled = geometry.contentOffset.y + geometry.contentInsets.top
                let raw = Double(travelled / Self.headerCollapseDistance)
                let clamped = min(max(raw, 0), 1)
                let steps = Self.headerCollapseSteps
                return (clamped * steps).rounded() / steps
            } action: { _, newValue in
                headerCollapseProgress = newValue
            }
            .collapsingHeaderFade(progress: headerCollapseProgress)
            .refreshable {
                await healthKit.fetchAll()
                await MainActor.run {
                    clockTick = Date()
                    runBurnAnimation()
                }
                Task { @MainActor in
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                        showRefreshBadge = true
                    }
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    withAnimation(.easeOut(duration: 0.45)) {
                        showRefreshBadge = false
                    }
                }
            }

            pinnedHeaderRow

            // Abdunkelung beim Öffnen der Leiste
            if showProfileSidebar {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            showProfileSidebar = false
                        }
                    }
                    .transition(.opacity)
            }
            // Bottom Sheets
            VStack(spacing: 0) {
                Spacer()
                if showProfileSidebar {
                    profilePanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: showProfileSidebar)
            .allowsHitTesting(showProfileSidebar)

            // Refresh-Badge
            if showRefreshBadge {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(language == "de" ? "Alles aktuell" : "All up to date")
                                .font(.poppins(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))
                                .font(.poppins(size: 11, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 6)
                    )
                    .padding(.top, topSafeArea + 6)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
    }
        .onAppear {
            migrateKPITilesForPAL()
            runBurnAnimation()
            syncWeightFromHealth()
        }
        .onChange(of: selectedDate) { _, _ in
            runBurnAnimation()
            resetDeepDive()
        }
        .onChange(of: tdeeResult.tdeeTotal) { _, _ in runBurnAnimation() }
        .onChange(of: healthKit.activity.fetchedAt) { _, _ in runBurnAnimation() }
        .onChange(of: healthKit.workouts) { _, _ in runBurnAnimation() }
        .onChange(of: healthKit.bodyMassKg) { _, _ in syncWeightFromHealth() }
        .onChange(of: showProfileSidebar) { _, isOpen in
            if isOpen { prepareExport() }
        }
        // Only the crossing matters — dragging the slider moves the value
        // continuously and must not touch the row on every step.
        .onChange(of: dailyGoalKcal) { old, new in
            guard (old > 0) != (new > 0) else { return }
            syncGoalTile(hasGoal: new > 0)
            // The cached text was written for a day with no goal in it — and
            // the store would serve that same text straight back, so the
            // persisted copy has to go too.
            deepDiveStore.clear(dateKey: HealthKitImportService.dateKey(selectedDate))
            resetDeepDive()
        }
        .onChange(of: weightSource) { _, _ in syncWeightFromHealth() }
        // History arrives after the first fetch, so the average would otherwise
        // stay empty until the next refresh and the ring stay neutral.
        .onChange(of: healthKit.history.count) { _, _ in updateTrailingAverage() }
        // Coming back to the app is the moment the numbers are most likely to
        // be wrong — minutes or hours have passed with nothing running.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { @MainActor in
                clockTick = Date()
                await healthKit.fetchAll()
                runBurnAnimation()
            }
        }
        // Keeps a dashboard left open honest: the elapsed BMR, the "now" line,
        // the partial-day comparisons and the ring's own figure all move with
        // the clock.
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { tick in
            clockTick = tick
            syncBurnFigure()
        }
        .sheet(isPresented: $showCalendarPicker) {
            calendarPickerSheet
        }
        .sheet(isPresented: Binding(
            get: { editingField != nil },
            set: { if !$0 { editingField = nil } }
        )) {
            editFieldSheet()
        }
        .sheet(isPresented: $showActivityBreakdown) {
            activityBreakdownSheet
        }
        .sheet(isPresented: $showDeepDive) {
            DayDeepDiveSheet(
                language: language,
                accentBlue: accentBlue,
                deepDive: deepDive,
                isLoading: deepDiveIsLoading,
                errorMessage: deepDiveError,
                onRegenerate: { Task { await loadDeepDive(force: true) } }
            )
            // The request starts here and nowhere else: that is what keeps a
            // day nobody opens free.
            .task { await loadDeepDive() }
            .presentationDetents([.medium, .large])
            .presentationBackground(Theme.canvas)
        }
        .fullScreenCover(isPresented: $showCalorieDetail) {
            CalorieDetailView(
                slots: calorieSlots,
                accentBlue: accentBlue,
                language: language,
                isSelectedToday: isSelectedToday,
                nowFraction: nowFraction
            )
            .caloricAppearance()
        }
    }

    /// Brings the ring to the current figure without replaying the count-up.
    ///
    /// animatedBurn is written only by runBurnAnimation, so a clock tick moved
    /// the chart and the tiles but left the ring's headline number frozen at
    /// whatever it was when the animation last ran — the one number on the
    /// screen still going stale. Replaying the full count-up every minute
    /// would be a distraction, so this just eases across.
    @MainActor
    private func syncBurnFigure() {
        guard !isSelectedFuture else { return }
        withAnimation(.easeOut(duration: 0.4)) {
            animatedBurn = displayBurnedSoFar
            ringProgress = displayBurnProgress
        }
    }

    private func runBurnAnimation() {
        // Same triggers the ring itself reacts to, so its tint never describes
        // a different day than its fill.
        updateTrailingAverage()
        ringProgress = 0
        animatedBurn = 0
        withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.15)) {
            ringProgress = displayBurnProgress
        }
        let target = displayBurnedSoFar
        let steps = 60
        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.018 * Double(i)) {
                withAnimation(.easeOut) { animatedBurn = target * Double(i) / Double(steps) }
            }
        }
    }

    // MARK: - Aktivitäts-Aufschlüsselung Sheet

    @State private var selectedEnergySegment: EnergySegment? = nil
    @State private var expandedSegmentType: EnergySegmentType? = nil
    @State private var infoSegmentType: EnergySegmentType? = nil

    private struct InfoSegment: Identifiable {
        let id = UUID()
        let type: EnergySegmentType
    }

    private struct EnergySegment: Identifiable {
        let type: EnergySegmentType
        var id: EnergySegmentType { type }
        let title: String
        let short: String
        let subtitle: String?
        let icon: String
        let color: Color
        let kcal: Double
    }

    /// Ordered energy-expenditure components — for today shows burned so far, for past/future shows full day.
    private var energySegments: [EnergySegment] {
        let neat = healthKit.isAuthorized ? activityResult.neatKcal : 0
        let eat  = healthKit.isAuthorized ? activityResult.eatKcal  : 0

        // When viewing today, scale BMR/TEF/caffeine to the elapsed fraction of the day.
        // NEAT and EAT come from HealthKit and already reflect what actually happened.
        let fraction = nowFraction / 24.0
        let bmrVal = isSelectedToday ? bmrBurnedSoFar : tdeeResult.bmrDynamisch
        let tefVal = isSelectedToday ? tdeeResult.tefKcal * fraction : tdeeResult.tefKcal
        let cafVal = isSelectedToday ? tdeeResult.koffeinBonus * fraction : tdeeResult.koffeinBonus

        var segs: [EnergySegment] = [
            EnergySegment(
                type: .bmr,
                title: language == "de" ? "BMR" : "Resting Metabolic Rate",
                short: "BMR",
                subtitle: language == "de" ? "Grundumsatz" : "Basal Metabolic Rate",
                icon: "moon.zzz.fill", color: Theme.segBMR, kcal: bmrVal
            ),
            EnergySegment(
                type: .neat,
                title: "NEAT",
                short: "NEAT",
                subtitle: language == "de" ? "Alltagsbewegung" : "Non-Exercise Activity Thermogenesis",
                icon: "figure.walk", color: Theme.segNEAT, kcal: neat
            ),
            EnergySegment(
                type: .eat,
                title: "EAT",
                short: "EAT",
                subtitle: language == "de" ? "Workouts" : "Exercise Activity Thermogenesis",
                icon: "dumbbell.fill", color: Theme.segEAT, kcal: eat
            ),
            EnergySegment(
                type: .tef,
                title: "TEF",
                short: "TEF",
                subtitle: language == "de" ? "Thermische Wirkung der Ernährung" : "Thermic Effect of Food",
                icon: "fork.knife.circle.fill", color: Theme.segTEF, kcal: tefVal
            ),
        ]
        if cafVal > 0 {
            segs.append(EnergySegment(
                type: .caffeine,
                title: language == "de" ? "Koffein-Thermogenese" : "Caffeine Thermogenesis",
                short: language == "de" ? "Koffein" : "Caffeine",
                subtitle: nil,
                icon: "cup.and.heat.waves.fill", color: Theme.segCaf, kcal: cafVal
            ))
        }
        return segs
    } 

        @ViewBuilder
    private func expandedContent(for type: EnergySegmentType, currentKcal: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let prev = previousValue(for: type)
            let diffPct = (prev > 0) ? ((currentKcal - prev) / prev) * 100.0 : 0.0

            HStack {
                PercentDeltaBadge(
                    percent: diffPct,
                    suffix: language == "de" ? "vs. gestern" : "vs. yesterday"
                )

                Spacer()

                Button {
                    infoSegmentType = type
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.top, 4)

            VStack(spacing: 8) {
                switch type {
                case .neat:
                    // Scaled like the NEAT total above, so the sub-rows agree
                    // with the percentage shown for the segment.
                    let f = elapsedActivityFraction
                    let prev = previousActivityResult.neatBreakdown
                    breakdownItem(label: language == "de" ? "Schritte" : "Steps", value: activityResult.neatBreakdown.neatSteps, prevValue: prev.neatSteps * f)
                    breakdownItem(label: language == "de" ? "Stehen" : "Standing", value: activityResult.neatBreakdown.neatStand, prevValue: prev.neatStand * f)
                    breakdownItem(label: language == "de" ? "Herzfrequenz" : "Heart Rate", value: activityResult.neatBreakdown.neatHR, prevValue: prev.neatHR * f)
                case .eat:
                    let f = elapsedActivityFraction
                    let prevDetails = previousActivityResult.workoutDetails
                    ForEach(activityResult.workoutDetails) { detail in
                        let matchedPrev = prevDetails.first(where: { $0.name == detail.name })?.kcal
                        workoutBreakdownItem(detail, prevValue: matchedPrev.map { $0 * f })
                    }
                    if activityResult.workoutDetails.isEmpty {
                        breakdownItem(label: language == "de" ? "Keine Workouts" : "No workouts", value: 0)
                    }
                case .tef:
                    let prevDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
                    let inputs = store.journalInputs(for: selectedDate)
                    let pInputs = store.journalInputs(for: prevDate)
                    let p = inputs.proteinGramsByMeal.values.reduce(0, +) * 1.0
                    let c = inputs.carbsGramsByMeal.values.reduce(0, +) * 0.3
                    let f = inputs.fatGramsByMeal.values.reduce(0, +) * 0.135
                    let pp = pInputs.proteinGramsByMeal.values.reduce(0, +) * 1.0
                    let pc = pInputs.carbsGramsByMeal.values.reduce(0, +) * 0.3
                    let pf = pInputs.fatGramsByMeal.values.reduce(0, +) * 0.135
                    breakdownItem(label: language == "de" ? "Protein" : "Protein", value: p, prevValue: pp)
                    breakdownItem(label: language == "de" ? "Kohlenhydrate" : "Carbs", value: c, prevValue: pc)
                    breakdownItem(label: language == "de" ? "Fett" : "Fat", value: f, prevValue: pf)
                case .caffeine:
                    let prevDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
                    let inputs = store.journalInputs(for: selectedDate)
                    let pInputs = store.journalInputs(for: prevDate)
                    let pBonus = TDEECalculationService.calculate(bmrStandard: activeFinalBMR, inputs: pInputs, isFemale: selectedGender == femaleText).koffeinBonus
                    breakdownItem(label: language == "de" ? "Koffein (\(Int(inputs.caffeineMg)) mg)" : "Caffeine (\(Int(inputs.caffeineMg)) mg)", value: tdeeResult.koffeinBonus, prevValue: pBonus)
                case .bmr:
                    breakdownItem(label: language == "de" ? "Basis-Grundumsatz" : "Base BMR", value: currentKcal)
                }
            }
            .padding(10)
            .background(Theme.ink.opacity(0.04))
            .cornerRadius(10)
        }
    }

    

    /// Like breakdownItem, plus a second line naming where the session came
    /// from and when it ran. Workouts now arrive from several sources, so
    /// "Laufen outdoor" alone no longer says which of them recorded it.
    private func workoutBreakdownItem(
        _ detail: ActivityCalculationService.WorkoutDetail,
        prevValue: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(detail.name)
                    .font(.poppins(size: 13, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                if let prev = prevValue, prev > 0 {
                    PercentDeltaBadge(percent: (detail.kcal - prev) / prev * 100.0, compact: true)
                }

                Text(String(format: "%.0f kcal", detail.kcal))
                    .font(.poppins(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 56, alignment: .trailing)
            }

            HStack(spacing: 5) {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: 8, weight: .semibold))
                Text(detail.sourceName)
                Text("·")
                Text(Self.workoutTimeRange(detail))
            }
            .font(.poppins(size: 10, weight: .regular))
            .foregroundStyle(Theme.textSecondary.opacity(0.7))
            .lineLimit(1)
        }
    }

    private static let workoutTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static func workoutTimeRange(_ detail: ActivityCalculationService.WorkoutDetail) -> String {
        let start = workoutTimeFormatter.string(from: detail.startDate)
        let end   = workoutTimeFormatter.string(from: detail.endDate)
        return "\(start) – \(end)"
    }

    private func breakdownItem(label: String, value: Double, prevValue: Double? = nil) -> some View {
        HStack {
            Text(label)
                .font(.poppins(size: 13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            if let prev = prevValue, prev > 0 {
                PercentDeltaBadge(percent: (value - prev) / prev * 100.0, compact: true)
            }

            Text(String(format: "%.0f kcal", value))
                .font(.poppins(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(minWidth: 56, alignment: .trailing)
        }
    }

    /// Direction-tinted capsule for a day-over-day percentage. One shape for
    /// both the segment header (with a "vs. gestern" suffix) and the compact
    /// sub-rows, so a delta reads the same everywhere it appears.
    private struct PercentDeltaBadge: View {
        let percent: Double
        var suffix: String? = nil
        var compact: Bool = false

        private var isUp: Bool { percent >= 0 }
        private var tint: Color { isUp ? .green : .red }

        var body: some View {
            HStack(spacing: compact ? 3 : 5) {
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: compact ? 8 : 11, weight: .bold))
                // No decimal: these are day-over-day comparisons of estimates,
                // and a tenth of a percent claims a precision they do not have.
                Text(String(format: "%+.0f%%", percent))
                    .font(.poppins(size: compact ? 11 : 13, weight: .semibold))
                if let suffix {
                    Text(suffix)
                        .font(.poppins(size: 13, weight: .medium))
                        .foregroundStyle(tint.opacity(0.8))
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, compact ? 7 : 10)
            .padding(.vertical, compact ? 3 : 6)
            .background(Capsule().fill(tint.opacity(0.13)))
        }
    }

        private var previousActivityResult: ActivityCalculationService.ActivityResult {
        let prevDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
        let key = HealthKitImportService.dateKey(prevDate)
        let inputs = store.journalInputs(for: prevDate)
        let tdee = TDEECalculationService.calculate(
            bmrStandard: activeFinalBMR,
            inputs: inputs,
            isFemale: selectedGender == femaleText
        )
        if let snap = healthKit.history[key] {
            return ActivityCalculationService.calculate(
                steps: snap.activity.steps,
                nonWorkoutSteps: snap.activity.nonWorkoutSteps,
                nonWorkoutDistanceMeters: snap.activity.nonWorkoutDistanceMeters,
                standTimeMinutes: snap.activity.standTimeMinutes,
                nonWorkoutStandMinutes: snap.activity.nonWorkoutStandMinutes,
                restingHR: snap.activity.restingHeartRate,
                hrSegments: snap.activity.hrSegments,
                wakeMinuteOfDay: snap.activity.wakeMinuteOfDay,
                vo2Max: healthKit.vo2Max,
                workouts: snap.workouts,
                weightKg: weightInKg,
                age: userAge,
                isMale: selectedGender != femaleText,
                sleepHours: sleepHours,
                bmrDynamisch: tdee.bmrDynamisch,
                referenceDate: prevDate
            )
        }
        return ActivityCalculationService.ActivityResult(neatKcal: 0, eatKcal: 0)
    }

    /// Share of the day's *waking* time that has elapsed. NEAT and EAT happen
    /// while awake, so scaling them by wall-clock time would compare this
    /// morning against a slice of yesterday that includes the night.
    private var elapsedActivityFraction: Double {
        guard isSelectedToday else { return 1.0 }
        let wakeHour = min(max(sleepHours, 0), 23)
        let awake = 24.0 - wakeHour
        guard awake > 0 else { return 1.0 }
        return min(1.0, max(0.0, (nowFraction - wakeHour) / awake))
    }

    private func previousValue(for type: EnergySegmentType) -> Double {
        let prevDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
        let inputs = store.journalInputs(for: prevDate)
        let tdee = TDEECalculationService.calculate(
            bmrStandard: activeFinalBMR,
            inputs: inputs,
            isFemale: selectedGender == femaleText
        )
        // TEF/caffeine are modelled evenly across the 24 h day, so they scale
        // with wall-clock time; NEAT/EAT scale with elapsed waking time. Both
        // must be scaled — comparing a partial today against a full yesterday
        // made every mid-day NEAT/EAT delta look negative.
        let clockFraction = isSelectedToday ? nowFraction / 24.0 : 1.0
        let activeFraction = elapsedActivityFraction
        let res = previousActivityResult

        switch type {
        case .bmr:
            // BMR accrues along the intraday profile in calorieSlots (0.88 while
            // asleep, 0.90–1.14 across the day), not evenly. Scaling yesterday
            // flat by wall-clock time compared two differently shaped curves and
            // manufactured a delta of tens of kcal — largest in the morning,
            // where the elapsed hours are mostly the 0.88 sleep block.
            //
            // Taking today's own accrual and rescaling it by the ratio of the
            // two days' BMR keeps the shape identical on both sides, so only a
            // real change in the day's BMR (illness, cycle) shows up.
            let todayBMR = todaySegmentValue(for: .bmr)
            guard tdeeResult.bmrDynamisch > 0 else { return todayBMR }
            return todayBMR * (tdee.bmrDynamisch / tdeeResult.bmrDynamisch)
        case .neat:     return res.neatKcal * activeFraction
        case .eat:      return res.eatKcal * activeFraction
        case .tef:      return tdee.tefKcal * clockFraction
        case .caffeine: return tdee.koffeinBonus * clockFraction
        }
    }

    /// Today's value for a segment, independent of whether it is currently
    /// shown in the ring — `energySegments` omits caffeine at zero, but the
    /// comparison still needs the number.
    private func todaySegmentValue(for type: EnergySegmentType) -> Double {
        let clockFraction = isSelectedToday ? nowFraction / 24.0 : 1.0
        switch type {
        case .bmr:      return isSelectedToday ? bmrBurnedSoFar : tdeeResult.bmrDynamisch
        case .neat:     return healthKit.isAuthorized ? activityResult.neatKcal : 0
        case .eat:      return healthKit.isAuthorized ? activityResult.eatKcal : 0
        case .tef:      return tdeeResult.tefKcal * clockFraction
        case .caffeine: return tdeeResult.koffeinBonus * clockFraction
        }
    }

    /// The day's split as a ring rather than a bar, matching the dashboard's
    /// calorie ring: same 270° sweep, same start angle, same round caps.
    ///
    /// Each arc is its own tap target. A bar of five segments on a phone gives
    /// the smallest of them a few points of width — as arcs they are large
    /// enough to hit, and the one you picked lifts out of the ring.
    private func energyRing(_ segs: [EnergySegment], total: Double) -> some View {
        // Same geometry as calorieRingWidget so the two read as one family.
        let sweep = 0.75
        let start = 135.0

        // Running offsets, so each arc knows where the ones before it ended.
        var cursor = 0.0
        var arcs: [(seg: EnergySegment, from: Double, to: Double)] = []
        for seg in segs {
            let share = total > 0 ? seg.kcal / total : 0
            arcs.append((seg, cursor, cursor + share))
            cursor += share
        }

        return ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(Theme.trackFill, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(start))

            ForEach(arcs, id: \.seg.id) { arc in
                let picked = expandedSegmentType == arc.seg.type
                Circle()
                    .trim(from: arc.from * sweep, to: arc.to * sweep)
                    .stroke(
                        LinearGradient(colors: [arc.seg.color.opacity(0.85), arc.seg.color],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: picked ? 17 : 12, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(start))
                    .shadow(color: arc.seg.color.opacity(picked ? 0.45 : 0.2), radius: picked ? 8 : 3)
                    // contentShape on the same trim: without it the tap target
                    // would be the full circle and every arc would overlap.
                    .contentShape(
                        Circle()
                            .trim(from: arc.from * sweep, to: arc.to * sweep)
                            // Wider than the stroke on purpose: a 14pt arc is
                            // thinner than a fingertip, so the target keeps the
                            // reach the old thicker ring had.
                            .stroke(style: StrokeStyle(lineWidth: 34))
                            .rotation(.degrees(start))
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            expandedSegmentType = picked ? nil : arc.seg.type
                        }
                    }
            }

            // The picked slice, or the day, in the middle — same type as the
            // dashboard ring so the two read as one instrument.
            VStack(spacing: 2) {
                let shown = segs.first(where: { $0.type == expandedSegmentType })
                Text("\(Int((shown?.kcal ?? total).rounded()))")
                    .font(.poppins(size: 42, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text(shown?.short ?? "kcal")
                    .font(.poppins(size: 14, weight: .regular))
                    .foregroundStyle(shown?.color ?? Theme.textSecondary)
            }
            .offset(y: -4)
            .animation(.easeOut(duration: 0.2), value: expandedSegmentType)
        }
        .frame(width: LayoutMetrics.ringSize * 1.15, height: LayoutMetrics.ringSize * 1.15)
        .padding(.top, 20)
    }
    private func infoSheet(for type: EnergySegmentType) -> some View {
        let seg = energySegments.first(where: { $0.type == type })
        let segColor = seg?.color ?? accentBlue
        return VStack(spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: seg?.icon ?? "info.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(segColor)
                    .frame(width: 44, height: 44)
                    .background(segColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(seg?.title ?? "")
                        .font(.poppins(size: 18, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(language == "de" ? "Information" : "Information")
                        .font(.poppins(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button { infoSegmentType = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.textSecondary.opacity(0.3))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Text(infoText(for: type))
                .font(.poppins(size: 15, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(5)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 10) {
                Text(language == "de" ? "Speist sich aus" : "Fed by")
                    .font(.poppins(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                // Wraps: five sources do not fit one row on a narrow phone,
                // and an HStack would have squeezed them instead of breaking.
                // Fixed two columns rather than adaptive: the adaptive grid
                // stretched "Herzfrequenz" across a full-width cell and let it
                // wrap mid-word while its neighbours stayed one line.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)],
                          alignment: .leading, spacing: 8) {
                    ForEach(LiveSource.feeding(type), id: \.de) { source in
                        HStack(spacing: 6) {
                            Image(systemName: source.icon)
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 14)
                            Text(source.label(language: language))
                                .font(.poppins(size: 12, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(segColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(segColor.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }

                Button {
                    infoSegmentType = nil
                    showActivityBreakdown = false
                    selectedTab = 1
                } label: {
                    HStack(spacing: 5) {
                        Text(language == "de" ? "Alle Live-Quellen ansehen" : "See all live sources")
                            .font(.poppins(size: 12, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(accentBlue)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
    }

    private func infoText(for type: EnergySegmentType) -> String {
        switch type {
        case .bmr: return language == "de" ? "Der Grundumsatz ist die Energie, die dein Körper im Ruhezustand benötigt, um lebenswichtige Funktionen aufrechtzuerhalten." : "Basal Metabolic Rate is the energy your body needs at rest to maintain vital functions."
        case .neat: return language == "de" ? "NEAT umfasst alle Kalorien, die du durch Alltagsbewegungen wie Gehen, Stehen oder Hausarbeit verbrennst, außerhalb von gezieltem Sport." : "NEAT includes all calories burned through daily activities like walking, standing, or chores, outside of intentional exercise."
        case .eat: return language == "de" ? "EAT bezeichnet die Energie, die du während geplanter sportlicher Aktivitäten und Workouts verbrauchst." : "EAT refers to the energy consumed during planned physical activities and workouts."
        case .tef: return language == "de" ? "TEF ist die Energie, die dein Körper für die Verdauung, Aufnahme und Verarbeitung von Nährstoffen aus der Nahrung aufwendet." : "TEF is the energy your body spends on digesting, absorbing, and processing nutrients from food."
        case .caffeine: return language == "de" ? "Koffein kann den Stoffwechsel und die Wärmeproduktion des Körpers kurzzeitig leicht erhöhen." : "Caffeine can slightly increase metabolism and the body's heat production for a short period."
        }
    }

    private var activityBreakdownSheet: some View {
        let segs = energySegments
        let total = max(segs.reduce(0) { $0 + $1.kcal }, 1)
        return NavigationStack {
            ZStack(alignment: .top) {
                CaloricBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        // Hero — total + stacked micro-chart. No card behind it:
                        // the ring floats on the sheet itself, which keeps the
                        // one number on the page from sitting in a frame.
                        VStack(spacing: 14) {
                            // No figure above the ring: it already carries the
                            // same number in its centre, and two of them a
                            // centimetre apart read as two different totals.
                            energyRing(segs, total: total)
                            // Legend
                            HStack(spacing: 14) {
                                ForEach(segs) { s in
                                    HStack(spacing: 5) {
                                        Circle().fill(s.color).frame(width: 7, height: 7)
                                        Text(s.short)
                                            .font(.poppins(size: 10, weight: .regular))
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(.horizontal, 18)

                        // Per-component rows with progress bars
                        VStack(spacing: 8) {
                            ForEach(segs) { s in
                                energySegmentRow(s, total: total)
                            }
                        }
                        .padding(.horizontal, 18)

                        if !healthKit.isAuthorized {
                            HStack(spacing: 8) {
                                Image(systemName: "heart.text.square.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(accentBlue)
                                Text(language == "de"
                                     ? "Verbinde Apple Health für NEAT & EAT Daten."
                                     : "Connect Apple Health for NEAT & EAT data.")
                                    .font(.poppins(size: 12, weight: .regular))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.horizontal, 30)
                            .padding(.top, 4)
                        }

                        Spacer().frame(height: 14)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle(language == "de" ? "Aufschlüsselung" : "Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t.done) { showActivityBreakdown = false }
                        .foregroundStyle(accentBlue)
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(item: Binding(
            get: { infoSegmentType.map { InfoSegment(type: $0) } },
            set: { infoSegmentType = $0?.type }
        )) { info in
            infoSheet(for: info.type)
                .presentationBackground(Theme.canvas)
        }
        .caloricAppearance()
        .presentationDetents([.fraction(0.62), .large])
        .presentationBackground(Theme.canvas)
    }

    private func energySegmentRow(_ s: EnergySegment, total: Double) -> some View {
        let pct = total > 0 ? s.kcal / total : 0
        let isExpanded = expandedSegmentType == s.type

        return VStack(spacing: 9) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    expandedSegmentType = (expandedSegmentType == s.type) ? nil : s.type
                }
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: s.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(s.color)
                        .frame(width: 42, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(s.color.opacity(0.16))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(s.color.opacity(0.30), lineWidth: 1))
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title)
                            .font(.poppins(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let subtitle = s.subtitle {
                            Text(subtitle)
                                .font(.poppins(size: 11, weight: .regular))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(Int(s.kcal))")
                                .font(.poppins(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("kcal")
                                .font(.poppins(size: 11, weight: .regular))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(String(format: "%.0f%%", pct * 100))
                            .font(.poppins(size: 11, weight: .medium))
                            .foregroundStyle(s.color)
                    }
                }
            }
            .buttonStyle(.plain)

            InstrumentProgressBar(progress: pct, color: s.color, height: 4, showScale: true)
                .frame(height: 10)

            if isExpanded {
                expandedContent(for: s.type, currentKcal: s.kcal)
                    .transition(.opacity)
            }
        }
        .padding(12)
        .glassCard(16)
    }

    // MARK: - Berechnungsmethoden View

         private func breakdownRow(icon: String, color: Color, title: String, subtitle: String, kcal: Int) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(isDark ? 0.18 : 0.10))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.poppins(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.poppins(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(kcal) kcal")
                .font(.poppins(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Bottom Sheet (User Profile)

        private var profilePanel: some View {
        VStack(spacing: 0) {
            // Drag Handle
            Capsule()
                .fill(.secondary.opacity(0.38))
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 6)

            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language == "de" ? "Einstellungen" : "Settings")
                        .font(.poppins(size: 24, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(language == "de"
                         ? "Körperwerte bearbeitest du unter Meine Daten"
                         : "Body metrics are edited under My Data")
                        .font(.poppins(size: 13, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                        showProfileSidebar = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 34, height: 34)
                        .glassEffect(in: .circle)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Master data is deliberately absent. Gender, age,
                    // height, weight, body fat and conditions were editable
                    // here, under Meine Daten and in the onboarding, and three
                    // editors over one record is three chances to disagree.
                    // Meine Daten → Stammdaten is the only one left.
                    profileSection(title: language == "de" ? "Allgemein" : "General") {
                        VStack(spacing: 4) {
                            LanguageSetting(
                                accent: accentBlue,
                                language: language,
                                onChange: { newValue in
                                    storedProfile?.sprache = newValue
                                }
                            )
                            Divider().padding(.leading, 40)
                            UnitSettings(
                                accent: accentBlue,
                                language: language,
                                weightText: $weightText,
                                weightUnit: $weightUnit,
                                heightText: $heightText,
                                heightUnit: $heightUnit
                            )
                            Divider().padding(.leading, 40)
                            HStack(spacing: 12) {
                                Image(systemName: "circle.lefthalf.filled")
                                    .font(.system(size: 16))
                                    .foregroundStyle(accentBlue)
                                    .frame(width: 28)
                                Text(language == "de" ? "Erscheinungsbild" : "Appearance")
                                    .font(.poppins(size: 15, weight: .regular))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer(minLength: 8)
                                AppearancePicker(language: language, accent: accentBlue)
                            }
                            .padding(.vertical, 6)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                    }

                    profileSection(title: language == "de" ? "Messung" : "Measurement") {
                        VStack(spacing: 4) {
                            HealthStatusSetting(
                                accent: accentBlue,
                                language: language,
                                isAuthorized: healthKit.isAuthorized,
                                onConnect: {
                                    Task { try? await healthKit.requestAuthorization() }
                                }
                            )
                            Divider().padding(.leading, 40)
                            WeightSourceSetting(
                                accent: accentBlue,
                                language: language,
                                healthKitAuthorized: healthKit.isAuthorized,
                                healthWeightKg: healthKit.bodyMassKg,
                                healthWeightDate: healthKit.bodyMassDate,
                                source: $weightSource
                            )
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                    }

                    profileSection(title: language == "de" ? "Ziel" : "Goal") {
                        DailyGoalSetting(
                            accent: accentBlue,
                            language: language,
                            // Starting at the user's own recent average beats a
                            // round number nobody picked: the first goal they
                            // see is already one they could plausibly hit.
                            suggestedKcal: trailingAverage ?? sevenDayAverage,
                            goalKcal: $dailyGoalKcal
                        )
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                    }

                    profileSection(title: language == "de" ? "Daten" : "Data") {
                        VStack(spacing: 4) {
                            if let url = exportURL {
                                ShareLink(item: url) {
                                    SettingsRow(icon: "square.and.arrow.up",
                                                label: language == "de" ? "Daten exportieren" : "Export data",
                                                accent: accentBlue,
                                                caption: language == "de"
                                                    ? "\(healthKit.history.count) Tage als CSV"
                                                    : "\(healthKit.history.count) days as CSV") {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Theme.textSecondary.opacity(0.55))
                                    }
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 40)
                            }
                            AboutSetting(language: language)
                                .padding(.vertical, 6)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                    }

                    // FOOTER INFO
                    VStack(spacing: 8) {
                        Text(language == "de"
                             ? "Deine Daten werden lokal auf deinem Gerät gespeichert und für die präzise Berechnung deines Energiebedarfs verwendet."
                             : "Your data is stored locally on your device and used for accurate energy expenditure calculations.")
                            .font(.poppins(size: 12, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.bottom, 50)
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.canvasLift)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 28, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: 28,
            style: .continuous
        ))
        .shadow(color: .black.opacity(0.18), radius: 32, x: 0, y: -8)
    }

    private func profileSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.poppins(size: 12, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 8)
            
            content()
                .background(GlassCardBackground(cornerRadius: 20))
        }
    }

    // MARK: - Kalorien-Ring-Widget (USP)

    private var calorieRingWidget: some View {
        Button {
            if !isSelectedFuture { showActivityBreakdown = true }
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    // 1. Technical Scale (Background Arc)
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(
                            Theme.trackFill,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(135))
                    
                    // 2. Active Progress Arc (Glowing)
                    // Tinted by where the day stands against its 14-day
                    // average: lighter above it, darker below.
                    if !isSelectedFuture {
                        let tint = Theme.ringTint(position: ringPosition)
                        Circle()
                            .trim(from: 0, to: ringProgress * 0.75)
                            .stroke(
                                Theme.ringArcGradient(position: ringPosition,
                                                      progress: ringProgress),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )
                            .rotationEffect(.degrees(135))
                            // Glow in the brand blue that now dominates the
                            // arc — a tinted halo around a mostly blue ring
                            // would colour it far more than the stroke does.
                            .shadow(color: accentBlue.opacity(0.35), radius: 8, x: 0, y: 0)
                            .animation(.easeInOut(duration: 0.55), value: ringPosition)

                        // Small Indicator Bead only today
                        if isSelectedToday {
                            GeometryReader { geo in
                                let angle = Double(ringProgress * 0.75 * 360 + 135)
                                let rad = angle * .pi / 180
                                let radius = geo.size.width / 2
                                let x = radius + radius * cos(rad)
                                let y = radius + radius * sin(rad)

                                Circle()
                                    .fill(.white)
                                    .overlay(Circle().strokeBorder(tint, lineWidth: 1.5))
                                    .frame(width: 8, height: 8)
                                    .shadow(color: tint.opacity(0.5), radius: 3)
                                    .position(x: x, y: y)
                            }
                        }
                    }

                    // 3. Center Instrument Data
                    VStack(spacing: 2) {
                        Text(!isSelectedFuture ? "\(Int(animatedBurn))" : "–")
                            .font(.poppins(size: 42, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                        
                        Text("kcal")
                            .font(.poppins(size: 14, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)

                        // With a goal set the arc fills against it, which makes
                        // the end of the ring *be* the goal — so it needs no
                        // marker of its own, only a name. Without this line a
                        // half-full ring never said half of what.
                        if dailyGoalKcal > 0, !isSelectedFuture {
                            Text(String(format: language == "de" ? "von %d kcal" : "of %d kcal",
                                        Int(dailyGoalKcal)))
                                .font(.poppins(size: 11, weight: .medium))
                                .foregroundStyle(displayBurnedSoFar >= dailyGoalKcal
                                                 ? Theme.segNEAT : Theme.textSecondary.opacity(0.75))
                                .padding(.top, 3)
                        }
                    }
                    .offset(y: -4) // Slight upward shift to center visually in the open arc
                }
                .frame(width: ringSize * 1.15, height: ringSize * 1.15)
                .padding(.top, 20)

                // Tap affordance / Status
                if !isSelectedFuture {
                    HStack(spacing: 6) {
                        Text(language == "de" ? "Aufschlüsselung ansehen" : "View breakdown")
                            .font(.poppins(size: 12, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .opacity(0.8)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(
                            LinearGradient(colors: [Theme.accentSky, accentBlue],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .shadow(color: accentBlue.opacity(0.30), radius: 8, x: 0, y: 4)
                    )
                    .padding(.top, 24)
                    .padding(.bottom, 10)
                } else {
                    Spacer().frame(height: 22)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSelectedFuture)
    }

    // MARK: - KPI-Zeile

    private var caloriesChartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language == "de" ? "Kalorien im Tagesverlauf" : "Calories Throughout the Day")
                        .font(.poppins(size: 15, weight: .semibold))
                        .foregroundStyle(accentBlue)
                    Text(language == "de" ? "kcal pro 30 Minuten" : "kcal per 30 minutes")
                        .font(.poppins(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // The whole card opens the detail view, so this is an
                // affordance, not a second hit target. A filled circle gave it
                // the visual weight of a primary action it never had.
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
                    .padding(.top, 2)
            }

            DailyCalorieAreaChart(
                slots: calorieSlots,
                accentBlue: accentBlue,
                nowFraction: nowFraction,
                isSelectedToday: isSelectedToday,
                sleepEndHour: sleepHours,
                language: language
            )
            .frame(height: LayoutMetrics.chartHeight)

            HStack(spacing: 14) {
                legendItem(color: Theme.slate.opacity(0.55),
                           label: language == "de" ? "Schlafphase" : "Sleep")
                legendItem(color: accentBlue,
                           label: language == "de" ? "Wachphase" : "Awake")
                if healthKit.isAuthorized && !isSelectedFuture && !selectedWorkouts.isEmpty {
                    legendItem(color: Theme.segEAT,
                               label: language == "de" ? "Sport" : "Workout")
                    legendItem(color: Theme.segCaf,
                               label: language == "de" ? "Nachbrennen" : "Afterburn")
                }
            }
        }
        .padding(14)
        .background(GlassCardBackground(cornerRadius: 18))
        .onTapGesture {
            showCalorieDetail = true
        }
        .padding(.horizontal, 10)
    }

    private var activeKPITiles: [DashboardKPI] { DashboardKPI.decode(kpiTilesRaw) }

    /// Puts the goal tile on the row when a goal appears, takes it off again
    /// when the goal goes.
    ///
    /// Without this the setting was almost invisible: the tile is not in the
    /// default row, so switching a goal on changed how full the ring drew and
    /// nothing else, and the one tile that reports the goal had to be found in
    /// a picker first. It goes in front, where the day's own figures are.
    private func syncGoalTile(hasGoal: Bool) {
        var tiles = activeKPITiles
        if hasGoal {
            guard !tiles.contains(.vsGoal) else { return }
            tiles.insert(.vsGoal, at: min(1, tiles.count))
        } else {
            guard tiles.contains(.vsGoal) else { return }
            tiles.removeAll { $0 == .vsGoal }
        }
        kpiTilesRaw = DashboardKPI.encode(tiles)
    }

    /// Adds the PAL tile once to layouts saved before it moved here from the
    /// day narrative. Runs a single time and never touches the row again, so a
    /// user who then removes the tile does not get it back on the next launch.
    private func migrateKPITilesForPAL() {
        guard !kpiPalMigrated else { return }
        kpiPalMigrated = true
        var tiles = activeKPITiles
        guard !tiles.contains(.palFactor) else { return }
        tiles.append(.palFactor)
        kpiTilesRaw = DashboardKPI.encode(tiles)
    }

    /// Hours spent awake so far on the selected day.
    private var wakingHoursElapsed: Double {
        let end = isSelectedToday ? nowFraction : 24.0
        return max(0, end - sleepHours)
    }

    /// Total EPOC across the day's sessions.
    private var afterburnKcalToday: Double {
        activityResult.workoutDetails.reduce(0) { $0 + $1.afterburnKcal }
    }

    /// A share of the day's total, formatted as a percentage.
    private func shareReading(_ value: Double) -> (value: String, tint: Color?) {
        let total = dayComponents(for: selectedDate).total
        guard total > 0 else { return ("–", nil) }
        return (String(format: "%.0f", value / total * 100), nil)
    }

    /// The reading for a tile, plus a tint when the number carries a direction.
    /// "–" wherever the day has no answer: the future, or Health not connected.
    private func kpiReading(_ kpi: DashboardKPI) -> (value: String, tint: Color?) {
        let health = healthKit.isAuthorized && !isSelectedFuture
        let parts  = dayComponents(for: selectedDate)

        switch kpi {
        case .dayEstimate:
            if isSelectedToday  { return ("\(Int(todayProjected))", nil) }
            if isSelectedFuture { return ("\(Int(tdeeResult.tdeeTotal))", nil) }
            return ("\(Int(displayBurnedSoFar))", nil)

        case .activeBurn:
            return (health ? "\(Int(activityResult.totalActiveKcal))" : "–", nil)
        case .neat:
            return (health ? "\(Int(activityResult.neatKcal))" : "–", nil)
        case .eat:
            return (health ? "\(Int(activityResult.eatKcal))" : "–", nil)
        case .bmr:
            return (isSelectedFuture ? "–" : "\(Int(tdeeResult.bmrDynamisch))", nil)
        case .afterburn:
            return (health ? "\(Int(afterburnKcalToday.rounded()))" : "–", nil)

        case .vsYesterday:
            guard !isSelectedFuture else { return ("–", nil) }
            return (String(format: "%+.0f", vsSelectedDayPercent), vsSelectedDayColor)
        case .vsSevenDayAverage:
            guard let percent = vsSevenDayPercent else { return ("–", nil) }
            return (String(format: "%+.0f", percent), percent >= 0 ? .green : .red)
        case .vsFourteenDayAverage:
            guard let percent = vsFourteenDayPercent else { return ("–", nil) }
            return (String(format: "%+.0f", percent), percent >= 0 ? .green : .red)
        case .vsGoal:
            guard dailyGoalKcal > 0, !isSelectedFuture else { return ("–", nil) }
            let reached = displayBurnedSoFar / dailyGoalKcal * 100
            return (String(format: "%.0f", reached), reached >= 100 ? .green : nil)

        case .bmrShare:
            guard !isSelectedFuture else { return ("–", nil) }
            return shareReading(parts.bmr)
        case .activeShare:
            guard health else { return ("–", nil) }
            return shareReading(parts.neat + parts.eat)
        case .neatShare:
            guard health else { return ("–", nil) }
            return shareReading(parts.neat)
        case .eatShare:
            guard health else { return ("–", nil) }
            return shareReading(parts.eat)
        case .tefShare:
            guard !isSelectedFuture else { return ("–", nil) }
            return shareReading(parts.tef)
        case .afterburnShareOfWorkout:
            guard health, parts.eat > 0 else { return ("–", nil) }
            return (String(format: "%.0f", afterburnKcalToday / parts.eat * 100), nil)

        case .palFactor:
            // Total over resting: the classic activity level. Below ~1.4 is a
            // desk day, above ~1.8 a properly active one.
            guard !isSelectedFuture, parts.bmr > 0 else { return ("–", nil) }
            return (String(format: "%.2f", parts.total / parts.bmr), nil)
        case .burnPerWakingHour:
            guard !isSelectedFuture, wakingHoursElapsed > 0.5 else { return ("–", nil) }
            return ("\(Int((displayBurnedSoFar / wakingHoursElapsed).rounded()))", nil)
        case .neatPerThousandSteps:
            // How much each thousand steps is actually worth for this body —
            // the raw step count says nothing on its own.
            guard health, selectedActivity.steps > 0 else { return ("–", nil) }
            let per = parts.neat / Double(selectedActivity.steps) * 1000
            return (String(format: "%.0f", per), nil)
        case .kcalPerKg:
            guard !isSelectedFuture, weightInKg > 0 else { return ("–", nil) }
            return (String(format: "%.1f", displayBurnedSoFar / weightInKg), nil)
        }
    }

    private var kpiRow: some View {
        VStack(spacing: 10) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(Array(activeKPITiles.enumerated()), id: \.element.id) { index, kpi in
                    reorderable(kpi, kpiBox(kpi))
                    .overlay(alignment: .topTrailing) {
                        if isEditingKPIs { removeBadge(for: kpi) }
                    }
                    // Alternating direction so the row wobbles like the
                    // home screen instead of moving as one block.
                    .rotationEffect(.degrees(jiggleAngle(index: index)))
                    .animation(
                        isEditingKPIs
                            ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.15),
                        value: jiggleUp
                    )
                }

                if isEditingKPIs && activeKPITiles.count < DashboardKPI.allCases.count {
                    addTileButton
                }
            }
            .onLongPressGesture(minimumDuration: 0.45) {
                enterKPIEditMode()
            }

            if isEditingKPIs {
                Button(action: exitKPIEditMode) {
                    Text(t.done)
                        .font(.poppins(size: 13, weight: .semibold))
                        .foregroundStyle(accentBlue)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .sensoryFeedback(.impact, trigger: isEditingKPIs)
        .sheet(isPresented: $showKPIPicker) { kpiPickerSheet }
        .sheet(item: $kpiInfoShown, onDismiss: { kpiChartSelection = nil }) {
            kpiDetailSheet($0)
        }
    }

    /// Drag-to-reorder, but only while editing.
    ///
    /// Applied unconditionally the drag would fight the scroll view for every
    /// press, and the tap that opens a tile's history would become a gamble.
    /// The raw value travels as the payload rather than making the enum
    /// Transferable — String already is, and one line of conformance is not
    /// worth a new dependency on UniformTypeIdentifiers.
    @ViewBuilder
    private func reorderable(_ kpi: DashboardKPI, _ tile: some View) -> some View {
        if isEditingKPIs {
            tile
                .draggable(kpi.rawValue) {
                    tile
                        .frame(width: 120)
                        .opacity(0.9)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first,
                          let dragged = DashboardKPI(rawValue: raw) else { return false }
                    moveKPI(dragged, before: kpi)
                    return true
                }
        } else {
            tile
        }
    }

    /// Puts `dragged` where `target` currently sits.
    ///
    /// The insertion index is looked up *after* the removal — taken before, it
    /// would be off by one whenever a tile moves rightwards, which is half of
    /// all drags.
    private func moveKPI(_ dragged: DashboardKPI, before target: DashboardKPI) {
        guard dragged != target else { return }
        var tiles = activeKPITiles
        guard let from = tiles.firstIndex(of: dragged) else { return }
        tiles.remove(at: from)
        let insertAt = tiles.firstIndex(of: target) ?? tiles.count
        tiles.insert(dragged, at: insertAt)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            kpiTilesRaw = DashboardKPI.encode(tiles)
        }
    }

    private func jiggleAngle(index: Int) -> Double {
        guard isEditingKPIs else { return 0 }
        let magnitude = jiggleUp ? 1.1 : -1.1
        return index.isMultiple(of: 2) ? magnitude : -magnitude
    }

    private func enterKPIEditMode() {
        guard !isEditingKPIs else { return }
        jiggleUp = false
        withAnimation(.easeOut(duration: 0.2)) { isEditingKPIs = true }
        withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) {
            jiggleUp = true
        }
    }

    /// Clearing jiggleUp as well is what lets the tiles settle: the rotation
    /// animates on that value, so leaving it set would freeze them mid-tilt.
    private func exitKPIEditMode() {
        withAnimation(.easeOut(duration: 0.18)) {
            isEditingKPIs = false
            jiggleUp = false
        }
    }

    private func removeBadge(for kpi: DashboardKPI) -> some View {
        Button {
            var tiles = activeKPITiles
            // One tile has to survive, or the row disappears with no way back.
            guard tiles.count > 1 else { return }
            tiles.removeAll { $0 == kpi }
            withAnimation(.easeOut(duration: 0.2)) {
                kpiTilesRaw = DashboardKPI.encode(tiles)
            }
        } label: {
            Image(systemName: "minus")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.red))
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(activeKPITiles.count <= 1)
        .opacity(activeKPITiles.count <= 1 ? 0.35 : 1)
        .offset(x: 6, y: -6)
    }

    private var addTileButton: some View {
        Button {
            showKPIPicker = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                Text(language == "de" ? "Hinzufügen" : "Add")
                    .font(.poppins(size: 11, weight: .medium))
            }
            .foregroundStyle(accentBlue)
            .frame(maxWidth: .infinity, minHeight: 128)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        accentBlue.opacity(0.45),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kachel-Detail

    /// Explanation plus a fortnight of the same figure as a column chart —
    /// days along the x-axis, the value up the y-axis. Columns rather than a
    /// line on purpose: each day is a separate measurement, not a sample of a
    /// continuous curve, and a day with no data shows as an honest gap
    /// instead of being interpolated over.
    private func kpiDetailSheet(_ kpi: DashboardKPI) -> some View {
        let calendar = Calendar.current
        let days: [(date: Date, value: Double?)] = (0..<14).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: selectedDate)
            else { return nil }
            return (date, kpiNumericValue(kpi, on: date))
        }
        let known = days.compactMap(\.value)
        let average = known.isEmpty ? nil : known.reduce(0, +) / Double(known.count)
        let unit = kpi.tableUnit(language: language)

        return NavigationStack {
            ZStack {
                CaloricBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(kpi.explanation(language: language))
                            .font(.poppins(size: 13, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .glassCard(16)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(language == "de" ? "Letzte 14 Tage" : "Last 14 days")
                                    .font(.poppins(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if let average {
                                    Text((language == "de" ? "Ø " : "avg ")
                                         + kpi.formatted(average) + (unit.isEmpty ? "" : " " + unit))
                                        .font(.poppins(size: 12, weight: .medium))
                                        .foregroundStyle(accentBlue)
                                }
                            }

                            if let caption = kpi.tableCaption(language: language) {
                                Text(caption)
                                    .font(.poppins(size: 11, weight: .regular))
                                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Chart {
                                ForEach(Array(days.enumerated()), id: \.offset) { _, row in
                                    if let value = row.value {
                                        BarMark(
                                            x: .value("Tag", row.date, unit: .day),
                                            y: .value(unit.isEmpty ? "Wert" : unit, value)
                                        )
                                        .foregroundStyle(
                                            calendar.isDate(row.date, inSameDayAs: selectedDate)
                                                ? AnyShapeStyle(Theme.accentGradient)
                                                : AnyShapeStyle(accentBlue.opacity(0.45))
                                        )
                                        .cornerRadius(3)
                                    }
                                }

                                if let average {
                                    RuleMark(y: .value("Ø", average))
                                        .foregroundStyle(Theme.textSecondary.opacity(0.45))
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                }

                                // Same bubble the day chart on the overview
                                // uses, hung off an invisible rule so it
                                // tracks the touched column.
                                if let picked = kpiChartSelection,
                                   let row = days.first(where: {
                                       calendar.isDate($0.date, inSameDayAs: picked)
                                   }) {
                                    RuleMark(x: .value("Auswahl", row.date, unit: .day))
                                        .foregroundStyle(.clear)
                                        .annotation(
                                            position: .top,
                                            spacing: 6,
                                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                                        ) {
                                            kpiChartBubble(kpi, date: row.date,
                                                           value: row.value, unit: unit)
                                        }
                                }
                            }
                            .frame(height: 200)
                            .chartOverlay { proxy in
                                GeometryReader { geo in
                                    Rectangle().fill(.clear).contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { drag in
                                                    let origin = geo[proxy.plotAreaFrame].origin
                                                    let x = drag.location.x - origin.x
                                                    guard let touched: Date = proxy.value(atX: x)
                                                    else { return }
                                                    // Nearest column, so a touch
                                                    // between two bars still picks one.
                                                    let nearest = days.min {
                                                        abs($0.date.timeIntervalSince(touched))
                                                            < abs($1.date.timeIntervalSince(touched))
                                                    }
                                                    withAnimation(.easeOut(duration: 0.08)) {
                                                        kpiChartSelection = nearest?.date
                                                    }
                                                }
                                                .onEnded { _ in
                                                    withAnimation(.easeOut(duration: 0.2)) {
                                                        kpiChartSelection = nil
                                                    }
                                                }
                                        )
                                }
                            }
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                                    AxisValueLabel(format: .dateTime.day().month(.defaultDigits),
                                                   centered: true)
                                        .font(.poppins(size: 9, weight: .regular))
                                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                                    AxisGridLine().foregroundStyle(.clear)
                                }
                            }
                            .chartYAxis {
                                AxisMarks(position: .leading) { _ in
                                    AxisGridLine().foregroundStyle(Theme.divider)
                                    AxisValueLabel()
                                        .font(.poppins(size: 9, weight: .regular))
                                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                                }
                            }
                            .padding(14)
                            .glassCard(16)
                        }

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle(kpi.title(language: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t.done) { kpiInfoShown = nil }
                        .foregroundStyle(accentBlue)
                        .fontWeight(.semibold)
                }
            }
        }
        .caloricAppearance()
        .presentationDetents([.large])
        .presentationBackground(Theme.canvas)
    }

    /// Reads exactly like the tooltip on the overview's day chart: one dark
    /// capsule, white text, date and value separated by a middot.
    private func kpiChartBubble(_ kpi: DashboardKPI, date: Date,
                                value: Double?, unit: String) -> some View {
        let reading = value.map { kpi.formatted($0) + (unit.isEmpty ? "" : " " + unit) }
            ?? (language == "de" ? "keine Daten" : "no data")
        return Text("\(kpiBubbleDateFormatter.string(from: date)) · \(reading)")
            .font(.poppins(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(isDark ? Color(white: 0.22) : Color(white: 0.12)))
    }

    private var kpiBubbleDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: language == "de" ? "de_DE" : "en_US")
        f.setLocalizedDateFormatFromTemplate("EEEEd.M.")
        return f
    }

    private var kpiPickerSheet: some View {
        let available = DashboardKPI.allCases.filter { !activeKPITiles.contains($0) }
        return NavigationStack {
            ZStack {
                CaloricBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(available) { kpi in
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    kpiTilesRaw = DashboardKPI.encode(activeKPITiles + [kpi])
                                }
                                showKPIPicker = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: kpi.icon)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(accentBlue)
                                        .frame(width: 38, height: 38)
                                        .background(Circle().fill(accentBlue.opacity(0.13)))
                                    // Name only. The live value underneath was
                                    // noise here — this list is for choosing
                                    // which tiles to keep, and today's reading
                                    // says nothing about whether a tile is
                                    // worth a place on the dashboard.
                                    Text(kpi.title(language: language))
                                        .font(.poppins(size: 14, weight: .medium))
                                        .foregroundStyle(Theme.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(accentBlue)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Theme.card)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if available.isEmpty {
                            Text(language == "de"
                                 ? "Alle Kacheln sind bereits auf dem Dashboard."
                                 : "Every tile is already on the dashboard.")
                                .font(.poppins(size: 13, weight: .regular))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.top, 40)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
            }
            .navigationTitle(language == "de" ? "Kachel hinzufügen" : "Add tile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t.done) { showKPIPicker = false }
                        .foregroundStyle(accentBlue)
                        .fontWeight(.semibold)
                }
            }
        }
        .caloricAppearance()
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.canvas)
    }

    private func kpiBox(_ kpi: DashboardKPI) -> some View {
        let reading = kpiReading(kpi)
        let iconColor: Color = reading.tint ?? accentBlue
        let valueFg: Color  = reading.tint ?? Theme.textPrimary
        let value = reading.value
        let unit  = kpi.title(language: language)
        return VStack(alignment: .leading, spacing: 5) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.13))
                    .frame(width: 40, height: 40)
                Image(systemName: kpi.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            Spacer(minLength: 10)
            Text(value)
                .font(.poppins(size: 21, weight: .bold))
                .foregroundStyle(valueFg)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            // Labels like "Schätzung für den kompletten Tag" never fit one
            // line at a third of the screen width, so they were being cut off.
            // The space is reserved either way — otherwise a one-line label
            // would make its tile shorter than the two next to it.
            Text(unit)
                .font(.poppins(size: 11, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.card)
                .shadow(color: Theme.cardShadow, radius: 12, x: 0, y: 4)
        )
        // A chart glyph rather than an "i": the sheet behind it carries a
        // fortnight of history, and an info mark would promise only a
        // definition. Hidden in edit mode, where the remove badge owns this
        // corner and two controls a thumb apart would be a coin toss.
        .overlay(alignment: .topTrailing) {
            if !isEditingKPIs {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.4))
                    .padding(10)
            }
        }
        // The whole tile is the target, not just the glyph — a 40pt corner is
        // a poor hit area for the one thing every tile can do.
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            guard !isEditingKPIs else { return }
            kpiInfoShown = kpi
        }
    }

    // MARK: - Workout Name

    private func workoutActivityName(_ type: HKWorkoutActivityType) -> String {
        if language == "de" {
            switch type {
            case .running:                          return "Laufen"
            case .cycling:                          return "Radfahren"
            case .swimming:                         return "Schwimmen"
            case .traditionalStrengthTraining:      return "Krafttraining"
            case .functionalStrengthTraining:       return "Functional Training"
            case .highIntensityIntervalTraining:    return "HIIT"
            case .yoga:                             return "Yoga"
            case .hiking:                           return "Wandern"
            case .walking:                          return "Gehen"
            case .elliptical:                       return "Elliptical"
            case .rowing:                           return "Rudern"
            case .tennis:                           return "Tennis"
            case .soccer:                           return "Fußball"
            case .basketball:                       return "Basketball"
            case .dance:                            return "Tanzen"
            case .pilates:                          return "Pilates"
            case .crossTraining:                    return "Cross Training"
            case .stairClimbing:                    return "Treppensteigen"
            default:                                return "Sport"
            }
        } else {
            switch type {
            case .running:                          return "Running"
            case .cycling:                          return "Cycling"
            case .swimming:                         return "Swimming"
            case .traditionalStrengthTraining:      return "Strength Training"
            case .functionalStrengthTraining:       return "Functional Training"
            case .highIntensityIntervalTraining:    return "HIIT"
            case .yoga:                             return "Yoga"
            case .hiking:                           return "Hiking"
            case .walking:                          return "Walking"
            case .elliptical:                       return "Elliptical"
            case .rowing:                           return "Rowing"
            case .tennis:                           return "Tennis"
            case .soccer:                           return "Soccer"
            case .basketball:                       return "Basketball"
            case .dance:                            return "Dance"
            case .pilates:                          return "Pilates"
            case .crossTraining:                    return "Cross Training"
            case .stairClimbing:                    return "Stair Climbing"
            default:                                return "Workout"
            }
        }
    }

    // MARK: - Legende

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 14, height: 9)
            Text(label)
                .font(.poppins(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Edit Sheet

    @ViewBuilder
    private func editFieldSheet() -> some View {
        NavigationStack {
            Group {
                switch editingField {
                case "weight":     weightEditView
                case "height":     heightEditView
                case "bodyFat":    bodyFatEditView
                case "conditions": conditionsEditView
                default:           EmptyView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t.done) { editingField = nil }
                        .foregroundStyle(accentBlue)
                        .fontWeight(.semibold)
                }
            }
        }
        .caloricAppearance()
        .presentationDetents([.medium, .large])
    }

    // MARK: - Gewicht

    private var weightEditView: some View {
        VStack(spacing: 28) {
            Picker("Einheit", selection: $weightUnit) {
                Text("kg").tag("kg")
                Text("lb").tag("lb")
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .onChange(of: weightUnit) {
                if weightUnit == "lb" {
                    editWeightLb = max(44, min(661, Int((Double(editWeightKg) * 2.20462).rounded())))
                    weightText = "\(editWeightLb)"
                } else {
                    editWeightKg = max(20, min(300, Int((Double(editWeightLb) / 2.20462).rounded())))
                    weightText = "\(editWeightKg)"
                }
            }

            HStack(spacing: 4) {
                Spacer()
                if weightUnit == "kg" {
                    Picker("", selection: $editWeightKg) {
                        ForEach(20...300, id: \.self) { v in Text("\(v)").tag(v) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 110, height: 180)
                    .clipped()
                    .onChange(of: editWeightKg) { weightText = "\(editWeightKg)" }
                } else {
                    Picker("", selection: $editWeightLb) {
                        ForEach(44...661, id: \.self) { v in Text("\(v)").tag(v) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 110, height: 180)
                    .clipped()
                    .onChange(of: editWeightLb) { weightText = "\(editWeightLb)" }
                }
                Text(weightUnit)
                    .font(.poppins(size: 24, weight: .semibold))
                    .foregroundStyle(accentBlue)
                    .frame(width: 36, alignment: .leading)
                Spacer()
            }
        }
        .padding()
        .navigationTitle(language == "de" ? "Gewicht ändern" : "Edit Weight")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let val = Int(Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 70.0)
            if weightUnit == "kg" {
                editWeightKg = max(20, min(300, val))
            } else {
                editWeightLb = max(44, min(661, val))
            }
        }
    }

    // MARK: - Größe

    private var heightEditView: some View {
        VStack(spacing: 28) {
            Picker("Einheit", selection: $heightUnit) {
                Text("cm").tag("cm")
                Text("ft").tag("ft")
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .onChange(of: heightUnit) {
                if heightUnit == "ft" {
                    let totalInches = Int((Double(editHeightCm) / 2.54).rounded())
                    editHeightFeet = max(3, min(8, totalInches / 12))
                    editHeightInches = max(0, min(11, totalInches % 12))
                    heightText = "\(editHeightFeet)'\(editHeightInches)\""
                } else {
                    editHeightCm = max(100, min(230, Int((Double(editHeightFeet * 12 + editHeightInches) * 2.54).rounded())))
                    heightText = "\(editHeightCm)"
                }
            }

            if heightUnit == "cm" {
                HStack(spacing: 4) {
                    Spacer()
                    Picker("", selection: $editHeightCm) {
                        ForEach(100...230, id: \.self) { v in Text("\(v)").tag(v) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 110, height: 180)
                    .clipped()
                    .onChange(of: editHeightCm) { heightText = "\(editHeightCm)" }
                    Text("cm")
                        .font(.poppins(size: 24, weight: .semibold))
                        .foregroundStyle(accentBlue)
                        .frame(width: 44, alignment: .leading)
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    Spacer()
                    Picker("", selection: $editHeightFeet) {
                        ForEach(3...8, id: \.self) { v in Text("\(v)").tag(v) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 180)
                    .clipped()
                    .onChange(of: editHeightFeet) { heightText = "\(editHeightFeet)'\(editHeightInches)\"" }
                    Text("ft")
                        .font(.poppins(size: 22, weight: .semibold))
                        .foregroundStyle(accentBlue)
                    Picker("", selection: $editHeightInches) {
                        ForEach(0...11, id: \.self) { v in Text("\(v)").tag(v) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 180)
                    .clipped()
                    .onChange(of: editHeightInches) { heightText = "\(editHeightFeet)'\(editHeightInches)\"" }
                    Text("in")
                        .font(.poppins(size: 22, weight: .semibold))
                        .foregroundStyle(accentBlue)
                    Spacer()
                }
            }
        }
        .padding()
        .navigationTitle(language == "de" ? "Größe ändern" : "Edit Height")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if heightUnit == "cm" {
                editHeightCm = max(100, min(230, Int(Double(heightText) ?? 170.0)))
            } else {
                let parts = heightText.components(separatedBy: CharacterSet(charactersIn: "'\""))
                    .compactMap { Int($0) }
                editHeightFeet = max(3, min(8, parts.first ?? 5))
                editHeightInches = max(0, min(11, parts.dropFirst().first ?? 9))
            }
        }
    }

    // MARK: - KFA

    private var bodyFatEditView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer().frame(height: 8)

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        if knowsBodyFat == true { knowsBodyFat = nil; bodyFatText = "" }
                        else { knowsBodyFat = true }
                    }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 24))
                        Text(t.yes)
                            .font(.poppins(size: 18, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .foregroundStyle(knowsBodyFat == true ? .white : accentBlue)
                    .background(RoundedRectangle(cornerRadius: 16)
                        .fill(knowsBodyFat == true ? accentBlue : accentBlue.opacity(controlAlpha)))
                }
                .buttonStyle(.plain)

                if knowsBodyFat == true {
                    VStack(spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            TextField("15", text: $bodyFatText)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .font(.poppins(size: 56, weight: .semibold))
                                .foregroundStyle(accentBlue)
                                .multilineTextAlignment(.center)
                                .frame(width: 140)
                            Text("%")
                                .font(.poppins(size: 22, weight: .regular))
                                .foregroundStyle(accentBlue.opacity(0.6))
                        }
                    }
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button {
                    showBodyFatHelp = true
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 24))
                        Text(t.no)
                            .font(.poppins(size: 18, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .foregroundStyle(accentBlue)
                    .background(RoundedRectangle(cornerRadius: 16)
                        .fill(accentBlue.opacity(controlAlpha)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .navigationTitle("KFA / BF%")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.22), value: knowsBodyFat)
        .sheet(isPresented: $showBodyFatHelp) {
            BodyFatHelpView(
                accentBlue: accentBlue,
                t: t,
                heightInCm: heightInCm,
                selectedGender: selectedGender,
                femaleText: femaleText
            ) { estimatedFat in
                bodyFatText = estimatedFat
                knowsBodyFat = true
                showBodyFatHelp = false
            }
        }
    }

    // MARK: - Besonderheiten

    private var conditionsEditView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 8)

                questionnaireSectionCard(title: t.thyroidSectionTitle) {
                    VStack(spacing: 8) {
                        metabolismChoiceButton(label: t.thyroidHypo, isSelected: thyroidCondition == "hypo") {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                if thyroidCondition == "hypo" { thyroidCondition = nil }
                                else { thyroidCondition = "hypo"; thyroidWellControlled = nil; selectedHypoSymptoms = []; selectedHyperSymptoms = [] }
                            }
                        }
                        metabolismChoiceButton(label: t.thyroidHyper, isSelected: thyroidCondition == "hyper") {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                if thyroidCondition == "hyper" { thyroidCondition = nil }
                                else { thyroidCondition = "hyper"; thyroidWellControlled = nil; selectedHypoSymptoms = []; selectedHyperSymptoms = [] }
                            }
                        }
                        metabolismChoiceButton(label: t.thyroidNone, isSelected: thyroidCondition == "none") {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                if thyroidCondition == "none" { thyroidCondition = nil }
                                else { thyroidCondition = "none"; thyroidWellControlled = nil; selectedHypoSymptoms = []; selectedHyperSymptoms = [] }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)

                if thyroidCondition == "hypo" || thyroidCondition == "hyper" {
                    questionnaireSectionCard(title: t.thyroidTherapyQuestion) {
                        VStack(spacing: 8) {
                            metabolismChoiceButton(label: t.thyroidOptimal, isSelected: thyroidWellControlled == true) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    if thyroidWellControlled == true { thyroidWellControlled = nil }
                                    else { thyroidWellControlled = true; selectedHypoSymptoms = []; selectedHyperSymptoms = [] }
                                }
                            }
                            metabolismChoiceButton(label: t.thyroidNotOptimal, isSelected: thyroidWellControlled == false) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    thyroidWellControlled = thyroidWellControlled == false ? nil : false
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if thyroidCondition == "hypo" && thyroidWellControlled == false {
                    questionnaireSectionCard(title: t.thyroidSymptomQuestion) {
                        VStack(spacing: 8) {
                            ForEach([t.hypoSymptomFatigue, t.hypoSymptomWeightGain, t.hypoSymptomCold, t.hypoSymptomSlow, t.hypoSymptomHair], id: \.self) { symptom in
                                metabolismCheckbox(label: symptom, isSelected: selectedHypoSymptoms.contains(symptom)) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        if selectedHypoSymptoms.contains(symptom) { selectedHypoSymptoms.remove(symptom) }
                                        else { selectedHypoSymptoms.insert(symptom) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if thyroidCondition == "hyper" && thyroidWellControlled == false {
                    questionnaireSectionCard(title: t.thyroidSymptomQuestion) {
                        VStack(spacing: 8) {
                            ForEach(
                                selectedGender == femaleText
                                    ? [t.hyperSymptomHeat, t.hyperSymptomWeightLoss, t.hyperSymptomHeart, t.hyperSymptomPeriod]
                                    : [t.hyperSymptomHeat, t.hyperSymptomWeightLoss, t.hyperSymptomHeart],
                                id: \.self
                            ) { symptom in
                                metabolismCheckbox(label: symptom, isSelected: selectedHyperSymptoms.contains(symptom)) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        if selectedHyperSymptoms.contains(symptom) { selectedHyperSymptoms.remove(symptom) }
                                        else { selectedHyperSymptoms.insert(symptom) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if selectedGender == femaleText {
                    questionnaireSectionCard(title: t.pcosSectionTitle) {
                        VStack(spacing: 8) {
                            metabolismChoiceButton(label: t.pcosYes, isSelected: hasPCOS == true) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    if hasPCOS == true { hasPCOS = nil }
                                    else { hasPCOS = true; pcosInsulinResistance = nil; selectedPCOSSymptoms = [] }
                                }
                            }
                            metabolismChoiceButton(label: t.pcosNo, isSelected: hasPCOS == false) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    if hasPCOS == false { hasPCOS = nil }
                                    else { hasPCOS = false; pcosInsulinResistance = nil; selectedPCOSSymptoms = [] }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                }

                if selectedGender == femaleText && hasPCOS == true {
                    questionnaireSectionCard(title: t.pcosInsulinQuestion) {
                        VStack(spacing: 8) {
                            metabolismChoiceButton(label: t.pcosInsulinYes, isSelected: pcosInsulinResistance == true) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    if pcosInsulinResistance == true { pcosInsulinResistance = nil }
                                    else { pcosInsulinResistance = true; selectedPCOSSymptoms = [] }
                                }
                            }
                            metabolismChoiceButton(label: t.pcosInsulinNo, isSelected: pcosInsulinResistance == false) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    pcosInsulinResistance = pcosInsulinResistance == false ? nil : false
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if selectedGender == femaleText && hasPCOS == true && pcosInsulinResistance == false {
                    questionnaireSectionCard(title: t.pcosSymptomQuestion) {
                        VStack(spacing: 8) {
                            ForEach([t.pcosSymptomIrregular, t.pcosSymptomBlocked, t.pcosSymptomCarbFatigue, t.pcosSymptomHair], id: \.self) { symptom in
                                metabolismCheckbox(label: symptom, isSelected: selectedPCOSSymptoms.contains(symptom)) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        if selectedPCOSSymptoms.contains(symptom) { selectedPCOSSymptoms.remove(symptom) }
                                        else { selectedPCOSSymptoms.insert(symptom) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button {
                    metabolismFactor = computedConditionFactor
                    editingField = nil
                } label: {
                    Text(language == "de" ? "Übernehmen" : "Apply")
                        .font(.poppins(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(conditionQuestionnaireDone ? accentBlue : accentBlue.opacity(0.35))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!conditionQuestionnaireDone)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 10)
        }
        .navigationTitle(language == "de" ? "Besonderheiten" : "Conditions")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: thyroidCondition)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: thyroidWellControlled)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: hasPCOS)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: pcosInsulinResistance)
    }

    private func conditionPresetRow(label: String, icon: String, preset: Double) -> some View {
        let isSelected = selectedConditions.contains(label)
        let isNoCondition = (label == noConditionText)
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                selectedConditions = [label]
                metabolismFactor = preset
            }
        } label: {
            HStack(spacing: 14) {
                if !isNoCondition {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .frame(width: 28)
                        .foregroundStyle(isSelected ? .white : accentBlue)
                }
                Text(label)
                    .font(.poppins(size: 15, weight: .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? accentBlue : accentBlue.opacity(isDark ? 0.22 : 0.08))
            )
        }
        .buttonStyle(.plain)
    }

    private func questionnaireSectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.poppins(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(accentBlue.opacity(cardAlpha))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(accentBlue.opacity(borderAlpha), lineWidth: 1)
                )
        )
    }

    private func metabolismChoiceButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.poppins(size: 14, weight: .regular))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isSelected ? .white : accentBlue)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? accentBlue : accentBlue.opacity(controlAlpha))
            )
        }
    }

    private func metabolismCheckbox(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.poppins(size: 14, weight: .regular))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isSelected ? .white : accentBlue)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? accentBlue : accentBlue.opacity(controlAlpha))
            )
        }
    }
}

struct InfographicHeroCard: View {
    let title: String
    var subtitle: String? = nil
    var description: String? = nil
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(color)
            VStack(spacing: 4) {
                Text(title)
                    .font(.poppins(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.poppins(size: 12, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            if let desc = description {
                Text(desc)
                    .font(.poppins(size: 12, weight: .regular))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.poppins(size: 38, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(unit)
                    .font(.poppins(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(color.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: color.opacity(0.1), radius: 20, x: 0, y: 10)
        )
    }
}

struct InfographicMathCard: View {
    let title: String
    var formula: String? = nil
    let value: String
    let color: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.poppins(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let formula {
                    Text(formula)
                        .font(.poppins(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Text(value)
                .font(.poppins(size: 16, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.divider, lineWidth: 1)
                )
        )
    }
}

struct InfographicSegmentBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        let value: Double
        let color: Color
        let label: String
    }
    let segments: [Segment]
    let total: Double

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(segments) { seg in
                        if seg.value > 0 {
                            Rectangle()
                                .fill(seg.color)
                                .frame(width: max(0, geo.size.width * CGFloat(seg.value / max(total, 1))))
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            
            HStack(spacing: 12) {
                ForEach(segments) { seg in
                    if seg.value > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(seg.color).frame(width: 8, height: 8)
                            Text("\(seg.label) \(Int((seg.value / max(total, 1)) * 100))%")
                                .font(.poppins(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card.opacity(0.4))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.divider, lineWidth: 1))
        )
    }
}

// MARK: - Dashboard KPI tiles

/// The KPIs available for the dashboard row.
///
/// Lives here rather than in its own file because a new file has to be
/// registered in project.pbxproj by hand in four places, and this project
/// carries no filesystem-synchronised groups to do it automatically.
enum DashboardKPI: String, CaseIterable, Identifiable {
    // Totals the app computes itself.
    case dayEstimate
    case activeBurn
    case neat
    case eat
    case bmr
    case afterburn

    // Comparisons against the user's own history.
    case vsYesterday
    case vsSevenDayAverage
    case vsFourteenDayAverage
    /// Only meaningful once a goal is set; reads "–" until then.
    case vsGoal

    // Composition — how the day's energy is split.
    case bmrShare
    case activeShare
    case neatShare
    case eatShare
    case tefShare
    case afterburnShareOfWorkout

    // Rates and efficiency.
    case palFactor
    case burnPerWakingHour
    case neatPerThousandSteps
    case kcalPerKg

    var id: String { rawValue }

    /// The three the dashboard has always shown.
    static let defaultRaw = "dayEstimate,vsYesterday,activeShare,palFactor"

    static func decode(_ raw: String) -> [DashboardKPI] {
        let parsed = raw.split(separator: ",").compactMap { DashboardKPI(rawValue: String($0)) }
        // Never hand back an empty row — a layout that lost every entry to a
        // renamed case would otherwise leave the dashboard blank.
        return parsed.isEmpty ? decode(defaultRaw) : parsed
    }

    static func encode(_ tiles: [DashboardKPI]) -> String {
        tiles.map(\.rawValue).joined(separator: ",")
    }

    var icon: String {
        switch self {
        case .dayEstimate:              return "target"
        case .activeBurn:               return "bolt.fill"
        case .neat:                     return "figure.walk"
        case .eat:                      return "dumbbell.fill"
        case .bmr:                      return "moon.zzz.fill"
        case .afterburn:                return "flame.fill"
        case .vsYesterday:              return "arrow.up.arrow.down"
        case .vsSevenDayAverage:        return "chart.line.uptrend.xyaxis"
        case .vsFourteenDayAverage:     return "chart.bar.xaxis"
        case .vsGoal:                   return "target"
        case .bmrShare:                 return "chart.pie.fill"
        case .activeShare:              return "bolt.circle.fill"
        case .neatShare:                return "figure.walk.circle.fill"
        case .eatShare:                 return "figure.strengthtraining.traditional"
        case .tefShare:                 return "fork.knife"
        case .afterburnShareOfWorkout:  return "flame.circle.fill"
        case .palFactor:                return "gauge.with.dots.needle.67percent"
        case .burnPerWakingHour:        return "clock.arrow.circlepath"
        case .neatPerThousandSteps:     return "shoeprints.fill"
        case .kcalPerKg:                return "scalemass.fill"
        }
    }

    func title(language: String) -> String {
        let de = language == "de"
        switch self {
        case .dayEstimate:   return de ? "Schätzung für den kompletten Tag" : "Estimate for the full day"
        case .activeBurn:    return de ? "Aktiver Kalorienverbrauch" : "Active calorie burn"
        case .neat:          return de ? "NEAT" : "NEAT"
        case .eat:           return de ? "EAT" : "EAT"
        case .bmr:           return de ? "Grundumsatz" : "Basal metabolic rate"
        case .afterburn:     return de ? "EPOC" : "EPOC"

        case .vsYesterday:          return de ? "% vs. Gestern" : "% vs. yesterday"
        case .vsSevenDayAverage:    return de ? "% vs. Ø 7 Tage" : "% vs. 7-day avg"
        case .vsFourteenDayAverage: return de ? "% vs. Ø 14 Tage" : "% vs. 14-day avg"
        case .vsGoal:               return de ? "% vom Tagesziel" : "% of daily goal"

        case .bmrShare:    return de ? "% Grundumsatz am Tag" : "% basal of the day"
        case .activeShare: return de ? "% Aktivanteil am Tag" : "% active of the day"
        case .neatShare:   return de ? "% Alltag am Tag" : "% everyday of the day"
        case .eatShare:    return de ? "% Sport am Tag" : "% workout of the day"
        case .tefShare:    return de ? "% Verdauung am Tag" : "% digestion of the day"
        case .afterburnShareOfWorkout:
            return de ? "% Nachbrennen am Sport" : "% afterburn of workout"

        case .palFactor:            return de ? "PAL" : "PAL"
        case .burnPerWakingHour:    return de ? "kcal je Wachstunde" : "kcal per waking hour"
        case .neatPerThousandSteps: return de ? "kcal je 1.000 Schritte" : "kcal per 1,000 steps"
        case .kcalPerKg:            return de ? "kcal je kg Körpergewicht" : "kcal per kg body weight"
        }
    }

    /// Unit shown beside each value in the history table.
    ///
    /// The three comparison tiles have no history of their own — a fortnight
    /// of "% versus the day before" would be a column of second derivatives.
    /// They show the day total they are derived from, so their unit is kcal.
    func tableUnit(language: String) -> String {
        switch self {
        case .palFactor:
            return ""
        case .bmrShare, .activeShare, .neatShare, .eatShare, .tefShare,
             .afterburnShareOfWorkout, .vsGoal:
            return "%"
        default:
            return "kcal"
        }
    }

    /// Set only where the table shows something other than the tile itself.
    func tableCaption(language: String) -> String? {
        let de = language == "de"
        switch self {
        case .vsYesterday, .vsSevenDayAverage, .vsFourteenDayAverage, .vsGoal:
            return de ? "Tagesverbrauch, aus dem der Vergleich entsteht"
                      : "The daily burn the comparison is drawn from"
        case .burnPerWakingHour:
            return de ? "kcal je Stunde wach" : "kcal per hour awake"
        default:
            return nil
        }
    }

    func formatted(_ value: Double) -> String {
        switch self {
        case .palFactor: return String(format: "%.2f", value)
        case .kcalPerKg: return String(format: "%.1f", value)
        default:         return String(format: "%.0f", value)
        }
    }

    /// One or two sentences behind the little "i".
    ///
    /// Several of these are ratios whose name gives nothing away — PAL above
    /// all. A number nobody can interpret is decoration, so every tile can
    /// explain itself.
    func explanation(language: String) -> String {
        let de = language == "de"
        switch self {
        case .dayEstimate:
            return de ? "Was du an diesem Tag voraussichtlich insgesamt verbrennst. Inklusive Grundumsatz, Alltag, Sport und Verdauung zusammen."
                      : "The total number of calories you're expected to burn that day. This includes your basal metabolic rate, daily activities, exercise, and digestion combined."
        case .activeBurn:
            return de ? "Alles, was durch Bewegung dazukam: Alltagsbewegung plus Training. Ohne Grundumsatz."
                      : "Everything movement added: everyday activity plus training. Basal burn excluded."
        case .neat:
            return de ? "Alltagsbewegung außerhalb des Trainings. Inklusive Gehen, Stehen, Treppen, Unruhe. Oft der größte Hebel im Tag."
                      : "Everyday physical activity outside of exercise. This includes walking, standing, climbing stairs, and moving around. Often the most effective way to stay active throughout the day."
        case .eat:
            return de ? "Was deine Trainingseinheiten gekostet haben, Nachbrennen eingerechnet."
                      : "What your sessions cost, afterburn included."
        case .bmr:
            return de ? "Was dein Körper in Ruhe braucht, nur um zu laufen. Ändert sich von Tag zu Tag kaum."
                      : "What your body needs at rest just to keep running. Barely moves day to day."
        case .afterburn:
            return de ? "Der Nachbrenneffekt: erhöhter Verbrauch nach dem Training. Geschätzt, nicht gemessen."
                      : "The afterburn: raised expenditure once a session ends. Estimated, not measured."

        case .vsYesterday:
            return de ? "Wie dieser Tag gegenüber dem Vortag steht. Läuft der Tag noch, wird nur die bisherige Zeit verglichen."
                      : "How this day stands against the one before. While the day is still running, only the elapsed part is compared."
        case .vsSevenDayAverage:
            return de ? "Wie dieser Tag gegenüber dem Schnitt deiner letzten sieben Tage steht."
                      : "How this day stands against your last seven days."
        case .vsFourteenDayAverage:
            return de ? "Wie dieser Tag gegenüber dem Schnitt deiner letzten vierzehn Tage steht. Derselbe Wert färbt den Ring."
                      : "How this day stands against your last fourteen days. The same figure tints the ring."
        case .vsGoal:
            return de ? "Wie viel deines Tagesziels du bisher verbrannt hast. Das Ziel setzt du in den Einstellungen; ohne Ziel bleibt die Kachel leer."
                      : "How much of your daily goal you have burnt so far. The goal is set in the settings; without one the tile stays empty."

        case .bmrShare:
            return de ? "Wie viel Prozent des Tages allein auf den Grundumsatz entfallen. Ein hoher Wert heißt: ruhiger Tag."
                      : "How much of the day was basal burn alone. A high figure means a quiet day."
        case .activeShare:
            return de ? "Wie viel Prozent des Tages du dir durch Bewegung verdient hast. Alltag und Sport zusammen."
                      : "How much of the day you earned through movement. Everyday activity and training together."
        case .neatShare:
            return de ? "Der Anteil des Tages, der aus Alltagsbewegung kam."
                      : "The share of the day that came from everyday movement."
        case .eatShare:
            return de ? "Der Anteil des Tages, der aus Training kam."
                      : "The share of the day that came from training."
        case .tefShare:
            return de ? "Der Anteil, den die Verdauung deiner Mahlzeiten gekostet hat. Nur belastbar, wenn du gegessen eingetragen hast."
                      : "The share digestion cost. Only meaningful on days you logged what you ate."
        case .afterburnShareOfWorkout:
            return de ? "Wie viel deiner Trainingskalorien erst nach der Einheit anfallen."
                      : "How much of your training burn lands after the session rather than during it."

        case .palFactor:
            return de ? "Dein Tagesverbrauch geteilt durch deinen Grundumsatz. Um 1,4 ist ein Schreibtischtag, ab etwa 1,8 ein richtig aktiver. Unabhängig von Größe und Gewicht, deshalb über Tage hinweg gut vergleichbar."
                      : "Your day's burn divided by your basal rate. Around 1.4 is a desk day, from roughly 1.8 a properly active one. Independent of height and weight, so it compares well across days."
        case .burnPerWakingHour:
            return de ? "Dein durchschnittlicher Verbrauch pro Stunde, seit du wach bist."
                      : "Your average burn per hour since you woke."
        case .neatPerThousandSteps:
            return de ? "Was tausend Schritte bei dir tatsächlich bringen. Hängt an Gewicht und Schrittlänge, die reine Schrittzahl sagt das nicht."
                      : "What a thousand steps are actually worth for you. Depends on weight and stride, which a raw step count never shows."
        case .kcalPerKg:
            return de ? "Dein Tagesverbrauch je Kilo Körpergewicht. Diese Kennzahl macht Tage über Gewichtsänderungen hinweg vergleichbar."
                      : "Your daily intake per kilogram of body weight. This metric allows you to compare days across different weights."
        }
    }
}


// MARK: - Live-Quellen

/// The data sources behind each energy component, mirroring the cards under
/// "Live-Quellen" in Meine Daten.
///
/// The info sheet used to list hand-written "factors" — Körpermasse, Alter,
/// Stoffwechsel — which described the *model* rather than anything the app
/// actually reads. These are the real inputs, named the same way they are
/// named on the screen that shows them live.
struct LiveSource {
    let icon: String
    let de: String
    let en: String
    let segments: Set<EnergySegmentType>

    func label(language: String) -> String { language == "de" ? de : en }

    static let all: [LiveSource] = [
        LiveSource(icon: "figure.run",         de: "Workouts",         en: "Workouts",       segments: [.eat]),
        LiveSource(icon: "figure.walk",        de: "Schritte",         en: "Steps",          segments: [.neat]),
        LiveSource(icon: "map.fill",           de: "Gehstrecke",       en: "Distance",       segments: [.neat]),
        LiveSource(icon: "waveform.path.ecg",  de: "Herzfrequenz",     en: "Heart Rate",     segments: [.neat, .eat]),
        LiveSource(icon: "heart.fill",         de: "Ruhepuls",         en: "Resting HR",     segments: [.neat, .eat]),
        LiveSource(icon: "figure.stand",       de: "Stehzeit",         en: "Stand Time",     segments: [.neat]),
        LiveSource(icon: "moon.zzz.fill",      de: "Schlafanalyse",    en: "Sleep",          segments: [.bmr]),
        LiveSource(icon: "lungs.fill",         de: "VO₂max",           en: "VO₂max",         segments: [.eat]),
        LiveSource(icon: "fork.knife",         de: "Makros",           en: "Macros",         segments: [.tef]),
        LiveSource(icon: "cup.and.heat.waves.fill", de: "Koffein",     en: "Caffeine",       segments: [.caffeine])
    ]

    static func feeding(_ type: EnergySegmentType) -> [LiveSource] {
        all.filter { $0.segments.contains(type) }
    }
}

enum EnergySegmentType: Hashable {
    case bmr, neat, eat, tef, caffeine
}
