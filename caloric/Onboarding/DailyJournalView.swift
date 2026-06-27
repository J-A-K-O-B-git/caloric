//
//  DailyJournalView.swift
//  caloric
//
//  Separater Tab für das tägliche Tracking (Menstruation, Krankheit, Makros)
//

import SwiftUI

struct DailyJournalView: View {

    // MARK: - Nested Types

    private typealias SickEnergyLevel = TDEECalculationService.JournalInputs.SickEnergyLevel
    private typealias FeverLevel      = TDEECalculationService.JournalInputs.FeverLevel

    // MARK: - Props

    let accentBlue: Color
    let language: String
    let selectedGender: String?
    let femaleText: String
    @Binding var selectedDate: Date

    // MARK: - State

    @State private var menstruationActive: Bool? = nil

    // Krankheit
    @State private var sickToggle      = false
    @State private var sickEnergyLevel: SickEnergyLevel? = nil
    @State private var feverLevel:      FeverLevel?       = nil

    // Koffein
    @State private var caffeineText: String = "0"
    @State private var caffeineInfoExpanded = false
    @FocusState private var caffeineFocused: Bool

    // Makros
    @State private var selectedMeal: String? = nil
    @State private var proteinByMeal:  [String: String] = ["breakfast": "", "lunch": "", "dinner": "", "daily": ""]
    @State private var carbsByMeal:    [String: String] = ["breakfast": "", "lunch": "", "dinner": "", "daily": ""]
    @State private var fatByMeal:      [String: String] = ["breakfast": "", "lunch": "", "dinner": "", "daily": ""]

    private enum MacroField: Hashable {
        case protein(String), carbs(String), fat(String)
    }
    @FocusState private var macroFocus: MacroField?

    @State private var showSavedBadge = false

