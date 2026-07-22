//
//  DataInsightView.swift
//  caloric
//

import SwiftUI

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

    @State private var selectedTab = 0
    @State private var editingField: ProfileField? = nil
    @State private var checkinExpanded = false

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    // MARK: Body

    var body: some View {
        ZStack {
            CaloricBackground()
            VStack(spacing: 0) {
                headerSection
                tabPicker
                ScrollView {
                    if selectedTab == 0 { liveSourcesTab } else { stammdatenTab }
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
            Text(language == "de" ? "Stammdaten & Datenquellen im System" : "Profile data & data sources")
                .font(.poppins(size: 13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selectedTab = tag }
        } label: {
            Text(title)
                .font(.poppins(size: 13, weight: .medium))
                .foregroundStyle(selectedTab == tag ? .white : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Group { if selectedTab == tag { Capsule().fill(accentBlue) } })
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

            VStack(spacing: 10) {
                liveCard(icon: "figure.run", iconColor: Theme.segEAT,
                         title: "Workouts", subtitle: "Apple Watch · Fitness-App",
                         frequency: language == "de" ? "täglich" : "daily", freqColor: Theme.segEAT,
                         tags: ["→ EAT"], value: workoutValue)
                liveCard(icon: "figure.walk", iconColor: Theme.segNEAT,
                         title: language == "de" ? "Schritte" : "Steps", subtitle: "Apple Watch · iPhone",
                         frequency: language == "de" ? "laufend" : "live", freqColor: .green,
                         tags: ["→ NEAT"], value: stepsValue)
                liveCard(icon: "map.fill", iconColor: Theme.segNEAT,
                         title: language == "de" ? "Gehstrecke" : "Walking Distance", subtitle: "Apple Watch · iPhone",
                         frequency: language == "de" ? "laufend" : "live", freqColor: .green,
                         tags: ["→ NEAT"], value: distanceValue)
                liveCard(icon: "waveform.path.ecg", iconColor: .pink,
                         title: language == "de" ? "Herzfrequenz" : "Heart Rate",
                         subtitle: language == "de" ? "Optischer Sensor · Apple Watch" : "Optical sensor · Apple Watch",
                         frequency: language == "de" ? "alle 5 Sek." : "every 5 s", freqColor: .pink,
                         tags: ["→ NEAT", "→ EAT"], value: heartRateValue)
                liveCard(icon: "heart.fill", iconColor: .red,
                         title: language == "de" ? "Ruheherzfrequenz" : "Resting Heart Rate",
                         subtitle: language == "de" ? "Tägl. Schätzung · Apple Health" : "Daily estimate · Apple Health",
                         frequency: language == "de" ? "täglich" : "daily", freqColor: .orange,
                         tags: ["→ NEAT", "→ EAT"], value: restingHRValue)
                liveCard(icon: "figure.stand", iconColor: .teal,
                         title: language == "de" ? "Stehzeit" : "Stand Time",
                         subtitle: language == "de" ? "Apple Watch · Bewegungssensor" : "Apple Watch · Motion sensor",
                         frequency: language == "de" ? "stündlich" : "hourly", freqColor: .teal,
                         tags: ["→ NEAT"], value: standValue)
                liveCard(icon: "moon.zzz.fill", iconColor: .indigo,
                         title: language == "de" ? "Schlafanalyse" : "Sleep Analysis",
                         subtitle: language == "de" ? "Apple Watch · Schlafsensor" : "Apple Watch · Sleep sensor",
                         frequency: language == "de" ? "nächtlich" : "nightly", freqColor: .indigo,
                         tags: ["→ BMR"], value: sleepValue)
                liveCard(icon: "lungs.fill", iconColor: .cyan,
                         title: "VO₂max",
                         subtitle: language == "de" ? "Laufmessung · Apple Watch" : "Run measurement · Apple Watch",
                         frequency: language == "de" ? "wöchentlich" : "weekly", freqColor: .cyan,
                         tags: ["→ EAT"], value: vo2Value)
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
                        Text(language == "de" ? "Heutiges Check-in" : "Today's Check-in")
                            .font(.poppins(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text(language == "de" ? "Manuell · Daily Journal" : "Manual · Daily Journal")
                            .font(.poppins(size: 11, weight: .regular)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle().fill(accentBlue).frame(width: 6, height: 6)
                            Text(language == "de" ? "täglich" : "daily")
                                .font(.poppins(size: 10, weight: .medium)).foregroundStyle(accentBlue)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(accentBlue.opacity(0.5))
                            .rotationEffect(.degrees(checkinExpanded ? 180 : 0))
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Text("→ TEF").font(.poppins(size: 11, weight: .medium)).foregroundStyle(accentBlue)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(accentBlue.opacity(0.08)).clipShape(Capsule())
                Text("→ BMR").font(.poppins(size: 11, weight: .medium)).foregroundStyle(accentBlue)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(accentBlue.opacity(0.08)).clipShape(Capsule())
                Spacer()
                Text(entry.sickActive
                     ? (language == "de" ? "Krank" : "Sick")
                     : (entry.caffeineMg > 0 ? "\(Int(entry.caffeineMg)) mg Koffein"
                        : (language == "de" ? "Keine Einträge" : "No entries")))
                    .font(.poppins(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            }

            if checkinExpanded {
                VStack(spacing: 0) {
                    Divider().padding(.bottom, 10)
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
                        let kcal = Int(totalProtein * 4 + totalCarbs * 4 + totalFat * 9)
                        checkinRow(icon: "flame.fill", iconColor: Theme.segTEF,
                                   label: language == "de" ? "Makros gesamt" : "Total macros",
                                   value: kcal > 0 ? "\(kcal) kcal" : "– kcal")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
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

    // MARK: Live Values

    private var workoutValue: String? {
        let c = healthKit.workouts.count
        guard c > 0 else { return language == "de" ? "Keine heute" : "None today" }
        return "\(c) Workout\(c == 1 ? "" : "s")"
    }
    private var stepsValue: String? {
        let s = healthKit.activity.steps; guard s > 0 else { return nil }
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = "."
        return (f.string(from: s as NSNumber) ?? "\(s)") + (language == "de" ? " Schritte" : " steps")
    }
    private var distanceValue: String? {
        let m = healthKit.activity.distanceMeters; guard m > 0 else { return nil }
        return String(format: "%.2f km", m / 1000)
    }
    private var heartRateValue: String? {
        guard let bpm = healthKit.activity.avgHeartRateWaking, bpm > 0 else { return nil }
        return String(format: "Ø %.0f bpm", bpm)
    }
    private var restingHRValue: String? {
        guard let bpm = healthKit.activity.restingHeartRate, bpm > 0 else { return nil }
        return String(format: "%.0f bpm", bpm)
    }
    private var standValue: String? {
        let m = healthKit.activity.standTimeMinutes; guard m > 0 else { return nil }
        return String(format: "%.0f min", m)
    }
    private var sleepValue: String? {
        guard let s = healthKit.sleep else { return nil }
        let totalH = s.durationSeconds / 3600
        let h = Int(totalH); let m = Int((totalH - Double(h)) * 60)
        return language == "de" ? "\(h) Std \(m) Min" : "\(h)h \(m)m"
    }
    private var vo2Value: String? {
        guard let v = healthKit.vo2Max, v > 0 else { return nil }
        return String(format: "%.1f ml/kg·min", v)
    }

    // MARK: Stammdaten Tab

    private var stammdatenTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(language == "de"
                 ? "Fest hinterlegte Profilwerte. Tippe auf eine Kachel, um sie zu bearbeiten."
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
                          tags: [String], value: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(iconColor.opacity(0.12)).frame(width: 40, height: 40)
                    Image(systemName: icon).font(.system(size: 16, weight: .medium)).foregroundStyle(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.poppins(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(.poppins(size: 11, weight: .regular)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(freqColor).frame(width: 6, height: 6)
                    Text(frequency).font(.poppins(size: 10, weight: .medium)).foregroundStyle(freqColor)
                }
            }
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag).font(.poppins(size: 11, weight: .medium)).foregroundStyle(accentBlue)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(accentBlue.opacity(0.08)).clipShape(Capsule())
                }
                if let v = value {
                    Spacer()
                    Text(v).font(.poppins(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(14)
        .background(GlassCardBackground(cornerRadius: 16))
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
                if field.isEditable {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(language == "de" ? "Abbrechen" : "Cancel") { dismiss() }
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .onAppear {
            editWeightKg = Int(Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 70)
            editWeightLb = Int(Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 154)
            editHeightCm = Int(Double(heightText.replacingOccurrences(of: ",", with: ".")) ?? 170)
        }
    }

    // MARK: Field routing

    @ViewBuilder
    private var fieldContent: some View {
        switch field {
        case .geschlecht:
            readOnlyCard(
                icon: "person.fill",
                value: selectedGender ?? (language == "de" ? "Nicht gesetzt" : "Not set"),
                note: language == "de"
                    ? "Das Geschlecht wurde beim Onboarding festgelegt und kann hier nicht geändert werden."
                    : "Gender was set during onboarding and cannot be changed here.")
        case .alter:
            readOnlyCard(
                icon: "calendar",
                value: "\(userAge) \(language == "de" ? "Jahre" : "years")",
                note: language == "de"
                    ? "Das Alter wird automatisch aus deinem Geburtsdatum berechnet."
                    : "Age is computed automatically from your birth date.")
        case .gewicht:
            weightEditor
        case .groesse:
            heightEditor
        case .koerperfett:
            bodyFatEditor
        case .besonderheiten:
            conditionsEditor
        }
    }

    // MARK: Read-only card

    private func readOnlyCard(icon: String, value: String, note: String) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(accentBlue.opacity(0.5))
                Text(value)
                    .font(.poppins(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(GlassCardBackground(cornerRadius: 18))

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    .padding(.top, 1)
                Text(note)
                    .font(.poppins(size: 13, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: Weight Editor

    private var weightEditor: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("", selection: $weightUnit) {
                Text("kg").tag("kg")
                Text("lb").tag("lb")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)

            HStack {
                Spacer()
                Picker("", selection: weightUnit == "kg" ? $editWeightKg : $editWeightLb) {
                    if weightUnit == "kg" {
                        ForEach(20...300, id: \.self) { v in Text("\(v)").tag(v) }
                    } else {
                        ForEach(44...661, id: \.self) { v in Text("\(v)").tag(v) }
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 130, height: 200)
                .clipped()
                .onChange(of: editWeightKg) {
                    if weightUnit == "kg" { weightText = "\(editWeightKg)" }
                }
                .onChange(of: editWeightLb) {
                    if weightUnit != "kg" { weightText = "\(editWeightLb)" }
                }

                Text(weightUnit)
                    .font(.poppins(size: 26, weight: .semibold))
                    .foregroundStyle(accentBlue)
                    .frame(width: 44, alignment: .leading)
                Spacer()
            }
        }
        .padding(20)
        .background(GlassCardBackground(cornerRadius: 18))
    }

    // MARK: Height Editor

    private var heightEditor: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Spacer()
                Picker("", selection: $editHeightCm) {
                    ForEach(100...230, id: \.self) { v in Text("\(v)").tag(v) }
                }
                .pickerStyle(.wheel)
                .frame(width: 130, height: 200)
                .clipped()
                .onChange(of: editHeightCm) { heightText = "\(editHeightCm)" }

                Text("cm")
                    .font(.poppins(size: 26, weight: .semibold))
                    .foregroundStyle(accentBlue)
                    .frame(width: 50, alignment: .leading)
                Spacer()
            }
        }
        .padding(20)
        .background(GlassCardBackground(cornerRadius: 18))
    }

    // MARK: Body Fat Editor

    private var bodyFatEditor: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                pillToggle(label: language == "de" ? "Ich kenne ihn" : "I know it",
                           isActive: knowsBodyFat == true) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        knowsBodyFat = knowsBodyFat == true ? nil : true
                    }
                }
                pillToggle(label: language == "de" ? "Nicht bekannt" : "Unknown",
                           isActive: knowsBodyFat == false) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if knowsBodyFat == true { bodyFatText = "" }
                        knowsBodyFat = knowsBodyFat == false ? nil : false
                    }
                }
            }

            if knowsBodyFat == true {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("15", text: $bodyFatText)
                        .keyboardType(.decimalPad)
                        .font(.poppins(size: 56, weight: .semibold))
                        .foregroundStyle(accentBlue)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 160)
                        .focused($bodyFatFocused)
                    Text("%")
                        .font(.poppins(size: 26, weight: .regular))
                        .foregroundStyle(accentBlue.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
                .onAppear { bodyFatFocused = true }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)
        .background(GlassCardBackground(cornerRadius: 18))
    }

    // MARK: Conditions Editor

    private var conditionsEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(language == "de"
                 ? "Wähle Besonderheiten, die deinen Stoffwechsel beeinflussen."
                 : "Select conditions that affect your metabolism.")
                .font(.poppins(size: 13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 8) {
                ForEach(conditionOptions, id: \.label) { option in
                    let isActive = activeConditions.contains(option.label)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if isActive {
                                selectedConditions.remove(option.label)
                                if selectedConditions.filter({ $0 != noConditionText }).isEmpty {
                                    selectedConditions = [noConditionText]
                                    metabolismFactor = 1.0
                                } else {
                                    recomputeFactor()
                                }
                            } else {
                                selectedConditions.remove(noConditionText)
                                selectedConditions.insert(option.label)
                                recomputeFactor()
                            }
                        }
                    } label: {
                        conditionRow(label: option.label, factor: option.factor, isActive: isActive)
                    }
                    .buttonStyle(.plain)
                }

                let noActive = activeConditions.isEmpty
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedConditions = [noConditionText]
                        metabolismFactor = 1.0
                    }
                } label: {
                    conditionRow(label: noConditionText, factor: 1.0, isActive: noActive)
                }
                .buttonStyle(.plain)
            }

            // Sleep section at bottom of Besonderheiten
            Divider().padding(.top, 4)

            Text(language == "de" ? "Schlaf" : "Sleep")
                .font(.poppins(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", sleepHours))
                        .font(.poppins(size: 38, weight: .bold))
                        .foregroundStyle(accentBlue)
                    Text(language == "de" ? "Stunden" : "hours")
                        .font(.poppins(size: 15, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                Slider(value: $sleepHours, in: 4...12, step: 0.5).tint(accentBlue)
                HStack {
                    Text("4h").font(.poppins(size: 11, weight: .regular)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("12h").font(.poppins(size: 11, weight: .regular)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(20)
        .background(GlassCardBackground(cornerRadius: 18))
    }

    private func conditionRow(label: String, factor: Double, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(isActive ? accentBlue : Theme.textSecondary.opacity(0.35))
            Text(label)
                .font(.poppins(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer()
            if isActive && factor != 1.0 {
                Text(String(format: "× %.2f", factor))
                    .font(.poppins(size: 11, weight: .semibold))
                    .foregroundStyle(accentBlue)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? accentBlue.opacity(0.09) : Theme.fieldFill.opacity(0.5))
        )
    }

    private func recomputeFactor() {
        let active = selectedConditions.filter { $0 != noConditionText }
        let factors = conditionOptions.filter { active.contains($0.label) }.map { $0.factor }
        metabolismFactor = factors.max(by: { abs($0 - 1.0) < abs($1 - 1.0) }) ?? 1.0
    }

    // MARK: Helpers

    private func pillToggle(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.poppins(size: 13, weight: .medium))
                .foregroundStyle(isActive ? .white : accentBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 10).fill(isActive ? accentBlue : accentBlue.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}
