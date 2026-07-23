//
//  DataInsightView.swift
//  caloric
//

import SwiftUI
import Charts

// MARK: - ProfileField

enum ProfileField: String, Identifiable {
    case geschlecht, alter, groesse, gewicht, koerperfett, besonderheiten
    var id: String { rawValue }

    func title(language: String) -> String {
        switch self {
        case .geschlecht:    return language == "de" ? "Geschlecht"       : "Gender"
        case .alter:         return language == "de" ? "Alter"            : "Age"
        case .groesse:       return language == "de" ? "Größe"            : "Height"
        case .gewicht:       return language == "de" ? "Gewicht"          : "Weight"
        case .koerperfett:   return language == "de" ? "Körperfettanteil" : "Body Fat %"
        case .besonderheiten:return language == "de" ? "Besonderheiten"   : "Conditions"
        }
    }

    var isEditable: Bool {
        switch self {
        case .geschlecht, .alter: return false
        default: return true
        }
    }
}

// MARK: - DataInsightView

struct DataInsightView: View {

    // MARK: Props
    let accentBlue: Color
    let language: String
    let selectedGender: String?
    let femaleText: String
    let noConditionText: String
    let userAge: Int

    // MARK: Bindings
    @Binding var selectedTab: Int
    @Binding var weightText: String
    @Binding var weightUnit: String
    @Binding var heightText: String
    @Binding var heightUnit: String
    @Binding var bodyFatText: String
    @Binding var knowsBodyFat: Bool?
    @Binding var sleepHours: Double
    @Binding var selectedConditions: Set<String>
    @Binding var metabolismFactor: Double

    // MARK: Environment
    @Environment(HealthKitImportService.self) private var healthKit
    @Environment(JournalStore.self) private var store

    // MARK: State
    @AppStorage("pLM_geschlecht")    private var lastModGeschlecht:    Double = 0
    @AppStorage("pLM_alter")         private var lastModAlter:         Double = 0
    @AppStorage("pLM_groesse")       private var lastModGroesse:       Double = 0
    @AppStorage("pLM_gewicht")       private var lastModGewicht:       Double = 0
    @AppStorage("pLM_koerperfett")   private var lastModKoerperfett:   Double = 0
    @AppStorage("pLM_besonderheiten")private var lastModBesonderheiten:Double = 0