    @Environment(JournalStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    private var macroKeyboardLabel: String {
        if caffeineFocused {
            let v = Int(caffeineText) ?? 0
            return v == 0 ? "– mg" : "\(v) mg Koffein"
        }
        switch macroFocus {
        case .protein(let m):
            let v = proteinByMeal[m] ?? ""
            return v.isEmpty ? "–" : "\(v) g Protein"
        case .carbs(let m):
            let v = carbsByMeal[m] ?? ""
            return v.isEmpty ? "–" : "\(v) g \(language == "de" ? "Kohlenhydrate" : "Carbs")"
        case .fat(let m):
            let v = fatByMeal[m] ?? ""
            return v.isEmpty ? "–" : "\(v) g \(language == "de" ? "Fett" : "Fat")"
        case nil: return ""
        }
    }

    // MARK: - Store Sync

    private func loadFromStore() {
        let e = store.entry(for: selectedDate)
        menstruationActive = e.menstruationActive
        sickToggle = e.sickActive
        sickEnergyLevel = e.sickEnergyLevel
        feverLevel = e.feverLevel == .none ? nil : e.feverLevel
        caffeineText = e.caffeineMg == 0 ? "0" : "\(Int(e.caffeineMg))"
        proteinByMeal = [
            "breakfast": e.proteinByMeal["breakfast"].map { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "lunch":     e.proteinByMeal["lunch"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "dinner":    e.proteinByMeal["dinner"].map    { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "daily":     e.proteinByMeal["daily"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? ""
        ]
        carbsByMeal = [
            "breakfast": e.carbsByMeal["breakfast"].map { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "lunch":     e.carbsByMeal["lunch"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "dinner":    e.carbsByMeal["dinner"].map    { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "daily":     e.carbsByMeal["daily"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? ""
        ]
        fatByMeal = [
            "breakfast": e.fatByMeal["breakfast"].map { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "lunch":     e.fatByMeal["lunch"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "dinner":    e.fatByMeal["dinner"].map    { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "daily":     e.fatByMeal["daily"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? ""
        ]
    }

    private var selectedDateString: String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.locale = Locale(identifier: language == "de" ? "de_DE" : "en_US")
        return f.string(from: selectedDate)
    }

    private var isFutureDate: Bool {
        selectedDate > Calendar.current.startOfDay(for: Date())
    }

    private var calendarDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (-4...4).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    private func dayDistanceFromToday(_ date: Date) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return abs(cal.dateComponents([.day], from: today, to: date).day ?? 0)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            ObsidianBackground()

            journalScrollView

            if showSavedBadge {
                VStack {
                    Spacer()
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(language == "de" ? "Änderungen gespeichert" : "Changes saved")
                            .font(.custom("PingFangSC-Semibold", size: 14, relativeTo: .callout))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(accentBlue)
                            .shadow(color: accentBlue.opacity(0.4), radius: 12, x: 0, y: 4)
                    )
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadFromStore() }
        .onChange(of: selectedDate) { _, _ in loadFromStore() }
        .onChange(of: menstruationActive) { _, v in
            store.update(for: selectedDate) { $0.menstruationActive = v }
        }
        .onChange(of: sickToggle) { _, v in
            store.update(for: selectedDate) { $0.sickActive = v }
        }
        .onChange(of: sickEnergyLevel) { _, v in
            store.update(for: selectedDate) { $0.sickEnergyLevel = v }
        }
        .onChange(of: feverLevel) { _, v in
            store.update(for: selectedDate) { $0.feverLevel = v ?? .none }
        }
        .onChange(of: caffeineText) { _, v in
            store.update(for: selectedDate) { $0.caffeineMg = Double(v) ?? 0 }
        }
        .onChange(of: proteinByMeal) { _, v in
            store.update(for: selectedDate) { e in
                e.proteinByMeal = v.compactMapValues {
                    Double($0.replacingOccurrences(of: ",", with: "."))
                }
            }
        }
        .onChange(of: carbsByMeal) { _, v in
            store.update(for: selectedDate) { e in
                e.carbsByMeal = v.compactMapValues {
                    Double($0.replacingOccurrences(of: ",", with: "."))
                }
            }
        }
        .onChange(of: fatByMeal) { _, v in
            store.update(for: selectedDate) { e in
                e.fatByMeal = v.compactMapValues {
                    Double($0.replacingOccurrences(of: ",", with: "."))
                }
            }
        }
    }

    // MARK: - Datumsleiste

    private var journalDatePicker: some View {
        HStack(spacing: 4) {
            ForEach(calendarDays, id: \.self) { date in
                journalDayChip(date: date)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    private func journalDayChip(date: Date) -> some View {
        let cal = Calendar.current
        let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
        let isToday = cal.isDateInToday(date)
        let dist = dayDistanceFromToday(date)
        let day = cal.component(.day, from: date)

        let chipW: CGFloat  = isToday ? 38 : isSelected ? 34 : 30
        let chipH: CGFloat  = isToday ? 46 : isSelected ? 42 : 36
        let dayFS: CGFloat  = isToday ? 15 : isSelected ? 13 : 11
        let weekFS: CGFloat = isToday ? 9 : 8
        let chipOpacity: Double = (isToday || isSelected) ? 1.0
                                 : max(0.35, 1.0 - Double(dist) * 0.2)

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                selectedDate = date
            }
        } label: {
            VStack(spacing: 2) {
                Text(journalWeekdayAbbrev(for: date))
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

    private func journalWeekdayAbbrev(for date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        if language == "de" {
            return ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"][weekday - 1]
        } else {
            return ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"][weekday - 1]
        }
    }

    // MARK: - Menstruation

    private var menstruationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(language == "de" ? "Menstruation" : "Menstruation")
                    .font(.custom("PingFangSC-Semibold", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(accentBlue)
                Spacer()
            }
            HStack(spacing: 10) {
                trackingToggle(label: language == "de" ? "Ja" : "Yes",
                               isSelected: menstruationActive == true) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        menstruationActive = menstruationActive == true ? nil : true
                    }
                }
                trackingToggle(label: language == "de" ? "Nein" : "No",
                               isSelected: menstruationActive == false) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        menstruationActive = menstruationActive == false ? nil : false
                    }
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    // MARK: - Krankheit

    private var sicknessCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Kopfzeile mit Toggle
            HStack(spacing: 10) {
                Text(language == "de" ? "Krankheit / Infekt" : "Illness / Infection")
                    .font(.custom("PingFangSC-Semibold", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(accentBlue)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { sickToggle },
                    set: { newVal in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                            sickToggle = newVal
                            if !newVal { sickEnergyLevel = nil; feverLevel = nil }
                        }
                    }
                ))
                .labelsHidden()
                .tint(accentBlue)
            }

            // Verschachtelte Abfragen (animiert einblenden)
            if sickToggle {
                VStack(alignment: .leading, spacing: 16) {

                    Divider()
                        .padding(.top, 12)

                    // Frage 1 – Energetischer Zustand
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            language == "de" ? "Wie fühlst du dich energetisch?" : "How is your energy level?",
                            systemImage: "bolt.fill"
                        )
                        .font(.custom("PingFangSC-Regular", size: 12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)

                        HStack(spacing: 8) {
                            energyButton(
                                label:      language == "de" ? "Leicht angeschlagen" : "Slightly off",
                                icon:       "figure.walk",
                                level:      .mild
                            )
                            energyButton(
                                label:      language == "de" ? "Platt / Bettruhe" : "Bedridden",
                                icon:       "bed.double.fill",
                                level:      .bedridden
                            )
                        }
                    }

                    // Frage 2 – Fieber
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            language == "de" ? "Hast du Fieber?" : "Do you have a fever?",
                            systemImage: "thermometer.medium"
                        )
                        .font(.custom("PingFangSC-Regular", size: 12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)

                        HStack(spacing: 6) {
                            feverButton(label: language == "de" ? "Nein"    : "None",
                                        sublabel: nil,
                                        level:    .none,
                                        tint:     accentBlue)
                            feverButton(label: language == "de" ? "Leicht"  : "Low",
                                        sublabel: "< 38.5 °C",
                                        level:    .low,
                                        tint:     .orange)
                            feverButton(label: language == "de" ? "Hoch"    : "High",
                                        sublabel: "> 38.5 °C",
                                        level:    .high,
                                        tint:     .red)
                        }
                    }

                    // Temporärer BMR-Hinweis bei Fieber
                    if feverLevel == .low || feverLevel == .high {
                        let isFeverHigh = feverLevel == .high
                        let tint: Color = isFeverHigh ? .red : .orange
                        let delta = isFeverHigh ? "+18 %" : "+10 %"

                        HStack(spacing: 6) {
                            Image(systemName: "thermometer.medium")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(tint)
                            Text(language == "de"
                                 ? "Temporärer BMR-Faktor: \(delta)"
                                 : "Temporary BMR factor: \(delta)")
                                .font(.custom("PingFangSC-Regular", size: 11, relativeTo: .caption2))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(isFeverHigh ? "×1.18" : "×1.10")
                                .font(.custom("PingFangSC-Semibold", size: 12, relativeTo: .caption))
                                .foregroundStyle(tint)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(tint.opacity(isDark ? 0.14 : 0.07))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(tint.opacity(isDark ? 0.28 : 0.18), lineWidth: 1)
                                )
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .leading)))
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(cardBackground)
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: sickToggle)
        .animation(.spring(response: 0.3,  dampingFraction: 0.82), value: feverLevel)
    }

    // Energielevel-Button (2 Optionen)
    private func energyButton(label: String, icon: String, level: SickEnergyLevel) -> some View {
        let isSelected = sickEnergyLevel == level
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                sickEnergyLevel = isSelected ? nil : level
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.custom("PingFangSC-Medium", size: 12, relativeTo: .caption))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .foregroundStyle(isSelected ? .white : accentBlue)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? accentBlue : accentBlue.opacity(isDark ? 0.18 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(accentBlue.opacity(isSelected ? 0 : (isDark ? 0.22 : 0.12)), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // Fieber-Button (3 Optionen, mit optionalem Sublabel + eigenem Farbton)
    private func feverButton(label: String, sublabel: String?, level: FeverLevel, tint: Color) -> some View {
        let isSelected = feverLevel == level
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                feverLevel = isSelected ? nil : level
            }
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.custom("PingFangSC-Semibold", size: 13, relativeTo: .callout))
                if let sub = sublabel {
                    Text(sub)
                        .font(.custom("PingFangSC-Regular", size: 10, relativeTo: .caption2))
                        .opacity(0.85)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? .white : tint)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? tint : tint.opacity(isDark ? 0.16 : 0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(tint.opacity(isSelected ? 0 : (isDark ? 0.28 : 0.15)), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Koffein

    private var caffeineCard: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Eingabe-Zeile
            HStack(spacing: 10) {
                Text(language == "de" ? "Koffein" : "Caffeine")
                    .font(.custom("PingFangSC-Semibold", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(accentBlue)
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        caffeineInfoExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accentBlue.opacity(0.6))
                        .rotationEffect(.degrees(caffeineInfoExpanded ? 180 : 0))
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: caffeineInfoExpanded)
                }
                .buttonStyle(.plain)
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        let v = max(0, (Int(caffeineText) ?? 0) - 10)
                        caffeineText = "\(v)"
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(accentBlue)
                            .background(Circle().fill(accentBlue.opacity(isDark ? 0.18 : 0.09)))
                    }
                    .buttonStyle(.plain)

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        TextField("0", text: $caffeineText)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .focused($caffeineFocused)
                            .font(.custom("PingFangSC-Semibold", size: 28, relativeTo: .title))
                            .foregroundStyle(accentBlue)
                            .multilineTextAlignment(.center)
                            .frame(width: 56)
                        Text("mg")
                            .font(.custom("PingFangSC-Regular", size: 12, relativeTo: .callout))
                            .foregroundStyle(accentBlue.opacity(0.55))
                    }

                    Button {
                        let v = (Int(caffeineText) ?? 0) + 10
                        caffeineText = "\(v)"
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(accentBlue)
                            .background(Circle().fill(accentBlue.opacity(isDark ? 0.18 : 0.09)))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Referenz-Tabelle (einklappbar)
            if caffeineInfoExpanded {
                VStack(spacing: 0) {
                    caffeineRef(emoji: "☕️", label: language == "de" ? "Espresso (einfach)" : "Espresso (single)", mg: "~80")
                    Divider().padding(.leading, 38).opacity(0.6)
                    caffeineRef(emoji: "☕️", label: language == "de" ? "Kaffee (gefiltert)" : "Filter coffee", mg: "~90")
                    Divider().padding(.leading, 38).opacity(0.6)
                    caffeineRef(emoji: "⚡️", label: language == "de" ? "Energy Drink (250ml)" : "Energy drink (250ml)", mg: "~80")
                    Divider().padding(.leading, 38).opacity(0.6)
                    caffeineRef(emoji: "🧃", label: "Mate (330ml)", mg: "~70")
                    Divider().padding(.leading, 38).opacity(0.6)
                    caffeineRef(emoji: "🧊", label: language == "de" ? "Pre-Workout (1 Scoop)" : "Pre-Workout (1 scoop)", mg: "200–300")
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentBlue.opacity(isDark ? 0.10 : 0.04))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(accentBlue.opacity(isDark ? 0.16 : 0.08), lineWidth: 1))
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private func caffeineRef(emoji: String, label: String, mg: String) -> some View {
        HStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 13))
                .frame(width: 22)
            Text(label)
                .font(.custom("PingFangSC-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Text("\(mg) mg")
                .font(.custom("PingFangSC-Semibold", size: 12, relativeTo: .caption))
                .foregroundStyle(.primary.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Makros

    private var macrosCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(language == "de" ? "Makros" : "Macros")
                    .font(.custom("PingFangSC-Semibold", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(accentBlue)
                Spacer()
            }

            HStack(spacing: 8) {
                mealTile(key: "breakfast",
                         name: language == "de" ? "Frühstück" : "Breakfast")
                mealTile(key: "lunch",
                         name: language == "de" ? "Mittag" : "Lunch")
                mealTile(key: "dinner",
                         name: language == "de" ? "Abend" : "Dinner")
            }
            mealTile(key: "daily",
                     name: language == "de" ? "Gesamt (ganzer Tag)" : "Total (full day)")

            if let meal = selectedMeal {
                HStack(spacing: 8) {
                    macroInputField(
                        emoji: "🥩", label: "Protein", placeholder: "0",
                        text: Binding(
                            get: { proteinByMeal[meal] ?? "" },
                            set: { proteinByMeal[meal] = $0 }
                        ),
                        focusValue: .protein(meal)
                    )
                    macroInputField(
                        emoji: "🌾",
                        label: language == "de" ? "KH" : "Carbs",
                        placeholder: "0",
                        text: Binding(
                            get: { carbsByMeal[meal] ?? "" },
                            set: { carbsByMeal[meal] = $0 }
                        ),
                        focusValue: .carbs(meal)
                    )
                    macroInputField(
                        emoji: "🫒",
                        label: language == "de" ? "Fett" : "Fat",
                        placeholder: "0",
                        text: Binding(
                            get: { fatByMeal[meal] ?? "" },
                            set: { fatByMeal[meal] = $0 }
                        ),
                        focusValue: .fat(meal)
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedMeal)
        .padding(14)
        .background(cardBackground)
    }

    // MARK: - Journal Scroll View

    private var journalScrollView: some View {
        ScrollView {
            VStack(spacing: 10) {
                Spacer().frame(height: 8)
                HStack {
                    Text("Daily Journal")
                        .font(.custom("PingFangSC-Semibold", size: 28, relativeTo: .title))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                journalDatePicker
                if isFutureDate {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(accentBlue.opacity(0.5))
                        Text(language == "de"
                             ? "Kein Eintrag für zukünftige Tage"
                             : "No entries for future dates")
                            .font(.custom("PingFangSC-Regular", size: 13, relativeTo: .callout))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .transition(.opacity)
                }
                cardsSection
                confirmButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Text(macroKeyboardLabel)
                    .font(.custom("PingFangSC-Semibold", size: 15, relativeTo: .callout))
                    .foregroundStyle(accentBlue)
                Spacer()
                Button(language == "de" ? "Fertig" : "Done") {
                    macroFocus = nil
                    caffeineFocused = false
                }
                .font(.custom("PingFangSC-Semibold", size: 15, relativeTo: .callout))
                .fontWeight(.semibold)
                .foregroundStyle(accentBlue)
            }
        }
    }

    // MARK: - Cards Section

    private var cardsSection: some View {
        VStack(spacing: 14) {
            if selectedGender == femaleText {
                menstruationCard
            }
            sicknessCard
            caffeineCard
            macrosCard
        }
        .padding(.horizontal, 20)
        .disabled(isFutureDate)
        .opacity(isFutureDate ? 0.45 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFutureDate)
    }

    // MARK: - Confirm Button

    private var confirmButton: some View {
        Button {
            macroFocus = nil
            caffeineFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { showSavedBadge = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.4)) { showSavedBadge = false }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text(language == "de" ? "Bestätigen" : "Confirm")
                    .font(.custom("PingFangSC-Semibold", size: 16, relativeTo: .subheadline))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accentBlue)
                    .shadow(color: accentBlue.opacity(0.35), radius: 8, x: 0, y: 3)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
        .disabled(isFutureDate)
        .opacity(isFutureDate ? 0.45 : 1.0)
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        GlassCardBackground(cornerRadius: 16)
    }

    private func mealTile(key: String, name: String) -> some View {
        let isSelected = selectedMeal == key
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                if isSelected { macroFocus = nil }
                selectedMeal = isSelected ? nil : key
            }
        } label: {
            VStack(spacing: 3) {
                Text(name)
                    .font(.custom("PingFangSC-Medium", size: 12, relativeTo: .caption))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? .white : accentBlue)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? accentBlue : accentBlue.opacity(isDark ? 0.18 : 0.08))
            )
        }
        .buttonStyle(.plain)
    }

    private func macroInputField(emoji: String, label: String, placeholder: String,
                                  text: Binding<String>, focusValue: MacroField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(emoji).font(.system(size: 13))
                Text(label)
                    .font(.custom("PingFangSC-Regular", size: 12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                TextField(placeholder, text: text)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .focused($macroFocus, equals: focusValue)
                    .font(.custom("PingFangSC-Semibold", size: 28, relativeTo: .title))
                    .foregroundStyle(accentBlue)
                Text("g")
                    .font(.custom("PingFangSC-Regular", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(accentBlue.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(accentBlue.opacity(isDark ? 0.13 : 0.06)))
    }

    private func trackingToggle(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.custom("PingFangSC-Medium", size: 14, relativeTo: .callout))
                .foregroundStyle(isSelected ? .white : accentBlue)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? accentBlue : accentBlue.opacity(isDark ? 0.18 : 0.08))
                )
        }
        .buttonStyle(.plain)
    }
}
