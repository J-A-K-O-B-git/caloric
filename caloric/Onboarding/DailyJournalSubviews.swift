//
//  DailyJournalSubviews.swift
//  caloric
//

import SwiftUI

// MARK: - Menstruation Card
struct MenstruationCard: View {
    let language: String
    @Binding var menstruationActive: Bool?
    let accentBlue: Color
    /// False inside the check-in flow, where the slide already asks the
    /// question in full size — the card repeating it read as a stutter.
    var showsHeader: Bool = true
    /// Called when the answer is complete and nothing follows from it, so the
    /// check-in can move on without asking for a second tap on "Weiter".
    var onAnswered: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.pink.opacity(0.15)).frame(width: 32, height: 32)
                        Image(systemName: "drop.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.pink)
                    }
                    Text(language == "de" ? "Menstruation" : "Menstruation")
                        .font(.poppins(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
            }
            HStack(spacing: 10) {
                trackingToggle(label: language == "de" ? "Ja" : "Yes", isSelected: menstruationActive == true, tint: .pink) {
                    let answered = menstruationActive != true
                    withAnimation(.easeInOut(duration: 0.18)) {
                        menstruationActive = answered ? true : nil
                    }
                    if answered { onAnswered?() }
                }
                trackingToggle(label: language == "de" ? "Nein" : "No", isSelected: menstruationActive == false, tint: accentBlue) {
                    let answered = menstruationActive != false
                    withAnimation(.easeInOut(duration: 0.18)) {
                        menstruationActive = answered ? false : nil
                    }
                    if answered { onAnswered?() }
                }
            }
        }
        .padding(16)
        .glassCard(20)
    }

    private func trackingToggle(label: String, isSelected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.poppins(size: 15, weight: .semibold))
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