    @State private var selectedTabSource = 0
    @State private var editingField: ProfileField? = nil
    @State private var checkinExpanded = false
    @State private var selectedHistoryType: HistoryType? = nil

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    enum HistoryType: String, Identifiable {
        case steps, distance, hr, restingHR, stand, sleep, vo2, workouts
        var id: String { rawValue }
        
        func title(language: String) -> String {
            switch self {
            case .steps:     return language == "de" ? "Schritte" : "Steps"
            case .distance:  return language == "de" ? "Gehstrecke" : "Distance"
            case .hr:        return language == "de" ? "Herzfrequenz" : "Heart Rate"
            case .restingHR: return language == "de" ? "Ruheherzfrequenz" : "Resting HR"
            case .stand:     return language == "de" ? "Stehzeit" : "Stand Time"
            case .sleep:     return language == "de" ? "Schlaf" : "Sleep"
            case .vo2:       return "VO₂max"
            case .workouts:  return "Workouts"
            }
        }
        
        var unit: String {
            switch self {
            case .steps: return ""
            case .distance: return "km"
            case .hr, .restingHR: return "bpm"
            case .stand: return "min"
            case .sleep: return "h"
            case .vo2: return "ml/kg·min"
            case .workouts: return ""
            }
        }
        
        var healthKitPath: String {
            switch self {
            case .steps: return "Activity/Steps"
            case .distance: return "Activity/DistanceWalkingRunning"
            case .hr, .restingHR: return "Vitals/HeartRate"
            case .stand: return "Activity/AppleStandTime"
            case .sleep: return "Sleep/SleepAnalysis"
            case .vo2: return "Vitals/VO2Max"
            case .workouts: return "Workouts"
            }
        }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            CaloricBackground()
            VStack(spacing: 0) {
                headerSection
                tabPicker
                ScrollView {
                    if selectedTabSource == 0 { liveSourcesTab } else { stammdatenTab }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .sheet(item: $editingField) { field in
            FieldEditSheet(
                field: field,
                accentBlue: accentBlue,
                language: language,
                noConditionText: noConditionText,
                selectedGender: selectedGender,
                userAge: userAge,
                weightText: $weightText,
                weightUnit: $weightUnit,
                heightText: $heightText,
                heightUnit: $heightUnit,
                bodyFatText: $bodyFatText,
                knowsBodyFat: $knowsBodyFat,
                sleepHours: $sleepHours,
                selectedConditions: $selectedConditions,
                metabolismFactor: $metabolismFactor,
                onSave: { setLastMod(for: $0) }
            )
            .presentationBackground(Theme.canvas)
        }
        .sheet(item: $selectedHistoryType) { type in
            HistoryDetailSheet(type: type, healthKit: healthKit, language: language, accentBlue: accentBlue)
                .presentationDetents([.height(580)]) // Increased height
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.canvas)
        }
    }

    // MARK: Timestamp helpers

    private func lastMod(for field: ProfileField) -> Double {
        switch field {
        case .geschlecht:    return lastModGeschlecht
        case .alter:         return lastModAlter
        case .groesse:       return lastModGroesse
        case .gewicht:       return lastModGewicht
        case .koerperfett:   return lastModKoerperfett
        case .besonderheiten:return lastModBesonderheiten
        }
    }

    private func setLastMod(for field: ProfileField) {
        let now = Date().timeIntervalSince1970
        switch field {
        case .geschlecht:    lastModGeschlecht    = now
        case .alter:         lastModAlter         = now
        case .groesse:       lastModGroesse       = now
        case .gewicht:       lastModGewicht       = now
        case .koerperfett:   lastModKoerperfett   = now
        case .besonderheiten:lastModBesonderheiten = now
        }
    }

    private func lastModText(for field: ProfileField) -> String? {
        let ts = lastMod(for: field)
        guard ts > 0 else { return nil }
        let d = Date(timeIntervalSince1970: ts)
        let f = DateFormatter()
        f.locale = Locale(identifier: language == "de" ? "de_DE" : "en_US")
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language == "de" ? "Deine Daten" : "Your Data")
                .font(.poppins(size: LayoutMetrics.titleFontSize, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    // MARK: Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            tabButton(title: language == "de" ? "Live-Quellen" : "Live Sources", tag: 0)
            tabButton(title: language == "de" ? "Stammdaten" : "Profile", tag: 1)
        }
        .padding(4)
        .background(Theme.fieldFill)
        .clipShape(Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private func tabButton(title: String, tag: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selectedTabSource = tag }
        } label: {
            Text(title)
                .font(.poppins(size: 13, weight: .medium))
                .foregroundStyle(selectedTabSource == tag ? .white : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Group { if selectedTabSource == tag { Capsule().fill(accentBlue) } })
        }
        .buttonStyle(.plain)
    }

    // MARK: Live-Quellen Tab

    private var liveSourcesTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(language == "de"
                 ? "Daten, die laufend vom Gerät erfasst oder manuell im Check-in eingetragen werden."
                 : "Data continuously captured from your device or entered in the daily check-in.")
                .font(.poppins(size: 13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            VStack(spacing: 12) {
                liveCard(icon: "figure.run", iconColor: Theme.segEAT,
                         title: "Workouts",
                         subtitle: language == "de" ? "von Apple Health importiert" : "Imported from Apple Health",
                         frequency: language == "de" ? "laufend" : "live", freqColor: Theme.segEAT,
                         tags: ["EAT"], historyType: .workouts)
                
                liveCard(icon: "figure.walk", iconColor: Theme.segNEAT,
                         title: language == "de" ? "Schritte" : "Steps", subtitle: language == "de" ? "von Apple Health importiert" : "Imported from Apple Health",
                         frequency: language == "de" ? "laufend" : "live", freqColor: .green,
                         tags: ["NEAT"], historyType: .steps)
                
                liveCard(icon: "map.fill", iconColor: Theme.segNEAT,
                         title: language == "de" ? "Gehstrecke" : "Walking Distance", subtitle: language == "de" ? "von Apple Health importiert" : "Imported from Apple Health",
                         frequency: language == "de" ? "laufend" : "live", freqColor: .green,
                         tags: ["NEAT"], historyType: .distance)
                
                liveCard(icon: "waveform.path.ecg", iconColor: .pink,
                         title: language == "de" ? "Herzfrequenz" : "Heart Rate",
                         subtitle: language == "de" ? "von Apple Health importiert" : "Imported from Apple Health",
                         frequency: language == "de" ? "alle 5 Sek." : "every 5 s", freqColor: .pink,
                         tags: ["NEAT", "EAT"], historyType: .hr)
                
                liveCard(icon: "heart.fill", iconColor: .red,
                         title: language == "de" ? "Ruheherzfrequenz" : "Resting Heart Rate",
                         subtitle: language == "de" ? "von Apple Health importiert" : "Imported from Apple Health",
                         frequency: language == "de" ? "täglich" : "daily", freqColor: .orange,
                         tags: ["NEAT", "EAT"], historyType: .restingHR)
                
                liveCard(icon: "figure.stand", iconColor: .teal,
                         title: language == "de" ? "Stehzeit" : "Stand Time",
                         subtitle: language == "de" ? "von Apple Health importiert" : "Imported from Apple Health",
                         frequency: language == "de" ? "stündlich" : "hourly", freqColor: .teal,
                         tags: ["NEAT"], historyType: .stand)
                
                liveCard(icon: "moon.zzz.fill", iconColor: .indigo,
                         title: language == "de" ? "Schlafanalyse" : "Sleep Analysis",
                         subtitle: language == "de" ? "von Apple Health importiert" : "Imported from Apple Health",
                         frequency: language == "de" ? "täglich" : "daily", freqColor: .indigo,
                         tags: ["BMR"], historyType: .sleep)
                
                liveCard(icon: "lungs.fill", iconColor: .cyan,
                         title: "VO₂max",
                         subtitle: language == "de" ? "von Apple Health importiert" : "Imported from Apple Health",
                         frequency: language == "de" ? "wöchentlich" : "weekly", freqColor: .cyan,
                         tags: ["EAT"], historyType: .vo2)
                
                checkinCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
    }

    // MARK: Check-in Card

    private var checkinCard: some View {
        let entry = store.entry(for: today)
        let meals = ["breakfast", "lunch", "dinner", "snack"]
        let totalProtein = meals.compactMap { entry.proteinByMeal[$0] }.reduce(0, +)
        let totalCarbs   = meals.compactMap { entry.carbsByMeal[$0]   }.reduce(0, +)
        let totalFat     = meals.compactMap { entry.fatByMeal[$0]     }.reduce(0, +)

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { checkinExpanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(accentBlue.opacity(0.12)).frame(width: 40, height: 40)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .medium)).foregroundStyle(accentBlue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language == "de" ? "Heutiger Check-in" : "Today's Check-in")
                            .font(.poppins(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text(language == "de" ? "Manuell aus dem Daily Journal" : "Manually from the Daily Journal")
                            .font(.poppins(size: 9, weight: .regular)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(accentBlue)
                            Text(language == "de" ? "täglich" : "daily")
                                .font(.poppins(size: 10, weight: .medium)).foregroundStyle(accentBlue)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right").font(.system(size: 7, weight: .bold))
                        Text("TEF")
                    }
                    .font(.poppins(size: 11, weight: .medium)).foregroundStyle(accentBlue)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(accentBlue.opacity(0.08)).clipShape(Capsule())
                    
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right").font(.system(size: 7, weight: .bold))
                        Text("BMR")
                    }
                    .font(.poppins(size: 11, weight: .medium)).foregroundStyle(accentBlue)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(accentBlue.opacity(0.08)).clipShape(Capsule())
                }
                .padding(.leading, 52)
                
                Spacer()
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accentBlue.opacity(0.5))
                    .rotationEffect(.degrees(checkinExpanded ? 180 : 0))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { checkinExpanded.toggle() }
                    }
            }

