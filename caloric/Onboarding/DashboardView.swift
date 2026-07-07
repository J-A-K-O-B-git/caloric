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

struct CalorieSlot: Identifiable {
    let id = UUID()
    let hour: Double
    let calories: Double
    let workoutKcal: Double
    let isSleep: Bool
    var total: Double { calories + workoutKcal }
}

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
        stride(from: 0.0, to: 24.0, by: 0.5).map { hour in
            let sleeping = hour < sleepHoursValue
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
            return CalorieSlot(hour: hour, calories: hourlyBMR * 0.5 * mult, workoutKcal: 0, isSleep: sleeping)
        }
    }

    private var nowFraction: Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0
    }

    private var burnedSoFar: Double {
        let bmrSoFar = calorieSlots.filter { $0.hour < nowFraction }.reduce(0) { $0 + $1.calories }
        let activeKcal = healthKit.isAuthorized ? activityResult.totalActiveKcal : 0
        let fractionalBonuses = (tdeeResult.tefKcal + tdeeResult.koffeinBonus) * (nowFraction / 24.0)
        return bmrSoFar + activeKcal + fractionalBonuses
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
        return ActivityCalculationService.calculate(
            steps:            healthKit.activity.steps,
            standTimeMinutes: healthKit.activity.standTimeMinutes,
            restingHR:        healthKit.activity.restingHeartRate,
            sedentaryAvgHR:   healthKit.activity.sedentaryAvgHR,
            unrecordedCardioAvgHR: healthKit.activity.unrecordedCardioAvgHR,
            cardioRatio:      healthKit.activity.cardioRatio,
            vo2Max:           healthKit.vo2Max,
            workouts:         healthKit.workouts,
            weightKg:         weightInKg,
            age:              userAge,
            isMale:           selectedGender != femaleText,
            sleepHours:       sleepHours,
            bmrDynamisch:     tdeeResult.bmrDynamisch
        )
    }

    private var burnProgress: Double {
        let target = todayProjected
        guard target > 0 else { return 0 }
        return min(1.0, burnedSoFar / target)
    }

    private var isSelectedToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    private var isSelectedFuture: Bool { selectedDate > Calendar.current.startOfDay(for: Date()) }
    
    private var displayBurnedSoFar: Double {
        if isSelectedToday {
            return burnedSoFar
        } else if isSelectedFuture {
            return 0
        } else {
            return todayProjected
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
                sedentaryAvgHR:   snap.activity.sedentaryAvgHR,
                unrecordedCardioAvgHR: snap.activity.unrecordedCardioAvgHR,
                cardioRatio:      snap.activity.cardioRatio,
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
                ObsidianBackground()
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
                        .font(.custom("PingFangSC-Semibold", size: 16))
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

    // MARK: - Body

    var body: some View {
        ZStack {
            ObsidianBackground()

            // Hauptinhalt
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language == "de" ? "Dein Überblick" : "Your Overview")
                            .font(.custom("PingFangSC-Semibold", size: LayoutMetrics.titleFontSize, relativeTo: .largeTitle))
                            .foregroundStyle(.white)
                        
                        Button {
                            showCalendarPicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedDateString)
                                    .font(.custom("PingFangSC-Regular", size: 14, relativeTo: .subheadline))
                                    .foregroundStyle(Theme.textSecondary)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SpringyButtonStyle())
                    }
                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                            showProfileSidebar = true
                        }
                    } label: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(accentBlue)
                    }
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

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language == "de" ? "Kalorien im Tagesverlauf" : "Calories Throughout the Day")
                            .font(.custom("PingFangSC-Semibold", size: 15, relativeTo: .subheadline))
                            .foregroundStyle(accentBlue)
                        Text(language == "de" ? "kcal pro 30 Minuten" : "kcal per 30 minutes")
                            .font(.custom("PingFangSC-Regular", size: 12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }

                    Chart {
                        ForEach(calorieSlots) { slot in
                            BarMark(
                                x: .value("Zeit", slot.hour),
                                y: .value("kcal", slot.calories)
                            )
                            .foregroundStyle(accentBlue.opacity(slot.isSleep ? (isDark ? 0.45 : 0.28) : 0.9))
                            .cornerRadius(3)
                        }
                    }
                    .frame(height: LayoutMetrics.chartHeight)
                    .chartXScale(domain: 0...24)
                    .chartXAxis {
                        AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                            AxisValueLabel {
                                if let d = value.as(Double.self) {
                                    Text("\(Int(d))h")
                                        .font(.custom("PingFangSC-Regular", size: 8, relativeTo: .caption2))
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
                                .font(.custom("PingFangSC-Regular", size: 8, relativeTo: .caption2))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 16) {
                        legendItem(color: accentBlue.opacity(isDark ? 0.45 : 0.28),
                                   label: language == "de" ? "Schlaf" : "Sleep")
                        legendItem(color: accentBlue,
                                   label: language == "de" ? "Wachphase" : "Awake")
                    }
                }
                .padding(14)
                .background(GlassCardBackground(cornerRadius: 18))
                .padding(.horizontal, 20)

            }
            .frame(maxWidth: .infinity)
            }
            .refreshable {
                await healthKit.fetchAll()
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
                                .font(.custom("PingFangSC-Semibold", size: 13, relativeTo: .callout))
                                .foregroundStyle(.primary)
                            Text(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))
                                .font(.custom("PingFangSC-Regular", size: 11, relativeTo: .caption2))
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
        .onAppear { runBurnAnimation() }
        .onChange(of: selectedDate) { _, _ in runBurnAnimation() }
        .onChange(of: tdeeResult.tdeeTotal) { _, _ in runBurnAnimation() }
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
                    .font(.custom("PingFangSC-Regular", size: weekFS, relativeTo: .caption2))
                Text("\(day)")
                    .font(.custom("PingFangSC-Semibold", size: dayFS, relativeTo: .caption))
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

    private enum EnergySegmentType {
        case bmr, neat, eat, tef, caffeine
    }

    private struct EnergySegment: Identifiable {
        let id = UUID()
        let type: EnergySegmentType
        let title: String
        let short: String
        let subtitle: String?
        let icon: String
        let color: Color
        let kcal: Double
    }

    /// Ordered energy-expenditure components that sum to the daily total.
    private var energySegments: [EnergySegment] {
        let neat = healthKit.isAuthorized ? activityResult.neatKcal : 0
        let eat  = healthKit.isAuthorized ? activityResult.eatKcal  : 0
        var segs: [EnergySegment] = [
            EnergySegment(
                type: .bmr,
                title: language == "de" ? "BMR" : "Resting Metabolic Rate",
                short: "BMR",
                subtitle: language == "de" ? "Grundumsatz" : "Basal Metabolic Rate",
                icon: "moon.zzz.fill", color: Theme.segBMR, kcal: tdeeResult.bmrDynamisch
            ),
            EnergySegment(
                type: .neat,
                title: "NEAT",
                short: "NEAT",
                subtitle: language == "de" ? "Non-Exercise Activity Thermogenesis" : "Non-Exercise Activity Thermogenesis",
                icon: "figure.walk", color: Theme.segNEAT, kcal: neat
            ),
            EnergySegment(
                type: .eat,
                title: "EAT",
                short: "EAT",
                subtitle: language == "de" ? "Exercise Activity Thermogenesis"
                                           : "Exercise Activity Thermogenesis",
                icon: "dumbbell.fill", color: Theme.segEAT, kcal: eat
            ),
            EnergySegment(
                type: .tef,
                title: language == "de" ? "TEF" : "TEF",
                short: "TEF",
                subtitle: language == "de" ? "Thermische Wirkung der Ernährung"
                                           : "Thermic Effect of Food",
                icon: "fork.knife.circle.fill", color: Theme.segTEF, kcal: tdeeResult.tefKcal
            ),
        ]
        if tdeeResult.koffeinBonus > 0 {
            segs.append(EnergySegment(
                type: .caffeine,
                title: language == "de" ? "Koffein-Thermogenese" : "Caffeine Thermogenesis",
                short: language == "de" ? "Koffein" : "Caffeine",
                subtitle: nil,
                icon: "cup.and.heat.waves.fill", color: Theme.segCaf, kcal: tdeeResult.koffeinBonus
            ))
        }
        return segs
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
                    .fill(Color.black.opacity(0.2))
                    .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            )
            
            // Faint scale below
            HStack(spacing: 0) {
                ForEach(0...10, id: \.self) { i in
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1, height: 3)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func energySegmentRow(_ s: EnergySegment, total: Double) -> some View {
        let pct = total > 0 ? s.kcal / total : 0
        return Button {
            selectedEnergySegment = s
        } label: {
            VStack(spacing: 11) {
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
                            .font(.custom("PingFangSC-Semibold", size: 15, relativeTo: .callout))
                            .foregroundStyle(Theme.textPrimary)
                        if let subtitle = s.subtitle {
                            Text(subtitle)
                                .font(.custom("PingFangSC-Regular", size: 11, relativeTo: .caption))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(Int(s.kcal))")
                                .font(.custom("PingFangSC-Semibold", size: 17, relativeTo: .headline))
                                .foregroundStyle(Theme.textPrimary)
                            Text("kcal")
                                .font(.custom("PingFangSC-Regular", size: 11, relativeTo: .caption2))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(String(format: "%.0f%%", pct * 100))
                            .font(.custom("PingFangSC-Medium", size: 11, relativeTo: .caption2))
                            .foregroundStyle(s.color)
                    }
                }
                InstrumentProgressBar(progress: pct, color: s.color, height: 4, showScale: true)
                    .frame(height: 12)
            }
            .padding(14)
            .glassCard(16)
        }
        .buttonStyle(.plain)
    }

    private var activityBreakdownSheet: some View {
        let segs = energySegments
        let total = max(segs.reduce(0) { $0 + $1.kcal }, 1)
        return NavigationStack {
            ZStack {
                ObsidianBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        Spacer().frame(height: 6)

                        // Hero — total + stacked micro-chart
                        VStack(spacing: 18) {
                            VStack(spacing: 3) {
                                Text(language == "de" ? "Dein hochgerechneter täglicher Gesamtumsatz" : "Your estimated total daily calorie expenditure")
                                    .font(.custom("PingFangSC-Medium", size: 9, relativeTo: .caption2))
                                    .foregroundStyle(Theme.textSecondary)
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text("\(Int(todayProjected))")
                                        .font(.custom("PingFangSC-Semibold", size: 46, relativeTo: .largeTitle))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("kcal")
                                        .font(.custom("PingFangSC-Regular", size: 16, relativeTo: .title3))
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
                                            .font(.custom("PingFangSC-Regular", size: 10, relativeTo: .caption2))
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
                                    .font(.custom("PingFangSC-Regular", size: 12, relativeTo: .caption))
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t.done) { showActivityBreakdown = false }
                        .foregroundStyle(accentBlue)
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.obsidian)
        .task { await healthKit.fetchAll() }
    }

    // MARK: - Berechnungsmethoden View

    private var calcExplanationView: some View {
        let lbm = weightInKg * (1.0 - bodyFatPercent / 100.0)
        let baseBMR = 370 + 21.6 * lbm
        let isMale = selectedGender != femaleText

        // ── NEAT intermediate values (mirror ActivityCalculationService.neat) ──
        let nWalkMin      = Double(healthKit.activity.steps) / 100.0
        let nWalkH        = nWalkMin / 60.0
        let nBmrH         = activeFinalBMR / 24.0
        let nStepsKcal    = nWalkH * 2.0 * nBmrH

        let nStandMin     = healthKit.activity.standTimeMinutes
        let nPureStandMin = max(0, nStandMin - nWalkMin)
        let nPureStandH   = nPureStandMin / 60.0
        let nStandKcal    = nPureStandH * 0.18 * nBmrH

        let nHrMax        = 220.0 - Double(userAge)
        let nWorkoutMin   = healthKit.workouts.reduce(0.0) { $0 + $1.duration } / 60.0
        let nEffSleepH    = sleepHours > 0 ? sleepHours : 8.0
        let nWakeMin      = (24.0 - nEffSleepH) * 60.0
        let nGapMin       = max(0, nWakeMin - nWalkMin - nStandMin - nWorkoutMin)
        let nHrAvg        = healthKit.activity.avgHeartRateWaking
        let nHrRest       = healthKit.activity.restingHeartRate
        // Mirror ActivityCalculationService.neat() exactly (saubererPuls, Effizienzfaktor, Cap)
        let nMicroKcal: Double = {
            guard let avg = nHrAvg, let rest = nHrRest, avg > rest, nHrMax > rest else { return 0 }
            let divisor = nHrMax - rest
            guard divisor > 0 else { return 0 }
            let geschaetzterLückenPuls = min(avg - (nWorkoutMin > 0 ? 15.0 : 0.0), rest + 25.0)
            let saubererPuls = max(rest + 2.0, geschaetzterLückenPuls)
            let kJ: Double = isMale
                ? -55.0969 + 0.6309 * nHrMax + 0.1988 * weightInKg + 0.2017 * Double(userAge)
                : -20.4022 + 0.4472 * nHrMax - 0.1263 * weightInKg + 0.0740 * Double(userAge)
            let kNetto = max(0, kJ / 4.184 - activeFinalBMR / (24.0 * 60.0))
            let micro = ((saubererPuls - rest) / divisor) * nGapMin * kNetto * 0.10
            return min(max(0, micro), 500.0)
        }()
        let nMicroRow: AnyView = { () -> AnyView in
            if let avg = nHrAvg, let rest = nHrRest, avg > rest {
                let geschaetzterLückenPuls = min(avg - (nWorkoutMin > 0 ? 15.0 : 0.0), rest + 25.0)
                let saubererPuls = max(rest + 2.0, geschaetzterLückenPuls)
                let hrrNetto = (saubererPuls - rest) / max(1, nHrMax - rest)
                return calcRow(
                    label: language == "de" ? "③ Mikro-NEAT (HR-Lücke)" : "③ Micro-NEAT (HR Gap)",
                    formula: String(format: language == "de"
                        ? "HR_avg %.0f → bereinigt %.0f · HR_rest %.0f · HR_max %.0f\nHRR %.2f · %.0f min · ×0.10"
                        : "HR_avg %.0f → adjusted %.0f · HR_rest %.0f · HR_max %.0f\nHRR %.2f · %.0f min · ×0.10",
                        avg, saubererPuls, rest, nHrMax, hrrNetto, nGapMin),
                    value: String(format: "%.0f kcal", nMicroKcal)
                )
            } else {
                return calcRow(
                    label: language == "de" ? "③ Mikro-NEAT (HR-Lücke)" : "③ Micro-NEAT (HR Gap)",
                    formula: language == "de" ? "Keine Herzfrequenz-Daten" : "No heart rate data",
                    value: "0 kcal"
                )
            }
        }()

        return ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Spacer().frame(height: 4)

                // ── BMR ──────────────────────────────────────────────────
                calcSection(
                    icon: "moon.zzz.fill",
                    iconColor: accentBlue,
                    title: "BMR — Katch-McArdle",
                    rows: [
                        calcRow(
                            label: language == "de" ? "Magermasse (LBM)" : "Lean Body Mass",
                            formula: language == "de"
                                ? "Gewicht × (1 − Körperfett%)"
                                : "Weight × (1 − Body fat%)",
                            value: String(format: "%.1f kg", lbm)
                        ),
                        calcRow(
                            label: "BMR Basis",
                            formula: "370 + 21.6 × LBM",
                            value: String(format: "%.0f kcal", baseBMR)
                        ),
                        calcRow(
                            label: language == "de" ? "Altersfaktor" : "Age factor",
                            formula: language == "de"
                                ? "≤30: ×1.0 · 31–60: −0.1%/J · >60: −0.5%/J"
                                : "≤30: ×1.0 · 31–60: −0.1%/yr · >60: −0.5%/yr",
                            value: {
                                let f: Double
                                if userAge <= 30 { f = 1.0 }
                                else if userAge <= 60 { f = 1.0 - Double(userAge - 30) * 0.001 }
                                else { f = 0.970 - Double(userAge - 60) * 0.005 }
                                return String(format: "×%.3f", f)
                            }()
                        ),
                        calcRow(
                            label: language == "de" ? "Stoffwechselfaktor" : "Metabolism factor",
                            formula: language == "de" ? "Benutzerdefiniert" : "User-defined",
                            value: String(format: "×%.2f", metabolismFactor)
                        ),
                        calcRow(
                            label: language == "de" ? "Schlafkorrektur" : "Sleep correction",
                            formula: language == "de"
                                ? "Schlaf ×0.9, Wach ×1.0"
                                : "Sleep ×0.9, Awake ×1.0",
                            value: String(format: "%.0f kcal", activeFinalBMR)
                        ),
                    ]
                )

                // ── NEAT ─────────────────────────────────────────────────
                calcSection(
                    icon: "figure.walk",
                    iconColor: .orange,
                    title: language == "de" ? "NEAT — 3-Komponenten-Modell" : "NEAT — 3-Component Model",
                    rows: [
                        calcRow(
                            label: language == "de" ? "① Geh-Kalorien" : "① Walk Calories",
                            formula: String(format: language == "de"
                                ? "%d Schr ÷ 100/min = %.0f min = %.2f h\n%.2f h × 2.0 × %.1f kcal/h"
                                : "%d steps ÷ 100/min = %.0f min = %.2f h\n%.2f h × 2.0 × %.1f kcal/h",
                                healthKit.activity.steps, nWalkMin, nWalkH, nWalkH, nBmrH),
                            value: String(format: "%.0f kcal", nStepsKcal)
                        ),
                        calcRow(
                            label: language == "de" ? "② Steh-Kalorien" : "② Stand Calories",
                            formula: String(format: language == "de"
                                ? "%.0f min Stand − %.0f min Geh = %.0f min rein\n%.2f h × 0.18 × %.1f kcal/h"
                                : "%.0f min stand − %.0f min walk = %.0f min net\n%.2f h × 0.18 × %.1f kcal/h",
                                nStandMin, nWalkMin, nPureStandMin, nPureStandH, nBmrH),
                            value: String(format: "%.0f kcal", nStandKcal)
                        ),
                        nMicroRow,
                        calcRow(
                            label: language == "de" ? "NEAT gesamt" : "NEAT total",
                            formula: String(format: "%.0f + %.0f + %.0f kcal",
                                           nStepsKcal, nStandKcal, nMicroKcal),
                            value: String(format: "%.0f kcal", activityResult.neatKcal)
                        ),
                    ]
                )

                // ── EAT ──────────────────────────────────────────────────
                calcSection(
                    icon: "dumbbell.fill",
                    iconColor: Color(red: 0.20, green: 0.78, blue: 0.35),
                    title: "EAT — Keytel-Formel",
                    rows: {
                        var rows: [AnyView] = [
                            calcRow(
                                label: language == "de"
                                    ? "Formel (\(isMale ? "Mann" : "Frau"))"
                                    : "Formula (\(isMale ? "Male" : "Female"))",
                                formula: isMale
                                    ? "−55.097 + 0.631×HR + 0.199×kg + 0.202×age"
                                    : "−20.402 + 0.447×HR − 0.126×kg + 0.074×age",
                                value: String(format: "%.1f kg · %d %@",
                                              weightInKg, userAge,
                                              language == "de" ? "J." : "yrs")
                            ),
                            calcRow(
                                label: "EPOC",
                                formula: language == "de"
                                    ? "Kraft-Training: ×1.20"
                                    : "Strength training: ×1.20",
                                value: ""
                            ),
                        ]
                        if healthKit.workouts.isEmpty {
                            rows.append(calcRow(
                                label: language == "de" ? "Keine Workouts heute" : "No workouts today",
                                formula: "–",
                                value: "0 kcal"
                            ))
                        } else {
                            for w in healthKit.workouts {
                                let kcal = ActivityCalculationService.eat(
                                    workout: w,
                                    weightKg: weightInKg,
                                    vo2Max: healthKit.vo2Max,
                                    hrRest: healthKit.activity.restingHeartRate,
                                    age: userAge,
                                    isMale: isMale
                                )
                                let mins = Int(w.duration / 60)
                                let hrStr = w.averageHeartRate
                                    .map { String(format: "Ø %.0f bpm · ", $0) } ?? ""
                                rows.append(calcRow(
                                    label: workoutActivityName(w.activityType),
                                    formula: "\(hrStr)\(mins) min",
                                    value: String(format: "%.0f kcal", kcal)
                                ))
                            }
                            rows.append(calcRow(
                                label: language == "de" ? "Gesamt (netto)" : "Total (net)",
                                formula: "Σ − BMR-Anteil",
                                value: String(format: "%.0f kcal", activityResult.eatKcal)
                            ))
                        }
                        return rows
                    }()
                )

                // ── Daily Journal ─────────────────────────────────────────────
                calcSection(
                    icon: "book.pages.fill",
                    iconColor: .purple,
                    title: language == "de" ? "Daily Journal — Anpassungen" : "Daily Journal — Adjustments",
                    rows: [
                        calcRow(
                            label: language == "de" ? "Krankheitsfaktor (Fieber)" : "Illness factor (fever)",
                            formula: language == "de"
                                ? "Kein Fieber ×1.0 · Leicht ×1.10 · Hoch ×1.18"
                                : "No fever ×1.0 · Low ×1.10 · High ×1.18",
                            value: String(format: "×%.2f", tdeeResult.krankheitsFaktor)
                        ),
                        calcRow(
                            label: language == "de" ? "PAL-Korrektur (Energielevel)" : "PAL correction (energy level)",
                            formula: language == "de"
                                ? "Leicht angeschlagen: Aktivität ×70% · Bettruhe: PAL = 1.1"
                                : "Mild: activity ×70% · Bedridden: PAL = 1.1",
                            value: ""
                        ),
                        calcRow(
                            label: language == "de" ? "Zyklusfaktor (nur Frauen)" : "Cycle factor (female only)",
                            formula: language == "de"
                                ? "Menstruation aktiv: BMR +5%"
                                : "Menstruation active: BMR +5%",
                            value: String(format: "×%.2f", tdeeResult.zyklusFaktor)
                        ),
                        calcRow(
                            label: language == "de" ? "Koffein-Thermogenese" : "Caffeine thermogenesis",
                            formula: "+15 kcal/100 mg · max. +60 kcal",
                            value: String(format: "+%.0f kcal", tdeeResult.koffeinBonus)
                        ),
                        calcRow(
                            label: language == "de" ? "Thermischer Effekt (TEF)" : "Thermic Effect of Food (TEF)",
                            formula: language == "de"
                                ? "Protein ×1.0 · KH ×0.3 · Fett ×0.135 kcal/g"
                                : "Protein ×1.0 · Carbs ×0.3 · Fat ×0.135 kcal/g",
                            value: String(format: "+%.0f kcal", tdeeResult.tefKcal)
                        ),
                    ]
                )

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 16)
        }
        .background(ObsidianBackground())
        .navigationTitle(language == "de" ? "Berechnungsmethoden" : "Calculation Methods")
        .navigationBarTitleDisplayMode(.large)
        .task { await healthKit.fetchAll() }
    }

    private func calcSection(icon: String, iconColor: Color, title: String, rows: [AnyView]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.custom("PingFangSC-Semibold", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                if idx > 0 {
                    Divider()
                        .padding(.horizontal, 16)
                }
                row
            }
            .padding(.bottom, 4)
        }
        .background(GlassCardBackground(cornerRadius: 18))
    }

    private func calcRow(label: String, formula: String, value: String) -> AnyView {
        AnyView(
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.custom("PingFangSC-Regular", size: 13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                    Text(formula)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !value.isEmpty {
                    Spacer()
                    Text(value)
                        .font(.custom("PingFangSC-Semibold", size: 13, relativeTo: .footnote))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        )
    }

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
                    .font(.custom("PingFangSC-Semibold", size: 15, relativeTo: .callout))
                Text(subtitle)
                    .font(.custom("PingFangSC-Regular", size: 12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(kcal) kcal")
                .font(.custom("PingFangSC-Semibold", size: 16, relativeTo: .callout))
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
                    Text(language == "de" ? "Dein Profil" : "Your Profile")
                        .font(.custom("PingFangSC-Semibold", size: 22, relativeTo: .title2))
                        .foregroundStyle(.primary)
                    Text(language == "de" ? "Passe hier deinen Namen und dein Geburtsdatum an." : "Adjust your name and birth date here.")
                        .font(.custom("PingFangSC-Regular", size: 13, relativeTo: .callout))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                        showProfileSidebar = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .glassEffect(in: .circle)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 18)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    // STAMMDATEN
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(accentBlue)
                                    .frame(width: 28)
                                Text(language == "de" ? "Vorname" : "First Name")
                                    .font(.custom("PingFangSC-Regular", size: 15))
                                    .foregroundStyle(.primary)
                                Spacer()
                                TextField("", text: $accountUsername)
                                    .font(.custom("PingFangSC-Semibold", size: 15))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.trailing)
                                    .submitLabel(.done)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)

                            Divider().padding(.leading, 50)

                            HStack {
                                Image(systemName: "calendar")
                                    .font(.system(size: 16))
                                    .foregroundStyle(accentBlue)
                                    .frame(width: 28)
                                Text(language == "de" ? "Geburtsdatum" : "Birth Date")
                                    .font(.custom("PingFangSC-Regular", size: 15))
                                    .foregroundStyle(.primary)
                                Spacer()
                                DatePicker("", selection: $birthDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .tint(accentBlue)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                        }
                        .background(GlassCardBackground(cornerRadius: 18))
                        .padding(.horizontal, 16)
                    }

                    VStack(spacing: 12) {
                        Text(language == "de" ? "Informationen" : "Information")
                            .font(.custom("PingFangSC-Semibold", size: 14))
                            .foregroundStyle(accentBlue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 6)

                        Text(language == "de" 
                             ? "Dein Geburtsdatum wird verwendet, um dein Alter für die Stoffwechselberechnungen (BMR) präzise zu bestimmen."
                             : "Your birth date is used to accurately determine your age for metabolic calculations (BMR).")
                            .font(.custom("PingFangSC-Regular", size: 13, relativeTo: .callout))
                            .foregroundStyle(.secondary)
                            .padding(16)
                            .background(GlassCardBackground(cornerRadius: 16))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 28, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: 28,
            style: .continuous
        ))
        .shadow(color: .black.opacity(0.18), radius: 32, x: 0, y: -8)
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
                            Color.white.opacity(0.08),
                            style: StrokeStyle(lineWidth: 10, lineCap: .butt, dash: [2, 5])
                        )
                        .rotationEffect(.degrees(135))
                    
                    // 2. Active Progress Arc (Glowing)
                    if !isSelectedFuture {
                        Circle()
                            .trim(from: 0, to: ringProgress * 0.75)
                            .stroke(
                                LinearGradient(
                                    colors: [accentBlue.opacity(0.5), accentBlue],
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
                                    .frame(width: 6, height: 6)
                                    .shadow(color: accentBlue, radius: 4)
                                    .position(x: x, y: y)
                            }
                        }
                    }

                    // 3. Center Instrument Data
                    VStack(spacing: 2) {
                        Text(!isSelectedFuture ? "\(Int(animatedBurn))" : "–")
                            .font(.custom("PingFangSC-Semibold", size: 38, relativeTo: .title))
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                        
                        HStack(spacing: 3) {
                            Text("kcal")
                                .font(.custom("PingFangSC-Regular", size: 12, relativeTo: .callout))
                                .foregroundStyle(Theme.textSecondary)
                            
                            if isSelectedToday {
                                Text("•")
                                    .font(.system(size: 8))
                                    .foregroundStyle(accentBlue.opacity(0.5))
                                
                                Text(currentTimeString)
                                    .font(.custom("PingFangSC-Regular", size: 11, relativeTo: .caption2))
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
                        Text(language == "de" ? "Instrumenten-Details" : "Instrument Details")
                            .font(.custom("PingFangSC-Medium", size: 11, relativeTo: .caption2))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .opacity(0.6)
                    }
                    .foregroundStyle(accentBlue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(accentBlue.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(accentBlue.opacity(0.30), lineWidth: 1))
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

    private var kpiRow: some View {
        HStack(spacing: 10) {
            kpiBox(
                icon: "target",
                value: isSelectedToday ? "\(Int(todayProjected))" : "\(Int(tdeeResult.tdeeTotal))",
                unit: "kcal",
                accent: false
            )
            kpiBox(
                icon: "arrow.up.arrow.down",
                value: isSelectedToday ? String(format: "%+.0f", vsYesterdayPercent) : "–",
                unit: language == "de" ? "% vs. Gestern" : "% vs. Yesterday",
                accent: false,
                tint: isSelectedToday ? vsYesterdayColor : nil
            )
            kpiBox(
                icon: "bolt.fill",
                value: healthKit.isAuthorized && isSelectedToday
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
                .font(.custom("PingFangSC-Semibold", size: 20, relativeTo: .title3))
                .foregroundStyle(valueFg)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(unit)
                .font(.custom("PingFangSC-Regular", size: 9, relativeTo: .caption2))
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
                .font(.custom("PingFangSC-Regular", size: 11, relativeTo: .caption2))
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
        .preferredColorScheme(.dark)
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
                    .font(.custom("PingFangSC-Semibold", size: 24, relativeTo: .title2))
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
                        .font(.custom("PingFangSC-Semibold", size: 24, relativeTo: .title2))
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
                        .font(.custom("PingFangSC-Semibold", size: 22, relativeTo: .title2))
                        .foregroundStyle(accentBlue)
                    Picker("", selection: $editHeightInches) {
                        ForEach(0...11, id: \.self) { v in Text("\(v)").tag(v) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 180)
                    .clipped()
                    .onChange(of: editHeightInches) { heightText = "\(editHeightFeet)'\(editHeightInches)\"" }
                    Text("in")
                        .font(.custom("PingFangSC-Semibold", size: 22, relativeTo: .title2))
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
                            .font(.custom("PingFangSC-Medium", size: 18, relativeTo: .headline))
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
                                .font(.custom("PingFangSC-Semibold", size: 56, relativeTo: .largeTitle))
                                .foregroundStyle(accentBlue)
                                .multilineTextAlignment(.center)
                                .frame(width: 140)
                            Text("%")
                                .font(.custom("PingFangSC-Regular", size: 22, relativeTo: .title2))
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
                            .font(.custom("PingFangSC-Medium", size: 18, relativeTo: .headline))
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
                        .font(.custom("PingFangSC-Semibold", size: 16, relativeTo: .subheadline))
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
                    .font(.custom("PingFangSC-Regular", size: 15, relativeTo: .subheadline))
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
                .font(.custom("PingFangSC-Semibold", size: 15, relativeTo: .subheadline))
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
                    .font(.custom("PingFangSC-Regular", size: 14, relativeTo: .callout))
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
                    .font(.custom("PingFangSC-Regular", size: 14, relativeTo: .callout))
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
