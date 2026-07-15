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

struct DashboardView: View {
    let accentBlue: Color
    let language: String
    let finalBMR: Double
    let sleepHoursValue: Double
    let leanBodyMass: Double
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

    @State private var editingField: String? = nil
        @State private var showProfileSidebar = false
    @State private var showActivityBreakdown = false
    @State private var ringProgress: Double = 0
    @State private var animatedBurn: Double = 0
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
    @State private var showCalorieDetail = false
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext
    @Environment(JournalStore.self)           private var store
    @Environment(HealthKitImportService.self) private var healthKit



    private var ringSize: CGFloat { LayoutMetrics.ringSize }

    private var topSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 50
    }
    @Environment(\.colorScheme) private var colorScheme
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
        let v = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return weightUnit == "kg" ? v : v * 0.453592
    }

    private var bodyFatPercent: Double {
        Double(bodyFatText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    // Reactive BMR — recomputes whenever the user edits weight, bodyFat, conditions, or sleep.
    private var activeFinalBMR: Double {
        let lbm    = weightInKg * (1.0 - bodyFatPercent / 100.0)
        let base   = 370 + 21.6 * lbm
        let age: Double = {
            if userAge <= 30 { return 1.0 }
            if userAge <= 60 { return 1.0 - Double(userAge - 30) * 0.001 }
            return 0.970 - Double(userAge - 60) * 0.005
        }()
        let adj    = base * age * metabolismFactor
        let hourly = adj / 24.0
        let wake   = 24.0 - sleepHours
        return (sleepHours * hourly * 0.9) + (wake * hourly)
    }

    private var hourlyBMR: Double {
        activeFinalBMR / (24 - sleepHoursValue * 0.1)
    }

    private var calorieSlots: [CalorieSlot] {
        let now = nowFraction
        let workoutList = healthKit.isAuthorized && !isSelectedFuture ? selectedWorkouts : []
        let totalWorkoutMinutes = workoutList.reduce(0.0) { $0 + $1.duration / 60.0 }
        let totalEatKcal = healthKit.isAuthorized && !isSelectedFuture ? activityResult.eatKcal : 0.0
        let dayStart = Calendar.current.startOfDay(for: selectedDate)

        return stride(from: 0.0, to: 24.0, by: 0.5).map { hour in
            let slotEnd = hour + 0.5
            let sleeping = hour < sleepHoursValue
            let isFuture = isSelectedFuture || (isSelectedToday && hour >= now)

            var workoutKcal = 0.0
            var isWorkout = false
            if !sleeping && !isFuture && totalWorkoutMinutes > 0 {
                for w in workoutList {
                    let wStart = w.startDate.timeIntervalSince(dayStart) / 3600.0
                    let wEnd   = w.endDate.timeIntervalSince(dayStart)   / 3600.0
                    let overlap = max(0, min(slotEnd, wEnd) - max(hour, wStart))
                    if overlap > 0 {
                        isWorkout = true
                        workoutKcal += (totalEatKcal / totalWorkoutMinutes) * (overlap * 60.0)
                    }
                }
            }

            var mult: Double = sleeping ? 0.88 : 1.0
            if !sleeping {
                switch hour {
                case sleepHoursValue..<(sleepHoursValue + 1.5): mult = 0.94
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
                workoutKcal: workoutKcal,
                isSleep: sleeping,
                isWorkout: isWorkout,
                isFuture: isFuture
            )
        }
    }

    private var nowFraction: Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
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
        guard healthKit.isAuthorized else {
            return ActivityCalculationService.ActivityResult(neatKcal: 0, eatKcal: 0)
        }
        let act = selectedActivity
        return ActivityCalculationService.calculate(
            steps:            act.steps,
            standTimeMinutes: act.standTimeMinutes,
            restingHR:        act.restingHeartRate,
            hrSegments:       act.hrSegments,
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

    private func saveActivityRecord() {
        guard healthKit.isAuthorized else { return }
        let result = activityResult
        let breakdown = result.neatBreakdown
        let record = DailyActivityRecord(
            dateKey: ActivityRepository.dateKey(for: selectedDate),
            date: Calendar.current.startOfDay(for: selectedDate),
            steps: selectedActivity.steps,
            standTimeMinutes: selectedActivity.standTimeMinutes,
            restingHR: selectedActivity.restingHeartRate,
            vo2Max: healthKit.vo2Max,
            workoutSeconds: selectedWorkouts.reduce(0.0) { $0 + $1.duration },
            sleepHours: sleepHours,
            weightKg: weightInKg > 0 ? weightInKg : nil,
            bmrDynamisch: tdeeResult.bmrDynamisch,
            neatSteps: breakdown.neatSteps,
            neatStand: breakdown.neatStand,
            neatHR: breakdown.neatHR,
            neatTotal: result.neatKcal,
            eatCalories: result.eatKcal
        )
        ActivityRepository.save(record: record, context: modelContext)
        ActivityRepository.deleteOlderThan(days: 90, context: modelContext)
    }

    private func backfillActivityHistory() {
        guard healthKit.isAuthorized, !healthKit.history.isEmpty else { return }
        let calendar = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        for (key, snapshot) in healthKit.history {
            guard let date = fmt.date(from: key) else { continue }
            let dayTDEE = TDEECalculationService.calculate(
                bmrStandard: activeFinalBMR,
                inputs: store.journalInputs(for: date),
                isFemale: selectedGender == femaleText
            )
            let result = ActivityCalculationService.calculate(
                steps: snapshot.activity.steps,
                standTimeMinutes: snapshot.activity.standTimeMinutes,
                restingHR: snapshot.activity.restingHeartRate,
                hrSegments: snapshot.activity.hrSegments,
                vo2Max: healthKit.vo2Max,
                workouts: snapshot.workouts,
                weightKg: weightInKg,
                age: userAge,
                isMale: selectedGender != femaleText,
                sleepHours: sleepHours,
                bmrDynamisch: dayTDEE.bmrDynamisch,
                referenceDate: date
            )
            let breakdown = result.neatBreakdown
            let record = DailyActivityRecord(
                dateKey: key,
                date: calendar.startOfDay(for: date),
                steps: snapshot.activity.steps,
                standTimeMinutes: snapshot.activity.standTimeMinutes,
                restingHR: snapshot.activity.restingHeartRate,
                vo2Max: healthKit.vo2Max,
                workoutSeconds: snapshot.workouts.reduce(0.0) { $0 + $1.duration },
                sleepHours: sleepHours,
                weightKg: weightInKg > 0 ? weightInKg : nil,
                bmrDynamisch: dayTDEE.bmrDynamisch,
                neatSteps: breakdown.neatSteps,
                neatStand: breakdown.neatStand,
                neatHR: breakdown.neatHR,
                neatTotal: result.neatKcal,
                eatCalories: result.eatKcal
            )
            ActivityRepository.save(record: record, context: modelContext)
        }
    }

    private var burnProgress: Double {
        let target = todayProjected
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
            return tdeeResult.bmrDynamisch + tdeeResult.koffeinBonus + tdeeResult.tefKcal +
                   (healthKit.isAuthorized ? activityResult.totalActiveKcal : 0)
        }
    }
    
    private var displayBurnProgress: Double {
        if isSelectedToday {
            return burnProgress
        } else if isSelectedFuture {
            return 0
        } else {
            return 1.0
        }
    }

    private var todayProjected: Double {
        tdeeResult.bmrDynamisch + tdeeResult.koffeinBonus + tdeeResult.tefKcal + (healthKit.isAuthorized ? activityResult.totalActiveKcal : 0)
    }

    private var yesterdayProjected: Double {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        let inputs = store.journalInputs(for: yesterday)
        let result = TDEECalculationService.calculate(
            bmrStandard: activeFinalBMR,
            inputs: inputs,
            isFemale: selectedGender == femaleText
        )
        let activeKcal: Double
        if let snap = healthKit.daySnapshot(for: yesterday) {
            activeKcal = ActivityCalculationService.calculate(
                steps:            snap.activity.steps,
                standTimeMinutes: snap.activity.standTimeMinutes,
                restingHR:        snap.activity.restingHeartRate,
                hrSegments:       snap.activity.hrSegments,
                vo2Max:           healthKit.vo2Max,
                workouts:         snap.workouts,
                weightKg:         weightInKg,
                age:              userAge,
                isMale:           selectedGender != femaleText,
                sleepHours:       sleepHours,
                bmrDynamisch:     result.bmrDynamisch
            ).totalActiveKcal
        } else {
            activeKcal = 0
        }
        return result.bmrDynamisch + result.koffeinBonus + result.tefKcal + activeKcal
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
        let key = HealthKitImportService.dateKey(prevDate)
        guard let snap = healthKit.history[key] else { return 0 }
        let prevTDEE = TDEECalculationService.calculate(
            bmrStandard: activeFinalBMR,
            inputs: store.journalInputs(for: prevDate),
            isFemale: selectedGender == femaleText
        )
        let prevActive = ActivityCalculationService.calculate(
            steps: snap.activity.steps,
            standTimeMinutes: snap.activity.standTimeMinutes,
            restingHR: snap.activity.restingHeartRate,
            hrSegments: snap.activity.hrSegments,
            vo2Max: healthKit.vo2Max,
            workouts: snap.workouts,
            weightKg: weightInKg,
            age: userAge,
            isMale: selectedGender != femaleText,
            sleepHours: sleepHours,
            bmrDynamisch: prevTDEE.bmrDynamisch,
            referenceDate: prevDate
        )
        return prevTDEE.bmrDynamisch + prevTDEE.koffeinBonus + prevTDEE.tefKcal + prevActive.totalActiveKcal
    }

    private var vsSelectedDayPercent: Double {
        if isSelectedToday { return vsYesterdayPercent }
        let prev = previousDayTotal
        guard prev > 0 else { return 0 }
        return (displayBurnedSoFar - prev) / prev * 100
    }

    private var vsSelectedDayColor: Color { vsSelectedDayPercent >= 0 ? .green : .red }

    private var calendarDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (-90...7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

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
        finalBMR: Double,
        sleepHoursValue: Double,
        leanBodyMass: Double,
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
        selectedDate: Binding<Date>
    ) {
        self.accentBlue = accentBlue
        self.language = language
        self.finalBMR = finalBMR
        self.sleepHoursValue = sleepHoursValue
        self.leanBodyMass = leanBodyMass
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
    }

        private var fullDateButton: some View {
        Button {
            showCalendarPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentBlue)
                Text(selectedDateString)
                    .font(.poppins(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Theme.card)
                    .overlay(Capsule().strokeBorder(Theme.cardStroke, lineWidth: 1))
                    .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 4)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(SpringyButtonStyle())
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

            VStack(spacing: 0) {
                // STATIC HEADER
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language == "de" ? "Dein Überblick" : "Your Overview")
                            .font(.poppins(size: LayoutMetrics.titleFontSize, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        
                        fullDateButton
                    }
                    Spacer()
                    profileIconButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 4)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: LayoutMetrics.cardSpacing) {
                        datePicker

                        calorieRingWidget
                            .padding(.horizontal, 20)

                        kpiRow
                            .padding(.horizontal, 20)

                        caloriesChartSection
                        
                        Spacer().frame(height: 100)
                    }
                }
                .refreshable {
                    await healthKit.fetchAll()
                    saveActivityRecord()
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
            }

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
            runBurnAnimation()
            saveActivityRecord()
            backfillActivityHistory()
        }
        .onChange(of: selectedDate) { _, _ in runBurnAnimation() }
        .onChange(of: tdeeResult.tdeeTotal) { _, _ in runBurnAnimation() }
        .onChange(of: healthKit.activity.fetchedAt) { _, _ in
            runBurnAnimation()
            saveActivityRecord()
            backfillActivityHistory()
        }
        .onChange(of: healthKit.workouts) { _, _ in runBurnAnimation() }
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

    // MARK: - Datumsleiste

    private var datePicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(calendarDays, id: \.self) { date in
                        dayChip(date: date)
                            .id(date)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            .onAppear {
                proxy.scrollTo(Calendar.current.startOfDay(for: Date()), anchor: .center)
            }
            .onChange(of: selectedDate) { _, date in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    proxy.scrollTo(date, anchor: .center)
                }
            }
        }
    }

    private func dayChip(date: Date) -> some View {
        let cal = Calendar.current
        let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
        let isToday = cal.isDateInToday(date)
        _ = dayDistanceFromToday(date)
        let day = cal.component(.day, from: date)

        let chipW: CGFloat  = isToday ? 38 : isSelected ? 34 : 30
        let chipH: CGFloat  = isToday ? 46 : isSelected ? 42 : 36
        let dayFS: CGFloat  = isToday ? 15 : isSelected ? 13 : 11
        let weekFS: CGFloat = isToday ? 9 : 8
        let chipOpacity: Double = (isToday || isSelected) ? 1.0 : 0.65

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                selectedDate = date
            }
        } label: {
            VStack(spacing: 2) {
                Text(weekdayAbbrev(for: date))
                    .font(.poppins(size: weekFS, weight: .regular))
                Text("\(day)")
                    .font(.poppins(size: dayFS, weight: .semibold))
                Circle()
                    .fill(isToday && !isSelected ? accentBlue : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: chipW, height: chipH)
            .foregroundStyle(
                isSelected ? Color.white :
                isToday    ? accentBlue :
                             Color.primary
            )
            .opacity(chipOpacity)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? accentBlue : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isSelected)
    }

    private func dayDistanceFromToday(_ date: Date) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return abs(cal.dateComponents([.day], from: today, to: date).day ?? 0)
    }

    private func weekdayAbbrev(for date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        if language == "de" {
            return ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"][weekday - 1]
        } else {
            return ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"][weekday - 1]
        }
    }

    private func runBurnAnimation() {
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

    private enum EnergySegmentType: Hashable {
        case bmr, neat, eat, tef, caffeine
    }

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
            let diff = currentKcal - prev

            HStack {
                HStack(spacing: 4) {
                    Image(systemName: diff >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(String(format: "%+.0f kcal %@", diff, language == "de" ? "vs. gestern" : "vs. yesterday"))
                }
                .font(.poppins(size: 12, weight: .medium))
                .foregroundStyle(diff >= 0 ? .green : .red)

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
                    breakdownItem(label: language == "de" ? "Schritte" : "Steps", value: activityResult.neatBreakdown.neatSteps)
                    breakdownItem(label: language == "de" ? "Stehen" : "Standing", value: activityResult.neatBreakdown.neatStand)
                    breakdownItem(label: language == "de" ? "Herzfrequenz" : "Heart Rate", value: activityResult.neatBreakdown.neatHR)
                case .eat:
                    breakdownItem(label: language == "de" ? "Workouts" : "Workouts", value: activityResult.eatKcal)
                case .tef:
                    let inputs = store.journalInputs(for: selectedDate)
                    let p = inputs.proteinGramsByMeal.values.reduce(0, +) * 1.0
                    let c = inputs.carbsGramsByMeal.values.reduce(0, +) * 0.3
                    let f = inputs.fatGramsByMeal.values.reduce(0, +) * 0.135
                    breakdownItem(label: language == "de" ? "Protein" : "Protein", value: p)
                    breakdownItem(label: language == "de" ? "Kohlenhydrate" : "Carbs", value: c)
                    breakdownItem(label: language == "de" ? "Fett" : "Fat", value: f)
                case .caffeine:
                    let inputs = store.journalInputs(for: selectedDate)
                    breakdownItem(label: language == "de" ? "Koffein (\(Int(inputs.caffeineMg)) mg)" : "Caffeine (\(Int(inputs.caffeineMg)) mg)", value: tdeeResult.koffeinBonus)
                case .bmr:
                    breakdownItem(label: language == "de" ? "Basis-Grundumsatz" : "Base BMR", value: currentKcal)
                }
            }
            .padding(10)
            .background(Theme.ink.opacity(0.04))
            .cornerRadius(10)
        }
    }

    private func breakdownItem(label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .font(.poppins(size: 13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(String(format: "%.0f kcal", value))
                .font(.poppins(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func previousValue(for type: EnergySegmentType) -> Double {
        let prevDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
        let key = HealthKitImportService.dateKey(prevDate)

        let inputs = store.journalInputs(for: prevDate)
        let tdee = TDEECalculationService.calculate(
            bmrStandard: activeFinalBMR,
            inputs: inputs,
            isFemale: selectedGender == femaleText
        )

        let fraction = isSelectedToday ? nowFraction / 24.0 : 1.0

        if let snap = healthKit.history[key] {
            let res = ActivityCalculationService.calculate(
                steps: snap.activity.steps,
                standTimeMinutes: snap.activity.standTimeMinutes,
                restingHR: snap.activity.restingHeartRate,
                hrSegments: snap.activity.hrSegments,
                vo2Max: healthKit.vo2Max,
                workouts: snap.workouts,
                weightKg: weightInKg,
                age: userAge,
                isMale: selectedGender != femaleText,
                sleepHours: sleepHours,
                bmrDynamisch: tdee.bmrDynamisch,
                referenceDate: prevDate
            )
            switch type {
            case .bmr:  return isSelectedToday ? bmrBurnedSoFar : tdee.bmrDynamisch
            case .neat: return res.neatKcal
            case .eat:  return res.eatKcal
            case .tef:  return tdee.tefKcal * fraction
            case .caffeine: return tdee.koffeinBonus * fraction
            }
        } else {
            switch type {
            case .bmr:  return isSelectedToday ? bmrBurnedSoFar : tdee.bmrDynamisch
            case .tef:  return tdee.tefKcal * fraction
            case .caffeine: return tdee.koffeinBonus * fraction
            default:    return 0
            }
        }
    }

    private func energyStackedBar(_ segs: [EnergySegment], total: Double) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                HStack(spacing: 1.5) {
                    ForEach(segs) { s in
                        let w = max(s.kcal > 0 ? 2 : 0, width * (s.kcal / total))
                        Rectangle()
                            .fill(
                                LinearGradient(colors: [s.color.opacity(0.8), s.color],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            .frame(width: w)
                            .shadow(color: s.color.opacity(0.3), radius: 2)
                    }
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
            .background(
                Capsule()
                    .fill(Theme.trackFill)
                    .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 0.5))
            )
            
            // Faint scale below
            HStack(spacing: 0) {
                ForEach(0...10, id: \.self) { i in
                    Rectangle()
                        .fill(Theme.ink.opacity(0.08))
                        .frame(width: 1, height: 3)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 2)
        }
    }

        private func energySegmentRow(_ s: EnergySegment, total: Double) -> some View {
        let pct = total > 0 ? s.kcal / total : 0
        let isExpanded = expandedSegmentType == s.type

        return VStack(spacing: 11) {
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
                .frame(height: 12)

            if isExpanded {
                expandedContent(for: s.type, currentKcal: s.kcal)
                    .transition(.opacity)
            }
        }
        .padding(14)
        .glassCard(16)
    }


    private func infoSheet(for type: EnergySegmentType) -> some View {
        let seg = energySegments.first(where: { $0.type == type })
        return VStack(spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: seg?.icon ?? "info.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(seg?.color ?? accentBlue)
                    .frame(width: 44, height: 44)
                    .background((seg?.color ?? accentBlue).opacity(0.14))
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
            
            Spacer()
        }
        .presentationDetents([.height(240)])
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
            ZStack {
                CaloricBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        Spacer().frame(height: 6)

                        // Hero — total + stacked micro-chart
                        VStack(spacing: 18) {
                            VStack(spacing: 3) {
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text("\(Int(displayBurnedSoFar))")
                                        .font(.poppins(size: 46, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("kcal")
                                        .font(.poppins(size: 16, weight: .regular))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            energyStackedBar(segs, total: total)
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(20)
                        .glassCard(22, tint: accentBlue, tintStrength: 0.04)
                        .padding(.horizontal, 18)

                        // Per-component rows with progress bars
                        VStack(spacing: 10) {
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

                        Spacer().frame(height: 24)
                    }
                }
            }
            .navigationTitle(language == "de" ? "Aufschlüsselung" : "Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: Binding(
                get: { infoSegmentType.map { InfoSegment(type: $0) } },
                set: { infoSegmentType = $0?.type }
            )) { info in
                infoSheet(for: info.type)
                    .presentationBackground(Theme.canvas)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t.done) { showActivityBreakdown = false }
                        .foregroundStyle(accentBlue)
                        .fontWeight(.semibold)
                }
            }
        }
        .caloricAppearance()
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.canvas)
        .task { await healthKit.fetchAll() }
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
                    Text(language == "de" ? "Meine Daten" : "My Data")
                        .font(.poppins(size: 24, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(language == "de" ? "Verwalte dein Profil und Körperwerte" : "Manage your profile and body metrics")
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
                    // SECTION 1: PERSONAL
                    profileSection(title: language == "de" ? "Persönlich" : "Personal") {
                        VStack(spacing: 0) {
                            profileRow(icon: "person.fill", label: language == "de" ? "Vorname" : "First Name") {
                                TextField("", text: $accountUsername)
                                    .font(.poppins(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .multilineTextAlignment(.trailing)
                                    .submitLabel(.done)
                            }
                            Divider().padding(.leading, 52)
                            profileRow(icon: "calendar", label: language == "de" ? "Geburtsdatum" : "Birth Date") {
                                DatePicker("", selection: $birthDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .tint(accentBlue)
                            }
                            Divider().padding(.leading, 52)
                            profileRow(icon: "figure.arms.open", label: language == "de" ? "Geschlecht" : "Gender") {
                                Text(selectedGender ?? "—")
                                    .font(.poppins(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                    }

                    // SECTION 2: BODY METRICS
                    profileSection(title: language == "de" ? "Körperwerte" : "Body Metrics") {
                        VStack(spacing: 0) {
                            profileActionRow(icon: "scalemass.fill", label: language == "de" ? "Gewicht" : "Weight", value: weightText + " " + weightUnit) {
                                editingField = "weight"
                            }
                            Divider().padding(.leading, 52)
                            profileActionRow(icon: "ruler.fill", label: language == "de" ? "Größe" : "Height", value: heightText + " " + heightUnit) {
                                editingField = "height"
                            }
                            Divider().padding(.leading, 52)
                            profileActionRow(icon: "percent", label: language == "de" ? "Körperfettanteil" : "Body Fat %", value: (knowsBodyFat == true) ? bodyFatText + "%" : (language == "de" ? "Unbekannt" : "Unknown")) {
                                editingField = "bodyFat"
                            }
                        }
                    }

                    // SECTION 3: METABOLISM
                    profileSection(title: language == "de" ? "Stoffwechsel & Gesundheit" : "Metabolism & Health") {
                        profileActionRow(icon: "bolt.heart.fill", label: language == "de" ? "Besonderheiten" : "Conditions", value: selectedConditions.contains(noConditionText) ? (language == "de" ? "Keine" : "None") : "\(selectedConditions.count) Aktiv") {
                            editingField = "conditions"
                        }
                    }

                    // SECTION 4: APPEARANCE
                    profileSection(title: language == "de" ? "Einstellungen" : "Settings") {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "circle.lefthalf.filled")
                                    .font(.system(size: 16))
                                    .foregroundStyle(accentBlue)
                                    .frame(width: 28)
                                Text(language == "de" ? "Erscheinungsbild" : "Appearance")
                                    .font(.poppins(size: 15, weight: .regular))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                            }
                            AppearancePicker(language: language, accent: accentBlue)
                        }
                        .padding(.vertical, 14)
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

    private func profileRow<Content: View>(icon: String, label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(accentBlue)
                .frame(width: 28, height: 28)
                .background(accentBlue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Text(label)
                .font(.poppins(size: 15, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
            
            Spacer()
            
            content()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }

    private func profileActionRow(icon: String, label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(accentBlue)
                    .frame(width: 28, height: 28)
                    .background(accentBlue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text(label)
                    .font(.poppins(size: 15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                
                Spacer()
                
                Text(value)
                    .font(.poppins(size: 15, weight: .semibold))
                    .foregroundStyle(accentBlue)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    if !isSelectedFuture {
                        Circle()
                            .trim(from: 0, to: ringProgress * 0.75)
                            .stroke(
                                LinearGradient(
                                    colors: [Theme.accentSky, accentBlue],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )
                            .rotationEffect(.degrees(135))
                            .shadow(color: accentBlue.opacity(0.4), radius: 8, x: 0, y: 0)
                        
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
                                    .overlay(Circle().strokeBorder(accentBlue, lineWidth: 1.5))
                                    .frame(width: 8, height: 8)
                                    .shadow(color: accentBlue.opacity(0.5), radius: 3)
                                    .position(x: x, y: y)
                            }
                        }
                    }

                    // 3. Center Instrument Data
                    VStack(spacing: 2) {
                        Text(!isSelectedFuture ? "\(Int(animatedBurn))" : "–")
                            .font(.poppins(size: 38, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                        
                        HStack(spacing: 3) {
                            Text("kcal")
                                .font(.poppins(size: 12, weight: .regular))
                                .foregroundStyle(Theme.textSecondary)
                            
                            if isSelectedToday {
                                Text("•")
                                    .font(.system(size: 8))
                                    .foregroundStyle(accentBlue.opacity(0.5))
                                
                                Text(currentTimeString)
                                    .font(.poppins(size: 11, weight: .regular))
                                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                            }
                        }
                    }
                    .offset(y: -4) // Slight upward shift to center visually in the open arc
                }
                .frame(width: ringSize, height: ringSize)
                .padding(.top, 28)

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
                    .padding(.bottom, 22)
                } else {
                    Spacer().frame(height: 22)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
            .glassCard(Theme.Radius.hero, tint: accentBlue, tintStrength: 0.05)
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
                Button {
                    showCalorieDetail = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accentBlue)
                        .frame(width: 28, height: 28)
                        .background(accentBlue.opacity(0.12))
                        .clipShape(Circle())
                }
            }

            Chart {
                ForEach(calorieSlots) { slot in
                    BarMark(
                        x: .value("Zeit", slot.hour),
                        y: .value("kcal", slot.isFuture ? slot.calories : slot.total)
                    )
                    .foregroundStyle(slotBarColor(slot))
                    .cornerRadius(2)
                }
                if isSelectedToday {
                    RuleMark(x: .value("Jetzt", nowFraction))
                        .foregroundStyle(accentBlue)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .annotation(position: .top, spacing: 2) {
                            Text(language == "de" ? "Jetzt" : "Now")
                                .font(.poppins(size: 7, weight: .semibold))
                                .foregroundStyle(accentBlue)
                        }
                }
            }
            .frame(height: LayoutMetrics.chartHeight)
            .chartXScale(domain: 0...24)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(String(format: "%02d:00", Int(d)))
                                .font(.poppins(size: 8, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisValueLabel()
                        .font(.poppins(size: 8, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 14) {
                legendItem(color: accentBlue.opacity(isDark ? 0.40 : 0.25),
                           label: language == "de" ? "Schlaf" : "Sleep")
                legendItem(color: accentBlue,
                           label: language == "de" ? "Wachphase" : "Awake")
                if healthKit.isAuthorized && !isSelectedFuture && !selectedWorkouts.isEmpty {
                    legendItem(color: Theme.segEAT,
                               label: language == "de" ? "Sport" : "Workout")
                }
                legendItem(color: Theme.ink.opacity(isDark ? 0.15 : 0.10),
                           label: language == "de" ? "Zukunft" : "Future")
            }
        }
        .padding(14)
        .background(GlassCardBackground(cornerRadius: 18))
        .onTapGesture {
            showCalorieDetail = true
        }
        .padding(.horizontal, 20)
    }

    private func slotBarColor(_ slot: CalorieSlot) -> Color {
        if slot.isFuture  { return Theme.ink.opacity(isDark ? 0.13 : 0.09) }
        if slot.isWorkout { return Theme.segEAT }
        if slot.isSleep   { return accentBlue.opacity(isDark ? 0.40 : 0.25) }
        return accentBlue.opacity(0.85)
    }

    private var kpiRow: some View {
        HStack(spacing: 10) {
            kpiBox(
                icon: "target",
                value: isSelectedToday
                    ? "\(Int(todayProjected))"
                    : isSelectedFuture
                        ? "\(Int(tdeeResult.tdeeTotal))"
                        : "\(Int(displayBurnedSoFar))",
                unit: "kcal",
                accent: false
            )
            kpiBox(
                icon: "arrow.up.arrow.down",
                value: isSelectedFuture ? "–" : String(format: "%+.0f", vsSelectedDayPercent),
                unit: language == "de" ? "% vs. Gestern" : "% vs. Yesterday",
                accent: false,
                tint: isSelectedFuture ? nil : vsSelectedDayColor
            )
            kpiBox(
                icon: "bolt.fill",
                value: healthKit.isAuthorized && !isSelectedFuture
                    ? "\(Int(activityResult.totalActiveKcal))"
                    : "–",
                unit: language == "de" ? "Aktiv kcal" : "Active kcal",
                accent: false
            )
        }
    }

    private func kpiBox(icon: String, value: String, unit: String, accent: Bool, tint: Color? = nil) -> some View {
        let fg: Color = tint ?? (accent ? .white : accentBlue)
        let valueFg: Color = tint ?? (accent ? .white : Color.primary)
        let unitFg: Color = tint.map { $0.opacity(0.7) } ?? (accent ? .white.opacity(0.75) : accentBlue.opacity(0.7))
        return VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(fg)
            Text(value)
                .font(.poppins(size: 20, weight: .semibold))
                .foregroundStyle(valueFg)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(unit)
                .font(.poppins(size: 9, weight: .regular))
                .foregroundStyle(unitFg)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            Group {
                if accent {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(accentBlue)
                } else {
                    GlassCardBackground(cornerRadius: 16)
                }
            }
        )
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
