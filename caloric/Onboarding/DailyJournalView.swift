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
    @State private var showAddDrinkSheet = false
    @State private var newDrinkName = ""
    @State private var newDrinkCaffeine = ""
    @FocusState private var caffeineFocused: Bool

    // Makros
    @State private var selectedMeal: String? = "breakfast" // Default to breakfast for better UX
    @State private var proteinByMeal:  [String: String] = ["breakfast": "", "lunch": "", "dinner": "", "daily": ""]
    @State private var carbsByMeal:    [String: String] = ["breakfast": "", "lunch": "", "dinner": "", "daily": ""]
    @State private var fatByMeal:      [String: String] = ["breakfast": "", "lunch": "", "dinner": "", "daily": ""]

    private enum MacroField: Hashable {
        case protein(String), carbs(String), fat(String)
    }
    @FocusState private var macroFocus: MacroField?

    @State private var showSavedBadge = false
    @State private var showCalendarPicker = false

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

    private var isFutureDate: Bool {
        selectedDate > Calendar.current.startOfDay(for: Date())
    }

    private var calendarDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (-90...7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
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

            // Sticky Bottom Footer for Confirm Button
            VStack {
                Spacer()
                ZStack {
                    // Glass background for the sticky footer
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Theme.obsidian.opacity(0.4))
                        .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .bottom))
                        .ignoresSafeArea()
                        .frame(height: 180)

                    confirmButton
                        .padding(.bottom, 74)
                }
            }
            .ignoresSafeArea(edges: .bottom)

            if showSavedBadge {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(language == "de" ? "Bestätigt" : "confirmed")
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
                    .padding(.top, (UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?.windows.first?.safeAreaInsets.top ?? 50) + 6)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadFromStore() }
        .onChange(of: selectedDate) { _, _ in loadFromStore() }
        .sheet(isPresented: $showCalendarPicker) {
            calendarPickerSheet
        }
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

    // MARK: - Datumsleiste (Scrolling alignment with Dashboard)

    private var journalDatePicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(calendarDays, id: \.self) { date in
                        journalDayChip(date: date)
                            .id(date)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            .onAppear {
                proxy.scrollTo(selectedDate, anchor: .center)
            }
            .onChange(of: selectedDate) { _, date in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    proxy.scrollTo(date, anchor: .center)
                }
            }
        }
    }

    private func journalDayChip(date: Date) -> some View {
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.pink.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: "drop.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.pink)
                }
                Text(language == "de" ? "Menstruation" : "Menstruation")
                    .font(.custom("PingFangSC-Semibold", size: 16, relativeTo: .subheadline))
                    .foregroundStyle(.white)
                Spacer()
            }
            HStack(spacing: 10) {
                trackingToggle(label: language == "de" ? "Ja" : "Yes",
                               isSelected: menstruationActive == true,
                               tint: .pink) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        menstruationActive = menstruationActive == true ? nil : true
                    }
                }
                trackingToggle(label: language == "de" ? "Nein" : "No",
                               isSelected: menstruationActive == false,
                               tint: accentBlue) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        menstruationActive = menstruationActive == false ? nil : false
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - Krankheit

    private var sicknessCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Kopfzeile mit Toggle
            HStack(spacing: 12) {
                Text(language == "de" ? "Krankheit" : "Illness")
                    .font(.custom("PingFangSC-Semibold", size: 16, relativeTo: .subheadline))
                    .foregroundStyle(.white)
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
                        .background(Color.white.opacity(0.1))
                        .padding(.top, 12)

                    // Frage 1 – Energetischer Zustand
                    VStack(alignment: .leading, spacing: 10) {
                        Text(language == "de" ? "Wie fühlst du dich energetisch?" : "How is your energy level?")
                            .font(.custom("PingFangSC-Regular", size: 12, relativeTo: .caption))
                            .foregroundStyle(Theme.textSecondary)

                        HStack(spacing: 8) {
                            energyButton(
                                label:      language == "de" ? "Leicht angeschlagen" : "Slightly off",
                                icon:       "",
                                level:      .mild
                            )
                            energyButton(
                                label:      language == "de" ? "Platt / Bettruhe" : "Bedridden",
                                icon:       "",
                                level:      .bedridden
                            )
                        }
                    }

                    // Frage 2 – Fieber
                    VStack(alignment: .leading, spacing: 10) {
                        Text(language == "de" ? "Hast du Fieber?" : "Do you have a fever?")
                            .font(.custom("PingFangSC-Regular", size: 12, relativeTo: .caption))
                            .foregroundStyle(Theme.textSecondary)

                        HStack(spacing: 8) {
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

                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(tint)
                            Text(language == "de"
                                 ? "Temporärer BMR-Faktor: \(delta)"
                                 : "Temporary BMR factor: \(delta)")
                                .font(.custom("PingFangSC-Regular", size: 12, relativeTo: .caption))
                                .foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            Text(isFeverHigh ? "×1.18" : "×1.10")
                                .font(.custom("PingFangSC-Semibold", size: 13, relativeTo: .caption))
                                .foregroundStyle(tint)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(tint.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(tint.opacity(0.25), lineWidth: 1)
                                )
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .leading)))
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
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
            Text(label)
                .font(.custom("PingFangSC-Medium", size: 12, relativeTo: .caption))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .foregroundStyle(isSelected ? .white : accentBlue)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? accentBlue : accentBlue.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(accentBlue.opacity(isSelected ? 0 : 0.2), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // Fieber-Button (3 Optionen)
    private func feverButton(label: String, sublabel: String?, level: FeverLevel, tint: Color) -> some View {
        let isSelected = feverLevel == level
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                feverLevel = isSelected ? nil : level
            }
        } label: {
            VStack(spacing: 1) {
                Text(label)
                    .font(.custom("PingFangSC-Semibold", size: 13, relativeTo: .callout))
                if let sub = sublabel {
                    Text(sub)
                        .font(.custom("PingFangSC-Regular", size: 10, relativeTo: .caption2))
                        .opacity(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundStyle(isSelected ? .white : tint)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? tint : tint.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(tint.opacity(isSelected ? 0 : 0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Koffein (Enhanced with Quick-Add Grid)

    private var caffeineCard: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Eingabe-Zeile
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        caffeineInfoExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Theme.segCaf.opacity(0.15)).frame(width: 32, height: 32)
                            Image(systemName: "cup.and.heat.waves.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.segCaf)
                        }
                        Text(language == "de" ? "Koffein" : "Caffeine")
                            .font(.custom("PingFangSC-Semibold", size: 16, relativeTo: .subheadline))
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accentBlue.opacity(0.6))
                            .rotationEffect(.degrees(caffeineInfoExpanded ? 180 : 0))
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button {
                        let v = max(0, (Int(caffeineText) ?? 0) - 10)
                        caffeineText = "\(v)"
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(accentBlue)
                            .background(Circle().fill(accentBlue.opacity(0.12)))
                    }
                    .buttonStyle(.plain)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        TextField("0", text: $caffeineText)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .focused($caffeineFocused)
                            .font(.custom("PingFangSC-Semibold", size: 28, relativeTo: .title))
                            .foregroundStyle(accentBlue)
                            .multilineTextAlignment(.center)
                            .frame(width: 60)
                        Text("mg")
                            .font(.custom("PingFangSC-Regular", size: 14, relativeTo: .callout))
                            .foregroundStyle(accentBlue.opacity(0.6))
                    }

                    Button {
                        let v = (Int(caffeineText) ?? 0) + 10
                        caffeineText = "\(v)"
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(accentBlue)
                            .background(Circle().fill(accentBlue.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Quick-Add Interactive Grid (Collapsible)
            if caffeineInfoExpanded {
                VStack(spacing: 16) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        // Built-in Presets
                        caffeineQuickAdd(label: language == "de" ? "Espresso" : "Espresso", mg: 80)
                        caffeineQuickAdd(label: language == "de" ? "Kaffee" : "Coffee", mg: 90)
                        caffeineQuickAdd(label: language == "de" ? "Schwarztee" : "Black Tea", mg: 50)
                        caffeineQuickAdd(label: language == "de" ? "Grüntee" : "Green Tea", mg: 30)
                        caffeineQuickAdd(label: "Energy (250ml)", mg: 80)
                        caffeineQuickAdd(label: "Monster (500ml)", mg: 160)
                        caffeineQuickAdd(label: "Mate (330ml)", mg: 70)
                        caffeineQuickAdd(label: "Cola (330ml)", mg: 35)
                        caffeineQuickAdd(label: "Pre-Workout", mg: 200)
                        
                        // User Custom Drinks
                        ForEach(store.customDrinks) { drink in
                            caffeineQuickAdd(label: drink.name, mg: drink.caffeineMg, isCustom: true, id: drink.id)
                        }
                    }
                    
                    Button {
                        showAddDrinkSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text(language == "de" ? "Eigenes Getränk erstellen" : "Create custom drink")
                        }
                        .font(.custom("PingFangSC-Medium", size: 13))
                        .foregroundStyle(accentBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(accentBlue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(cardBackground)
        .sheet(isPresented: $showAddDrinkSheet) {
            addDrinkSheet
        }
    }

    private func caffeineQuickAdd(label: String, mg: Int, isCustom: Bool = false, id: UUID? = nil) -> some View {
        Button {
            let current = Int(caffeineText) ?? 0
            caffeineText = "\(current + mg)"
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.custom("PingFangSC-Medium", size: 12, relativeTo: .caption))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("+\(mg) mg")
                        .font(.custom("PingFangSC-Regular", size: 10, relativeTo: .caption2))
                        .foregroundStyle(accentBlue)
                }
                Spacer()
                if isCustom, let drinkId = id {
                    Button {
                        store.removeCustomDrink(id: drinkId)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(accentBlue.opacity(0.6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accentBlue.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accentBlue.opacity(0.15), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private var addDrinkSheet: some View {
        NavigationStack {
            ZStack {
                ObsidianBackground()
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(language == "de" ? "Name des Getränks" : "Drink Name")
                            .font(.custom("PingFangSC-Medium", size: 14))
                            .foregroundStyle(Theme.textSecondary)
                        TextField(language == "de" ? "z.B. Mein Special Tee" : "e.g. My Special Tea", text: $newDrinkName)
                            .font(.custom("PingFangSC-Semibold", size: 18))
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(language == "de" ? "Koffeingehalt (mg)" : "Caffeine content (mg)")
                            .font(.custom("PingFangSC-Medium", size: 14))
                            .foregroundStyle(Theme.textSecondary)
                        TextField("0", text: $newDrinkCaffeine)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .font(.custom("PingFangSC-Semibold", size: 18))
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Spacer()
                    
                    Button {
                        if let mg = Int(newDrinkCaffeine), !newDrinkName.isEmpty {
                            store.addCustomDrink(name: newDrinkName, caffeineMg: mg)
                            newDrinkName = ""
                            newDrinkCaffeine = ""
                            showAddDrinkSheet = false
                        }
                    } label: {
                        Text(language == "de" ? "Getränk speichern" : "Save Drink")
                            .font(.custom("PingFangSC-Semibold", size: 16))
                            .foregroundStyle(accentBlue)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(accentBlue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accentBlue.opacity(0.2), lineWidth: 1))
                    }
                    .disabled(newDrinkName.isEmpty || Int(newDrinkCaffeine) == nil)
                    .opacity(newDrinkName.isEmpty || Int(newDrinkCaffeine) == nil ? 0.5 : 1.0)
                }
                .padding(24)
            }
            .navigationTitle(language == "de" ? "Neues Getränk" : "New Drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language == "de" ? "Abbrechen" : "Cancel") {
                        showAddDrinkSheet = false
                    }
                    .foregroundStyle(accentBlue)
                }
            }
        }
    }

    // MARK: - Makros (Refined Tabs)

    private var macrosCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.segTEF.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.segTEF)
                }
                Text(language == "de" ? "Makros" : "Macros")
                    .font(.custom("PingFangSC-Semibold", size: 16, relativeTo: .subheadline))
                    .foregroundStyle(.white)
                Spacer()
            }

            // Sleek Tabbed Meal Selector
            HStack(spacing: 0) {
                mealTab(key: "breakfast", name: language == "de" ? "Frühstück" : "Breakfast")
                mealTab(key: "lunch",     name: language == "de" ? "Mittag" : "Lunch")
                mealTab(key: "dinner",    name: language == "de" ? "Abend" : "Dinner")
                mealTab(key: "daily",     name: language == "de" ? "Gesamt" : "Total")
            }
            .padding(4)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())

            if let meal = selectedMeal {
                VStack(spacing: 12) {
                    macroInputField(
                        label: "Protein", placeholder: "0",
                        text: Binding(
                            get: { proteinByMeal[meal] ?? "" },
                            set: { proteinByMeal[meal] = $0 }
                        ),
                        focusValue: .protein(meal),
                        tint: Theme.segNEAT
                    )
                    HStack(spacing: 12) {
                        macroInputField(
                            label: language == "de" ? "Kohlenhydrate" : "Carbs",
                            placeholder: "0",
                            text: Binding(
                                get: { carbsByMeal[meal] ?? "" },
                                set: { carbsByMeal[meal] = $0 }
                            ),
                            focusValue: .carbs(meal),
                            tint: accentBlue
                        )
                        macroInputField(
                            label: language == "de" ? "Fett" : "Fat",
                            placeholder: "0",
                            text: Binding(
                                get: { fatByMeal[meal] ?? "" },
                                set: { fatByMeal[meal] = $0 }
                            ),
                            focusValue: .fat(meal),
                            tint: .orange
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedMeal)
        .padding(16)
        .background(cardBackground)
    }

    private func mealTab(key: String, name: String) -> some View {
        let isSelected = selectedMeal == key
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selectedMeal = key
            }
        } label: {
            Text(name)
                .font(.custom("PingFangSC-Medium", size: 12, relativeTo: .caption))
                .foregroundStyle(isSelected ? .white : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        if isSelected {
                            Capsule()
                                .fill(accentBlue)
                                .shadow(color: accentBlue.opacity(0.3), radius: 4, x: 0, y: 2)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Journal Scroll View

    private var journalScrollView: some View {
        ScrollView {
            VStack(spacing: 14) {
                Spacer().frame(height: 12)
                
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Daily Journal")
                            .font(.custom("PingFangSC-Semibold", size: 32, relativeTo: .largeTitle))
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
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 4)
                
                journalDatePicker
                
                if isFutureDate {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(accentBlue.opacity(0.6))
                        Text(language == "de"
                             ? "Einträge für zukünftige Tage gesperrt"
                             : "Entries locked for future dates")
                            .font(.custom("PingFangSC-Medium", size: 14, relativeTo: .callout))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .glassCard(16)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
                }
                
                cardsSection
                
                Spacer().frame(height: 140) // Spacing for sticky footer
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
                .foregroundStyle(accentBlue)
            }
        }
    }

    private var selectedDateString: String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.locale = Locale(identifier: language == "de" ? "de_DE" : "en_US")
        return f.string(from: selectedDate)
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
                            Image(systemName: "arrow.uturn.backward.circle.fill")
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
                    Button(language == "de" ? "Fertig" : "Done") {
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

    // MARK: - Cards Section

    private var cardsSection: some View {
        VStack(spacing: 16) {
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

    // MARK: - Confirm Button (Sticky)

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
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text(language == "de" ? "Tag bestätigen" : "Confirm Day")
                    .font(.custom("PingFangSC-Semibold", size: 17, relativeTo: .headline))
            }
            .foregroundStyle(accentBlue)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accentBlue.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(accentBlue.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .disabled(isFutureDate)
        .opacity(isFutureDate ? 0.45 : 1.0)
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        GlassCardBackground(cornerRadius: 20)
    }

    private func macroInputField(label: String, placeholder: String,
                                  text: Binding<String>, focusValue: MacroField, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.custom("PingFangSC-Medium", size: 11, relativeTo: .caption2))
                .foregroundStyle(Theme.textSecondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                TextField(placeholder, text: text)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .focused($macroFocus, equals: focusValue)
                    .font(.custom("PingFangSC-Semibold", size: 20, relativeTo: .body))
                    .foregroundStyle(tint)
                Text("g")
                    .font(.custom("PingFangSC-Medium", size: 12, relativeTo: .caption))
                    .foregroundStyle(tint.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.15), lineWidth: 1))
        )
    }

    private func trackingToggle(label: String, isSelected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.custom("PingFangSC-Semibold", size: 15, relativeTo: .callout))
                .foregroundStyle(isSelected ? .white : tint)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? tint : tint.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(tint.opacity(isSelected ? 0 : 0.2), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
}