            if checkinExpanded {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        if selectedGender == femaleText {
                            checkinRow(icon: "drop.fill", iconColor: .pink, label: "Menstruation",
                                       value: entry.menstruationActive == true
                                           ? (language == "de" ? "Aktiv" : "Active")
                                           : (language == "de" ? "Nein" : "No"))
                        }
                        checkinRow(icon: "bandage.fill", iconColor: .orange,
                                   label: language == "de" ? "Krank" : "Sick",
                                   value: entry.sickActive ? (language == "de" ? "Ja" : "Yes") : (language == "de" ? "Nein" : "No"))
                        checkinRow(icon: "cup.and.saucer.fill", iconColor: accentBlue, label: "Koffein",
                                   value: entry.caffeineMg > 0 ? "\(Int(entry.caffeineMg)) mg" : "0 mg")
                        checkinRow(icon: "fork.knife", iconColor: Theme.segNEAT, label: "Protein",
                                   value: totalProtein > 0 ? "\(Int(totalProtein)) g" : "– g")
                        checkinRow(icon: "bolt.fill", iconColor: accentBlue,
                                   label: language == "de" ? "Kohlenhydrate" : "Carbs",
                                   value: totalCarbs > 0 ? "\(Int(totalCarbs)) g" : "– g")
                        checkinRow(icon: "drop.triangle.fill", iconColor: .orange,
                                   label: language == "de" ? "Fett" : "Fat",
                                   value: totalFat > 0 ? "\(Int(totalFat)) g" : "– g")
                    }
                    .padding(.bottom, 16)
                    