// MARK: - Sickness Card
struct SicknessCard: View {
    let language: String
    var showsHeader: Bool = true
    /// Only fired for "no". Answering "yes" opens the energy and fever
    /// questions on the same slide, and advancing would skip them.
    var onAnswered: (() -> Void)? = nil
    @Binding var sickToggle: Bool
    @Binding var sickEnergyLevel: TDEECalculationService.JournalInputs.SickEnergyLevel?
    @Binding var feverLevel: TDEECalculationService.JournalInputs.FeverLevel?
    let accentBlue: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
                Text(language == "de" ? "Bist du heute krank?" : "Are you feeling sick today?")
                    .font(.poppins(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            HStack(spacing: 10) {
                sickPill(label: language == "de" ? "Nein" : "No", isSelected: !sickToggle) {
                    onAnswered?()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                        sickToggle = false
                        sickEnergyLevel = nil
                        feverLevel = nil
                    }
                }
                sickPill(label: language == "de" ? "Ja" : "Yes", isSelected: sickToggle) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                        sickToggle = true
                    }
                }
            }

            if sickToggle {
                VStack(alignment: .leading, spacing: 16) {
                    Divider().background(Theme.divider)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(language == "de" ? "Wie fühlst du dich energetisch?" : "How is your energy level?")
                            .font(.poppins(size: 12, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                        HStack(spacing: 8) {
                            energyButton(label: language == "de" ? "Leicht angeschlagen" : "Slightly off", level: .mild)
                            energyButton(label: language == "de" ? "Platt / Bettruhe" : "Bedridden", level: .bedridden)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(language == "de" ? "Hast du Fieber?" : "Do you have a fever?")
                            .font(.poppins(size: 12, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                        HStack(spacing: 8) {
                            feverButton(label: language == "de" ? "Nein" : "None", sublabel: nil, level: .none, tint: accentBlue)
                            feverButton(label: language == "de" ? "Leicht" : "Low", sublabel: "< 38.5 °C", level: .low, tint: .orange)
                            feverButton(label: language == "de" ? "Hoch" : "High", sublabel: "> 38.5 °C", level: .high, tint: .red)
                        }
                    }

                    if feverLevel == .low || feverLevel == .high {
                        let isFeverHigh = feverLevel == .high
                        let tint: Color = isFeverHigh ? .red : .orange
                        let delta = isFeverHigh ? "+18 %" : "+10 %"
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(tint)
                            Text(language == "de" ? "Temporärer BMR-Faktor: \(delta)" : "Temporary BMR factor: \(delta)")
                                .font(.poppins(size: 12, weight: .regular))
                                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                            Spacer()
                            Text(isFeverHigh ? "×1.18" : "×1.10")
                                .font(.poppins(size: 13, weight: .semibold))
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .glassCard(20)
    }

    private func sickPill(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.poppins(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? .white : accentBlue)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? accentBlue : accentBlue.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(accentBlue.opacity(isSelected ? 0 : 0.2), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    private func energyButton(label: String, level: TDEECalculationService.JournalInputs.SickEnergyLevel) -> some View {
        let isSelected = sickEnergyLevel == level
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                sickEnergyLevel = isSelected ? nil : level
            }
        } label: {
            Text(label)
                .font(.poppins(size: 12, weight: .medium))
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

    private func feverButton(label: String, sublabel: String?, level: TDEECalculationService.JournalInputs.FeverLevel, tint: Color) -> some View {
        let isSelected = feverLevel == level
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                feverLevel = isSelected ? nil : level
            }
        } label: {
            VStack(spacing: 1) {
                Text(label)
                    .font(.poppins(size: 13, weight: .semibold))
                if let sub = sublabel {
                    Text(sub)
                        .font(.poppins(size: 10, weight: .regular))
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
}

// MARK: - Caffeine Card
struct CaffeineCard: View {
    let accentBlue: Color
    let language: String
    @Binding var caffeineText: String
    @Binding var caffeineInfoExpanded: Bool
    @Binding var showAddDrinkSheet: Bool
    @FocusState.Binding var caffeineFocused: Bool
    let store: JournalStore

    private let presets = [0, 80, 150, 200, 300]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header: title + expand chevron
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    caffeineInfoExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accentBlue.opacity(0.6))
                        .rotationEffect(.degrees(caffeineInfoExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            // Large -/value/+ display
            HStack {
                Button {
                    let v = max(0, (Int(caffeineText) ?? 0) - 10)
                    caffeineText = "\(v)"
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 48, height: 48)
                        .foregroundStyle(accentBlue)
                        .background(Circle().fill(accentBlue.opacity(0.12)))
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("0", text: $caffeineText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .focused($caffeineFocused)
                        .font(.poppins(size: 44, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .frame(width: 110)
                    Text("mg")
                        .font(.poppins(size: 18, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Button {
                    let v = (Int(caffeineText) ?? 0) + 10
                    caffeineText = "\(v)"
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 48, height: 48)
                        .foregroundStyle(accentBlue)
                        .background(Circle().fill(accentBlue.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            // Preset pills
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { mg in
                    let isSelected = (Int(caffeineText) ?? -1) == mg
                    Button {
                        caffeineText = "\(mg)"
                    } label: {
                        Text(mg == 0 ? (language == "de" ? "Keins" : "None") : "\(mg)")
                            .font(.poppins(size: 13, weight: .medium))
                            .foregroundStyle(isSelected ? .white : accentBlue)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(isSelected ? accentBlue : accentBlue.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            // Expandable: full drinks grid
            if caffeineInfoExpanded {
                VStack(spacing: 14) {
                    Divider().background(Theme.divider)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        caffeineQuickAdd(label: language == "de" ? "Espresso" : "Espresso", mg: 80)
                        caffeineQuickAdd(label: language == "de" ? "Kaffee" : "Coffee", mg: 90)
                        caffeineQuickAdd(label: language == "de" ? "Schwarztee" : "Black Tea", mg: 50)
                        caffeineQuickAdd(label: language == "de" ? "Grüntee" : "Green Tea", mg: 30)
                        caffeineQuickAdd(label: "Energy (250ml)", mg: 80)
                        caffeineQuickAdd(label: "Monster (500ml)", mg: 160)
                        caffeineQuickAdd(label: "Mate (330ml)", mg: 70)
                        caffeineQuickAdd(label: "Cola (330ml)", mg: 35)
                        caffeineQuickAdd(label: "Pre-Workout", mg: 200)

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
                        .font(.poppins(size: 13, weight: .medium))
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
        .glassCard(20)
    }

    private func caffeineQuickAdd(label: String, mg: Int, isCustom: Bool = false, id: UUID? = nil) -> some View {
        Button {
            let current = Int(caffeineText) ?? 0
            caffeineText = "\(current + mg)"
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.poppins(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("+\(mg) mg")
                        .font(.poppins(size: 10, weight: .regular))
                        .foregroundStyle(accentBlue)
                }
                Spacer()
                if isCustom, let drinkId = id {
                    Button {
                        store.removeCustomDrink(id: drinkId)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink.opacity(0.25))
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
}

// MARK: - Meal Description Chips

/// Describing a meal in words instead of grams.
///
/// Six chips over three axes, because that is exactly what the TEF formula
/// takes. Each axis is a three-way choice shown as two chips: tapping "viel"
/// and "wenig" are mutually exclusive, and neither tapped means normal — so
/// the common case costs nothing at all.
struct MealDescriptionPicker: View {
    let language: String
    let accentBlue: Color
    let description: MealEstimator.Description
    let estimate: MealEstimator.Macros
    let onChange: (MealEstimator.Description) -> Void

    private var de: Bool { language == "de" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            portionRow

            axisRow(title: de ? "Protein" : "Protein",
                    level: description.protein) { level in
                var d = description; d.protein = level; onChange(d)
            }
            axisRow(title: de ? "Kohlenhydrate" : "Carbs",
                    level: description.carbs) { level in
                var d = description; d.carbs = level; onChange(d)
            }
            axisRow(title: de ? "Fett" : "Fat",
                    level: description.fat) { level in
                var d = description; d.fat = level; onChange(d)
            }

            // The grams the words produce, shown live. Without this the picker
            // would be a black box asking for trust it has not earned.
            HStack(spacing: 14) {
                estimateChip(de ? "Protein" : "Protein", estimate.proteinG, Theme.segNEAT)
                estimateChip(de ? "KH" : "Carbs", estimate.carbsG, Theme.segEAT)
                estimateChip(de ? "Fett" : "Fat", estimate.fatG, Theme.segTEF)
                Spacer()
                Text("\(Int(estimate.kcal.rounded())) kcal")
                    .font(.poppins(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 2)
        }
    }

    private var portionRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(de ? "Portion" : "Portion")
                .font(.poppins(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                ForEach(MealEstimator.Portion.allCases, id: \.rawValue) { portion in
                    chip(label: portionLabel(portion),
                         isOn: description.portion == portion) {
                        var d = description; d.portion = portion; onChange(d)
                    }
                }
            }
        }
    }

    private func portionLabel(_ p: MealEstimator.Portion) -> String {
        switch p {
        case .small:  return de ? "klein" : "small"
        case .normal: return de ? "normal" : "normal"
        case .large:  return de ? "groß" : "large"
        }
    }

    private func axisRow(title: String,
                         level: MealEstimator.Level,
                         set: @escaping (MealEstimator.Level) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.poppins(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                chip(label: de ? "wenig" : "low", isOn: level == .low) {
                    // Tapping the active chip clears it: the way back to
                    // "normal" should not require hunting for a third button.
                    set(level == .low ? .normal : .low)
                }
                chip(label: de ? "viel" : "high", isOn: level == .high) {
                    set(level == .high ? .normal : .high)
                }
            }
        }
    }

    private func chip(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.poppins(size: 13, weight: isOn ? .semibold : .medium))
                .foregroundStyle(isOn ? .white : accentBlue)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(isOn ? accentBlue : accentBlue.opacity(0.12))
                        .overlay(Capsule().strokeBorder(
                            accentBlue.opacity(isOn ? 0 : 0.2), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }

    private func estimateChip(_ label: String, _ grams: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(Int(grams.rounded())) g")
                .font(.poppins(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityLabel("\(label) \(Int(grams.rounded())) Gramm")
    }
}

// MARK: - Macros Card
struct MacrosCard: View {
    let language: String
    let accentBlue: Color
    @Binding var selectedMeal: String?
    @Binding var aiInputText: String
    @Binding var aiIsLoading: Bool
    @Binding var aiErrorMessage: String?
    @Binding var proteinByMeal: [String: String]
    @Binding var carbsByMeal: [String: String]
    @Binding var fatByMeal: [String: String]
    let analyzeFoodWithAI: () -> Void
    let analyzeFoodFromPhoto: () -> Void
    let copyYesterdayBreakfast: () -> Void
    let isRecording: Bool
    let startRecording: () -> Void
    let stopRecording: () -> Void
    
    @FocusState.Binding var macroFocus: MacrosCardMacroField?
    /// Supplied by the journal, which owns both the stored words and the body
    /// figures needed to turn them into grams.
    let mealDescription: (MealEstimator.Meal) -> MealEstimator.Description
    let mealEstimate: (MealEstimator.Meal) -> MealEstimator.Macros
    let setMealDescription: (MealEstimator.Description, MealEstimator.Meal) -> Void

    @State private var entryMode: MacrosEntryMode? = nil
    /// Whether the precise routes are unfolded. Closed by default: the words
    /// above already produce an answer, and a row of buttons offered before
    /// anything has been said reads as four ways to do work.
    @State private var preciseOpen = false

    private enum MacrosEntryMode {
        case text, photo, voice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // No header. The slide already asks "Was hast du gegessen?", the
            // subtitle described a card that no longer starts with photos, and
            // the icon repeated the slide's own. Straight to the meals.
            HStack(spacing: 0) {
                mealTab(key: "breakfast", name: language == "de" ? "Frühstück"  : "Breakfast")
                mealTab(key: "lunch",     name: language == "de" ? "Mittagessen" : "Lunch")
                mealTab(key: "dinner",    name: language == "de" ? "Abendessen"  : "Dinner")
                mealTab(key: "snack",     name: language == "de" ? "Snack"       : "Snack")
            }
            .padding(4)
            .background(Theme.fieldFill)
            .clipShape(Capsule())

            // Kept, but moved down with the meal it copies into — it was only
            // ever in the header because that is where there was room.
            if selectedMeal == "breakfast" {
                Button(action: copyYesterdayBreakfast) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text(language == "de" ? "Vom Vortag übernehmen" : "Copy yesterday")
                    }
                    .font(.poppins(size: 12, weight: .medium))
                    .foregroundStyle(accentBlue)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            // Describing the meal is the way in. The AI routes are a step you
            // take when the words are not enough, not a menu you pick from
            // before you have said anything at all.
            if let meal = MealEstimator.Meal(rawValue: selectedMeal ?? "") {
                MealDescriptionPicker(
                    language: language,
                    accentBlue: accentBlue,
                    description: mealDescription(meal),
                    estimate: mealEstimate(meal),
                    onChange: { setMealDescription($0, meal) }
                )
            }

            Divider().overlay(Theme.divider)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    preciseOpen.toggle()
                    if !preciseOpen { entryMode = nil }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 12, weight: .semibold))
                    Text(language == "de" ? "Genauer erfassen" : "Log it precisely")
                        .font(.poppins(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(preciseOpen ? 180 : 0))
                }
                .foregroundStyle(accentBlue)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if preciseOpen {
                HStack(spacing: 12) {
                    entryModeButton(mode: .text,  icon: "keyboard", label: language == "de" ? "Tippen" : "Type")
                    entryModeButton(mode: .photo, icon: "camera.fill", label: language == "de" ? "Foto" : "Photo")
                    entryModeButton(mode: .voice, icon: "mic.fill", label: language == "de" ? "Sprechen" : "Voice")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let mode = entryMode, mode != .photo {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                entryMode = nil
                                aiInputText = ""
                                if isRecording { stopRecording() }
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(Theme.fieldFill)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        TextField(
                            mode == .text 
                                ? (language == "de" ? "Z.B. 3 Eier mit 50g Speck..." : "e.g. 3 eggs with 50g bacon...")
                                : (language == "de" ? "Spreche jetzt..." : "Listening..."),
                            text: $aiInputText, 
                            axis: .vertical
                        )
                        .lineLimit(1...3)
                        .font(.poppins(size: 13, weight: .regular))
                        .foregroundColor(Theme.textPrimary)
                        .disabled(aiIsLoading)

                        if mode == .voice {
                            Button {
                                if isRecording { stopRecording() }
                                else { startRecording() }
                            } label: {
                                ZStack {
                                    Circle().fill(isRecording ? .red.opacity(0.15) : accentBlue.opacity(0.1)).frame(width: 32, height: 32)
                                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(isRecording ? .red : accentBlue)
                                        .scaleEffect(isRecording ? 1.2 : 1.0)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        Button { analyzeFoodWithAI() } label: {
                            if aiIsLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                    .frame(width: 80, height: 32)
                                    .background(Capsule().fill(accentBlue))
                            } else {
                                Text(language == "de" ? "Schätzen" : "Estimate")
                                    .font(.poppins(size: 13, weight: .semibold))
                                    .foregroundStyle(aiInputText.isEmpty ? accentBlue.opacity(0.5) : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(aiInputText.isEmpty ? accentBlue.opacity(0.1) : accentBlue))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(aiInputText.isEmpty || aiIsLoading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.fieldFill)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(accentBlue.opacity(aiInputText.isEmpty ? 0.05 : 0.25), lineWidth: 1))

                    if let error = aiErrorMessage {
                        Text(error)
                            .font(.poppins(size: 11, weight: .regular))
                            .foregroundColor(.red)
                            .padding(.leading, 4)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Macro input fields for selected meal
            if let meal = selectedMeal {
                VStack(spacing: 12) {
                    macroInputField(label: "Protein", placeholder: "0",
                        text: Binding(get: { proteinByMeal[meal] ?? "" }, set: { proteinByMeal[meal] = $0 }),
                        focusValue: .protein(meal), tint: Theme.segNEAT)
                    HStack(spacing: 12) {
                        macroInputField(label: language == "de" ? "Kohlenhydrate" : "Carbs", placeholder: "0",
                            text: Binding(get: { carbsByMeal[meal] ?? "" }, set: { carbsByMeal[meal] = $0 }),
                            focusValue: .carbs(meal), tint: accentBlue)
                        macroInputField(label: language == "de" ? "Fett" : "Fat", placeholder: "0",
                            text: Binding(get: { fatByMeal[meal] ?? "" }, set: { fatByMeal[meal] = $0 }),
                            focusValue: .fat(meal), tint: .orange)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .glassCard(20)
    }

    private func macroInputField(label: String, placeholder: String,
                                  text: Binding<String>, focusValue: MacrosCardMacroField, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.poppins(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                TextField(placeholder, text: text)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .focused($macroFocus, equals: focusValue)
                    .font(.poppins(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                Text("g")
                    .font(.poppins(size: 12, weight: .medium))
                    .foregroundStyle(tint.opacity(0.6))
            }
            
            let val = Double(text.wrappedValue.replacingOccurrences(of: ",", with: ".")) ?? 0
            let ref: Double = label.contains("Protein") ? 150 : (label.contains("Fat") || label.contains("Fett") ? 80 : 300)
            InstrumentProgressBar(progress: min(1.0, val / ref), color: tint, height: 3, showScale: false)
                .padding(.top, 2)
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

    private func mealTab(key: String, name: String) -> some View {
        let isSelected = selectedMeal == key
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selectedMeal = key
            }
        } label: {
            Text(name)
                .font(.poppins(size: 11, weight: .medium))
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

    private func entryModeButton(mode: MacrosEntryMode, icon: String, label: String) -> some View {
        let isSelected = entryMode == mode
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                if mode == .photo {
                    analyzeFoodFromPhoto()
                } else {
                    if entryMode == mode {
                        entryMode = nil
                        aiInputText = ""
                        if isRecording { stopRecording() }
                    } else {
                        entryMode = mode
                        aiInputText = ""
                        if mode == .voice { startRecording() }
                    }
                }
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? accentBlue : accentBlue.opacity(0.08))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isSelected ? .white : accentBlue)
                }
                
                Text(label)
                    .font(.poppins(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

enum MacrosCardMacroField: Hashable {
    case protein(String), carbs(String), fat(String)
}
