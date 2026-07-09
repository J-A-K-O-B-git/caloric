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
    let cardBackground: AnyView
    let trackingToggle: (String, Bool, Color, @escaping () -> Void) -> AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.pink.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: "drop.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.pink)
                }
                Text(language == "de" ? "Menstruation" : "Menstruation")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            HStack(spacing: 10) {
                trackingToggle(language == "de" ? "Ja" : "Yes", menstruationActive == true, .pink) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        menstruationActive = menstruationActive == true ? nil : true
                    }
                }
                trackingToggle(language == "de" ? "Nein" : "No", menstruationActive == false, accentBlue) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        menstruationActive = menstruationActive == false ? nil : false
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }
}

// MARK: - Sickness Card
struct SicknessCard: View {
    let language: String
    @Binding var sickToggle: Bool
    @Binding var sickEnergyLevel: TDEECalculationService.JournalInputs.SickEnergyLevel?
    @Binding var feverLevel: TDEECalculationService.JournalInputs.FeverLevel?
    let accentBlue: Color
    let cardBackground: AnyView
    let energyButton: (String, TDEECalculationService.JournalInputs.SickEnergyLevel) -> AnyView
    let feverButton: (String, String?, TDEECalculationService.JournalInputs.FeverLevel, Color) -> AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(language == "de" ? "Krankheit" : "Illness")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Toggle("", isOn: $sickToggle.animation(.spring(response: 0.38, dampingFraction: 0.85)))
                    .labelsHidden()
                    .tint(accentBlue)
                    .onChange(of: sickToggle) { _, newVal in
                        if !newVal { sickEnergyLevel = nil; feverLevel = nil }
                    }
            }

            if sickToggle {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                        .background(Theme.divider)
                        .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(language == "de" ? "Wie fühlst du dich energetisch?" : "How is your energy level?")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)

                        HStack(spacing: 8) {
                            energyButton(language == "de" ? "Leicht angeschlagen" : "Slightly off", .mild)
                            energyButton(language == "de" ? "Platt / Bettruhe" : "Bedridden", .bedridden)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(language == "de" ? "Hast du Fieber?" : "Do you have a fever?")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)

                        HStack(spacing: 8) {
                            feverButton(language == "de" ? "Nein" : "None", nil, .none, accentBlue)
                            feverButton(language == "de" ? "Leicht" : "Low", "< 38.5 °C", .low, .orange)
                            feverButton(language == "de" ? "Hoch" : "High", "> 38.5 °C", .high, .red)
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
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                            Spacer()
                            Text(isFeverHigh ? "×1.18" : "×1.10")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
    let cardBackground: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
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
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(accentBlue)
                            .multilineTextAlignment(.center)
                            .frame(width: 60)
                        Text("mg")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
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

            if caffeineInfoExpanded {
                VStack(spacing: 16) {
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
                        .font(.system(size: 13, weight: .medium, design: .rounded))
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
    }

    private func caffeineQuickAdd(label: String, mg: Int, isCustom: Bool = false, id: UUID? = nil) -> some View {
        Button {
            let current = Int(caffeineText) ?? 0
            caffeineText = "\(current + mg)"
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("+\(mg) mg")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
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
    let macroInputField: (String, String, Binding<String>, AnyHashable, Color) -> AnyView
    let cardBackground: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.segTEF.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.segTEF)
                }
                Text(language == "de" ? "Makros" : "Macros")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }

            HStack(spacing: 0) {
                mealTab(key: "breakfast", name: language == "de" ? "Frühstück" : "Breakfast")
                mealTab(key: "lunch",     name: language == "de" ? "Mittag" : "Lunch")
                mealTab(key: "dinner",    name: language == "de" ? "Abend" : "Dinner")
                mealTab(key: "daily",     name: language == "de" ? "Gesamt" : "Total")
            }
            .padding(4)
            .background(Theme.fieldFill)
            .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField(language == "de" ? "Z.B. 3 Eier mit 50g Speck..." : "e.g. 3 eggs with 50g bacon...", text: $aiInputText, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(Theme.textPrimary)
                        .disabled(aiIsLoading)
                    
                    Button { analyzeFoodWithAI() } label: {
                        ZStack {
                            Circle().fill(aiInputText.isEmpty ? accentBlue.opacity(0.1) : accentBlue).frame(width: 32, height: 32)
                            if aiIsLoading {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkles").font(.system(size: 14, weight: .bold)).foregroundStyle(aiInputText.isEmpty ? accentBlue.opacity(0.4) : .white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(aiInputText.isEmpty || aiIsLoading)
                }
                .padding(.horizontal, 12).padding(.vertical, 8).background(Theme.fieldFill).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accentBlue.opacity(aiInputText.isEmpty ? 0.05 : 0.25), lineWidth: 1))
                
                if let error = aiErrorMessage {
                    Text(error).font(.system(size: 11, weight: .regular, design: .rounded)).foregroundColor(.red).padding(.leading, 4)
                }
            }
            .padding(.vertical, 4)

            if let meal = selectedMeal {
                if meal == "daily" {
                    totalSummaryView
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    VStack(spacing: 12) {
                        macroInputField("Protein", "0", Binding(get: { proteinByMeal[meal] ?? "" }, set: { proteinByMeal[meal] = $0 }), AnyHashable(MacrosCardMacroField.protein(meal)), Theme.segNEAT)
                        HStack(spacing: 12) {
                            macroInputField(language == "de" ? "Kohlenhydrate" : "Carbs", "0", Binding(get: { carbsByMeal[meal] ?? "" }, set: { carbsByMeal[meal] = $0 }), AnyHashable(MacrosCardMacroField.carbs(meal)), accentBlue)
                            macroInputField(language == "de" ? "Fett" : "Fat", "0", Binding(get: { fatByMeal[meal] ?? "" }, set: { fatByMeal[meal] = $0 }), AnyHashable(MacrosCardMacroField.fat(meal)), .orange)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func mealSum(_ dict: [String: String]) -> Int {
        ["breakfast", "lunch", "dinner"].compactMap { Int(dict[$0] ?? "") }.reduce(0, +)
    }

    private var totalSummaryView: some View {
        let totalProtein = mealSum(proteinByMeal)
        let totalCarbs   = mealSum(carbsByMeal)
        let totalFat     = mealSum(fatByMeal)
        let totalKcal    = totalProtein * 4 + totalCarbs * 4 + totalFat * 9

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                macroTotalPill(label: "Protein", value: totalProtein, unit: "g", color: Theme.segNEAT)
                macroTotalPill(label: language == "de" ? "Kohlenhydrate" : "Carbs", value: totalCarbs, unit: "g", color: accentBlue)
                macroTotalPill(label: language == "de" ? "Fett" : "Fat", value: totalFat, unit: "g", color: .orange)
            }
            HStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange.opacity(0.8))
                Text("\(totalKcal) kcal \(language == "de" ? "gesamt" : "total")")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.fieldFill)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.divider, lineWidth: 1))
            )
        }
    }

    private func macroTotalPill(label: String, value: Int, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                Text(unit)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(color.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color.opacity(0.15), lineWidth: 1))
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
                .font(.system(size: 12, weight: .medium, design: .rounded))
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
}

enum MacrosCardMacroField: Hashable {
    case protein(String), carbs(String), fat(String)
}