                    Button {
                        withAnimation { selectedTab = 2 }
                    } label: {
                        HStack {
                            Image(systemName: "pencil.and.outline")
                            Text(language == "de" ? "Im Daily Journal bearbeiten" : "Edit in Daily Journal")
                        }
                        .font(.poppins(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(accentBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: accentBlue.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(GlassCardBackground(cornerRadius: 16))
    }

    private func checkinRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(iconColor).frame(width: 20)
            Text(label).font(.poppins(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value).font(.poppins(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: Stammdaten Tab

    private var stammdatenTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(language == "de"
                 ? "Deine fest hinterlegten Profilwerte. Tippe auf eine Kachel, um sie zu bearbeiten."
                 : "Fixed profile values. Tap a tile to edit it.")
                .font(.poppins(size: 13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 20)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                profileCard(
                    field: .geschlecht,
                    label: language == "de" ? "GESCHLECHT" : "GENDER",
                    value: selectedGender ?? (language == "de" ? "Nicht gesetzt" : "Not set"))
                profileCard(
                    field: .alter,
                    label: language == "de" ? "ALTER" : "AGE",
                    value: "\(userAge) \(language == "de" ? "Jahre" : "yrs")")
                profileCard(
                    field: .groesse,
                    label: language == "de" ? "GRÖSSE" : "HEIGHT",
                    value: heightText.isEmpty ? "–" : "\(heightText) \(heightUnit)")
                profileCard(
                    field: .gewicht,
                    label: language == "de" ? "GEWICHT" : "WEIGHT",
                    value: weightText.isEmpty ? "–" : "\(weightText) \(weightUnit)")
                profileCard(
                    field: .koerperfett,
                    label: language == "de" ? "KÖRPERFETT" : "BODY FAT",
                    value: bodyFatText.isEmpty
                        ? (language == "de" ? "Nicht gesetzt" : "Not set")
                        : "\(bodyFatText) %")
                profileCard(
                    field: .besonderheiten,
                    label: language == "de" ? "BESONDERHEITEN" : "CONDITIONS",
                    value: besonderheitenSummary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
    }

    private var besonderheitenSummary: String {
        let active = selectedConditions.filter { $0 != noConditionText }
        guard !active.isEmpty else { return noConditionText }
        return active.map { full -> String in
            if full.contains("Hypothyreose") || full.lowercased().contains("hypothyroid") { return "Hypothyreose" }
            if full.contains("Hyperthyreose") || full.lowercased().contains("hyperthyroid") { return "Hyperthyreose" }
            if full.contains("PCOS") { return "PCOS" }
            if full.contains("Menopause") { return "Menopause" }
            return full
        }.joined(separator: " · ")
    }

    // MARK: Profile Card

    private func profileCard(field: ProfileField, label: String, value: String) -> some View {
        Button { editingField = field } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Label
                Text(label)
                    .font(.poppins(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(0.4)
                    .padding(.bottom, 6)

                // Value
                Text(value)
                    .font(.poppins(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                // Timestamp
                if let ts = lastModText(for: field) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textSecondary.opacity(0.4))
                        Text(ts)
                            .font(.poppins(size: 9, weight: .regular))
                            .foregroundStyle(Theme.textSecondary.opacity(0.4))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                } else {
                    // invisible placeholder keeps height consistent
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text("–")
                            .font(.poppins(size: 9, weight: .regular))
                    }
                    .opacity(0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .background(GlassCardBackground(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(accentBlue.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Live Card

    private func liveCard(icon: String, iconColor: Color,
                          title: String, subtitle: String,
                          frequency: String, freqColor: Color,
                          tags: [String], historyType: HistoryType) -> some View {
        Button {
            selectedHistoryType = historyType
        } label: {
            HStack(alignment: .center, spacing: 12) {
                // Primary Icon centered vertically
                ZStack {
                    Circle().fill(iconColor.opacity(0.12)).frame(width: 40, height: 40)
                    Image(systemName: icon).font(.system(size: 16, weight: .medium)).foregroundStyle(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 14) { // More spacing between header and tags
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.poppins(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text(subtitle).font(.poppins(size: 9, weight: .regular)).foregroundStyle(Theme.textSecondary)
                    }
                    
                    // Tags with refined Arrow prefix
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 7, weight: .bold))
                                Text(tag)
                            }
                            .font(.poppins(size: 10, weight: .medium)).foregroundStyle(accentBlue)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(accentBlue.opacity(0.08)).clipShape(Capsule())
                        }
                    }
                }
                
                Spacer()
                
                // Frequency label centered vertically on the right
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(freqColor)
                    Text(frequency).font(.poppins(size: 10, weight: .medium)).foregroundStyle(freqColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .background(GlassCardBackground(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - HistoryDetailSheet

private struct HistoryDetailSheet: View {
    let type: DataInsightView.HistoryType
    let healthKit: HealthKitImportService
    let language: String
    let accentBlue: Color
    
    @State private var rawSelectedDate: Date?
    
    struct HistoryPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }
    
    private var historyData: [HistoryPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var points = [HistoryPoint]()
        
        for i in (0..<28).reversed() {
            guard let date = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            let key = HealthKitImportService.dateKey(date)
            let val: Double = {
                guard let snap = healthKit.history[key] else { return 0 }
                switch type {
                case .steps:     return Double(snap.activity.steps)
                case .distance:  return snap.activity.distanceMeters / 1000.0
                case .hr:        return snap.activity.avgHeartRateWaking ?? 0
                case .restingHR: return snap.activity.restingHeartRate ?? 0
                case .stand:     return snap.activity.standTimeMinutes
                case .sleep:     return snap.sleep?.totalAsleepSeconds ?? 0
                case .vo2:       return healthKit.vo2Max ?? 0
                case .workouts:  return Double(snap.workouts.count)
                }
            }()
            points.append(HistoryPoint(date: date, value: val))
        }
        return points
    }
    
    private var selectedPoint: HistoryPoint? {
        if let d = rawSelectedDate {
            return historyData.min(by: { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) })
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(type.title(language: language))
                        .font(.poppins(size: 22, weight: .bold))
                    Spacer()
                    Text(language == "de" ? "Verlauf" : "History")
                        .font(.poppins(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                
                if let sel = selectedPoint {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        let displayVal: String = {
                            if type == .sleep {
                                let h = Int(sel.value / 3600)
                                let m = Int((sel.value.truncatingRemainder(dividingBy: 3600)) / 60)
                                return "\(h)h \(m)m"
                            }
                            return String(format: type.rawValue.contains("distance") || type.rawValue.contains("vo2") ? "%.2f" : "%.0f", sel.value)
                        }()
                        Text(displayVal)
                            .font(.poppins(size: 34, weight: .heavy))
                            .foregroundStyle(accentBlue)
                        if type != .sleep {
                            Text(type.unit)
                                .font(.poppins(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text(sel.date.formatted(.dateTime.day().month().year()))
                            .font(.poppins(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                } else {
                    Text(language == "de" ? "Halte den Finger auf das Diagramm" : "Press and hold on the chart")
                        .font(.poppins(size: 14, weight: .regular))
                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                        .frame(height: 50)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 36)
            .padding(.bottom, 28)
            
            // Content (Chart or List)
            ScrollView {
                VStack(spacing: 32) {
                    if type == .hr {
                        heartRateLogView
                    } else if type == .sleep {
                        sleepDetailView
                    } else {
                        genericChartView
                    }
                    
                    appleHealthButton
                        .padding(.top, 10)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
    }
    
    @ViewBuilder
    private var genericChartView: some View {
        Chart {
            ForEach(historyData) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(accentBlue.gradient)
                .cornerRadius(4)
                .opacity(selectedPoint == nil || selectedPoint?.date == point.date ? 1.0 : 0.4)
            }
        }
        .chartXSelection(value: $rawSelectedDate)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { value in
                AxisGridLine().foregroundStyle(Theme.divider)
                AxisValueLabel(format: .dateTime.day().month())
                    .font(.poppins(size: 11, weight: .regular))
            }
        }
        .frame(height: 200)
    }
    
    @ViewBuilder
    private var heartRateLogView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language == "de" ? "Letzte Messungen" : "Recent Samples")
                .font(.poppins(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            
            VStack(spacing: 1) {
                ForEach(healthKit.recentHR.prefix(40)) { sample in
                    HStack {
                        Text("\(Int(sample.bpm))")
                            .font(.poppins(size: 17, weight: .bold))
                            .foregroundStyle(.pink)
                        Text("bpm")
                            .font(.poppins(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(sample.date.formatted(.dateTime.hour().minute()))
                            .font(.poppins(size: 13, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                        Text(sample.date.formatted(.dateTime.day().month()))
                            .font(.poppins(size: 12, weight: .regular))
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    }
                    .padding(.vertical, 12)
                    if sample.id != healthKit.recentHR.prefix(40).last?.id {
                        Divider().background(Theme.divider)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.fieldFill.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
    
    @ViewBuilder
    private var sleepDetailView: some View {
        VStack(spacing: 32) {
            // Stacked Bar Chart for Stages
            Chart {
                ForEach(historyData) { point in
                    if let stages = healthKit.history[HealthKitImportService.dateKey(point.date)]?.sleep?.stages {
                        ForEach(stages) { stage in
                            BarMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("Duration", stage.duration / 3600.0)
                            )
                            .foregroundStyle(by: .value("Stage", stage.type.rawValue))
                        }
                    }
                }
            }
            .chartForegroundStyleScale([
                "deep": Color.indigo,
                "core": Color.blue,
                "rem":  Color.teal,
                "awake": Color.orange,
                "inBed": Color.gray.opacity(0.3)
            ])
            .chartXSelection(value: $rawSelectedDate)
            .frame(height: 200)
            
            if let sel = selectedPoint, let stages = healthKit.history[HealthKitImportService.dateKey(sel.date)]?.sleep?.stages {
                VStack(alignment: .leading, spacing: 14) {
                    Text(language == "de" ? "Aufschlüsselung" : "Breakdown")
                        .font(.poppins(size: 15, weight: .semibold))
                    
                    let grouped = Dictionary(grouping: stages, by: { $0.type })
                    VStack(spacing: 10) {
                        ForEach(HKSleepType.allCases, id: \.self) { type in
                            let duration = grouped[type]?.reduce(0) { $0 + $1.duration } ?? 0
                            if duration > 0 {
                                HStack {
                                    Circle().fill(sleepColor(for: type)).frame(width: 8, height: 8)
                                    Text(sleepLabel(for: type))
                                        .font(.poppins(size: 14, weight: .medium))
                                    Spacer()
                                    Text("\(Int(duration/3600))h \(Int((duration.truncatingRemainder(dividingBy: 3600))/60))m")
                                        .font(.poppins(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Theme.fieldFill.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }
    
    private func sleepColor(for type: HKSleepType) -> Color {
        switch type {
        case .deep: return .indigo
        case .core: return .blue
        case .rem: return .teal
        case .awake: return .orange
        case .inBed: return .gray.opacity(0.5)
        }
    }
    
    private func sleepLabel(for type: HKSleepType) -> String {
        switch type {
        case .deep: return language == "de" ? "Tiefschlaf" : "Deep"
        case .core: return language == "de" ? "Kernschlaf" : "Core"
        case .rem: return "REM"
        case .awake: return language == "de" ? "Wach" : "Awake"
        case .inBed: return language == "de" ? "Im Bett" : "In Bed"
        }
    }
    
    private var appleHealthButton: some View {
        Button {
            let urlStr = "x-apple-health://app/\(type.healthKitPath)"
            if let url = URL(string: urlStr) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 20))
                Text(language == "de" ? "Details in Apple Health ansehen" : "View Details in Apple Health")
                    .font(.poppins(size: 15, weight: .semibold))
            }
            .foregroundStyle(accentBlue)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(accentBlue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(accentBlue.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FieldEditSheet

private struct FieldEditSheet: View {

    let field: ProfileField
    let accentBlue: Color
    let language: String
    let noConditionText: String
    let selectedGender: String?
    let userAge: Int

    @Binding var weightText: String
    @Binding var weightUnit: String
    @Binding var heightText: String
    @Binding var heightUnit: String
    @Binding var bodyFatText: String
    @Binding var knowsBodyFat: Bool?
    @Binding var sleepHours: Double
    @Binding var selectedConditions: Set<String>
    @Binding var metabolismFactor: Double

    var onSave: (ProfileField) -> Void

    @State private var editWeightKg: Int = 70
    @State private var editWeightLb: Int = 154
    @State private var editHeightCm: Int = 170
    @FocusState private var bodyFatFocused: Bool

    @Environment(\.dismiss) private var dismiss

    private var t: Translations { Translations(language: language) }

    private var conditionOptions: [(label: String, factor: Double)] {
        [(t.hypothyroidism, 0.92),
         (t.hyperthyroidism, 1.07),
         (t.pcos, 0.85),
         (t.menopause, 0.95)]
    }

    private var activeConditions: Set<String> {
        selectedConditions.filter { $0 != noConditionText }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                fieldContent
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 50)
            }
            .background(CaloricBackground())
            .navigationTitle(field.title(language: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(field.isEditable
                           ? (language == "de" ? "Fertig" : "Done")
                           : (language == "de" ? "Schließen" : "Close")) {
                        if field.isEditable { onSave(field) }
                        dismiss()
                    }
                    .font(.poppins(size: 15, weight: .semibold))
                    .foregroundStyle(accentBlue)
                }
            }
        }
    }

    @ViewBuilder
    private var fieldContent: some View {
        switch field {
        case .geschlecht:
            VStack(alignment: .leading, spacing: 10) {
                Text(language == "de" ? "Biologisches Geschlecht" : "Biological Gender")
                    .font(.poppins(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text(selectedGender ?? "–")
                    .font(.poppins(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(language == "de" ? "Dieses Feld ist nach der Ersteinrichtung schreibgeschützt." : "This field is read-only after setup.")
                    .font(.poppins(size: 12, weight: .regular))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
        case .alter:
            VStack(alignment: .leading, spacing: 10) {
                Text(language == "de" ? "Alter" : "Age")
                    .font(.poppins(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text("\(userAge) \(language == "de" ? "Jahre" : "yrs")")
                    .font(.poppins(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(language == "de" ? "Das Alter basiert auf deinem Geburtsdatum." : "Age is based on your birth date.")
                    .font(.poppins(size: 12, weight: .regular))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
        case .groesse:
            VStack(spacing: 20) {
                Picker("", selection: $heightUnit) {
                    Text("cm").tag("cm")
                    Text("ft/in").tag("ft")
                }
                .pickerStyle(.segmented)
                
                if heightUnit == "cm" {
                    HStack {
                        TextField("170", text: $heightText)
                            .keyboardType(.numberPad)
                            .font(.poppins(size: 32, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text("cm")
                            .font(.poppins(size: 18, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding()
                    .glassCard(16)
                } else {
                    // Logic for ft/in input if needed
                    Text(heightText)
                }
            }
        case .gewicht:
            VStack(spacing: 20) {
                Picker("", selection: $weightUnit) {
                    Text("kg").tag("kg")
                    Text("lb").tag("lb")
                }
                .pickerStyle(.segmented)
                
                HStack {
                    TextField("70", text: $weightText)
                        .keyboardType(.decimalPad)
                        .font(.poppins(size: 32, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text(weightUnit)
                        .font(.poppins(size: 18, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding()
                .glassCard(16)
            }
        case .koerperfett:
            VStack(spacing: 20) {
                HStack {
                    TextField("15", text: $bodyFatText)
                        .keyboardType(.decimalPad)
                        .focused($bodyFatFocused)
                        .font(.poppins(size: 32, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("%")
                        .font(.poppins(size: 18, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding()
                .glassCard(16)
                
                Toggle(language == "de" ? "Körperfettanteil bekannt" : "Know body fat", isOn: Binding(
                    get: { knowsBodyFat ?? false },
                    set: { knowsBodyFat = $0 }
                ))
                .font(.poppins(size: 15, weight: .medium))
            }
        case .besonderheiten:
            VStack(alignment: .leading, spacing: 16) {
                Text(language == "de" ? "Wähle zutreffende Bedingungen aus:" : "Select applicable conditions:")
                    .font(.poppins(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                
                ForEach(conditionOptions, id: \.label) { opt in
                    Button {
                        if selectedConditions.contains(opt.label) {
                            selectedConditions.remove(opt.label)
                        } else {
                            selectedConditions.insert(opt.label)
                        }
                    } label: {
                        HStack {
                            Text(opt.label)
                                .font(.poppins(size: 15, weight: .medium))
                            Spacer()
                            if selectedConditions.contains(opt.label) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(accentBlue)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(Theme.textSecondary.opacity(0.3))
                            }
                        }
                        .padding()
                        .background(Theme.fieldFill)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                
                Divider().padding(.vertical, 10)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(language == "de" ? "Stoffwechsel-Anpassung" : "Metabolism Factor")
                        .font(.poppins(size: 14, weight: .medium))
                    HStack {
                        Text("\(Int(metabolismFactor * 100))%")
                            .font(.poppins(size: 18, weight: .bold))
                            .foregroundStyle(accentBlue)
                        Slider(value: $metabolismFactor, in: 0.7...1.3, step: 0.01)
                            .tint(accentBlue)
                    }
                }
                .padding()
                .glassCard(16)
            }
        }
    }
}
