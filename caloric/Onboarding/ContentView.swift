//
//  ContentView.swift
//  caloric
//
//  Haupt-Onboarding: Navigation + State für alle Schritte
//

import SwiftUI
import SwiftData

struct ContentView: View {

    // --- State ---
    @State private var currentStep = 0
    @State private var selectedLanguage = "de"
    @State private var selectedGender: String? = nil
    @State private var birthDate = Date()
    @State private var weightText = "70"
    @State private var weightUnit = "kg"
    @State private var heightText = "170"
    @State private var heightUnit = "cm"
    @State private var weightKg: Int = 70
    @State private var weightLb: Int = 154
    @State private var heightCm: Int = 170
    @State private var heightFeet: Int = 5
    @State private var heightInches: Int = 9
    @State private var knowsBodyFat: Bool? = nil
    @State private var bodyFatText = ""
    @State private var showBodyFatHelp = false
    @State private var selectedConditions: Set<String> = []
    @State private var sleepHours: Double = 7
    @State private var activeField: String? = nil
    @State private var showResult = false
    @State private var animatedBMR: Double = 0
    @State private var showCards = false
    @State private var metabolismFactor: Double = 1.0
    @State private var accountUsername = ""
    @State private var accountEmail = ""
    @State private var accountPassword = ""
    @State private var showEmailSignUp = false
    @State private var showBFSavedBadge = false
    @State private var isNavigatingForward = true
    // Metabolism questionnaire
    @State private var thyroidCondition: String? = nil
    @State private var thyroidWellControlled: Bool? = nil
    @State private var selectedHypoSymptoms: Set<String> = []
    @State private var selectedHyperSymptoms: Set<String> = []
    @State private var hasPCOS: Bool? = nil
    @State private var pcosInsulinResistance: Bool? = nil
    @State private var selectedPCOSSymptoms: Set<String> = []
    private let accentBlue = Theme.accentBlue
    @State private var healthKit = HealthKitImportService()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    private var cardAlpha: Double { isDark ? 0.17 : 0.07 }
    private var controlAlpha: Double { isDark ? 0.22 : 0.10 }
    private var borderAlpha: Double { isDark ? 0.35 : 0.15 }
    private var dimAlpha: Double { isDark ? 0.42 : 0.25 }
    private var t: Translations { Translations(language: selectedLanguage) }

    private var topSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 50
    }

    private var userAge: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
    }

    // MARK: - BMR-Berechnung (Katch-McArdle)

    private var weightInKg: Double {
        let value = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return weightUnit == "kg" ? value : value * 0.453592
    }

    private var heightInCm: Double {
        if heightUnit == "cm" {
            return Double(heightText.replacingOccurrences(of: ",", with: ".")) ?? 0
        } else {
            guard let feet = parseFeetInput(heightText) else { return 0 }
            return feet * 30.48
        }
    }

    private var bodyFatPercent: Double {
        Double(bodyFatText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var leanBodyMass: Double { weightInKg * (1 - (bodyFatPercent / 100)) }
    private var baseBMR: Double { 370 + (21.6 * leanBodyMass) }
    private var ageFactor: Double { userAge > 30 ? 1 - (Double(userAge - 30) * 0.0015) : 1.0 }
    private var ageAdjustedBMR: Double { baseBMR * ageFactor }

    private var hormoneFactor: Double { metabolismFactor }

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
        guard selectedGender == t.female, hasPCOS == true else { return 1.0 }
        if pcosInsulinResistance == true { return 0.85 }
        let count = selectedPCOSSymptoms.count
        let hasBlocked = selectedPCOSSymptoms.contains(t.pcosSymptomBlocked)
        let hasCarbFatigue = selectedPCOSSymptoms.contains(t.pcosSymptomCarbFatigue)
        if count >= 3 || (hasBlocked && hasCarbFatigue) { return 0.85 }
        return 1.0
    }

    // Most extreme single factor — never multiply
    private var computedMetabolismFactor: Double {
        let tf = computedThyroidFactor
        let pf = computedPCOSFactor
        return abs(tf - 1.0) >= abs(pf - 1.0) ? tf : pf
    }

    private var isReadyToCalculate: Bool {
        guard thyroidCondition != nil else { return false }
        if thyroidCondition != "none" { guard thyroidWellControlled != nil else { return false } }
        if selectedGender == t.female {
            guard hasPCOS != nil else { return false }
            if hasPCOS == true { guard pcosInsulinResistance != nil else { return false } }
        }
        return true
    }

    private var hormoneAdjustedBMR: Double { ageAdjustedBMR * hormoneFactor }

    private var finalBMR: Double {
        let hourlyBMR = hormoneAdjustedBMR / 24
        let wakeHours = 24 - sleepHours
        return (sleepHours * hourlyBMR * 0.9) + (wakeHours * hourlyBMR * 1.0)
    }

    // MARK: - Validierung

    private var weightError: String? {
        guard let value = Double(weightText.replacingOccurrences(of: ",", with: ".")),
              !weightText.isEmpty else { return nil }
        let maxWeight: Double = weightUnit == "kg" ? 500 : 1102
        if value <= 0 { return t.weightErrorZero }
        if value > maxWeight { return t.weightErrorMax }
        return nil
    }

    private var isWeightValid: Bool {
        guard let value = Double(weightText.replacingOccurrences(of: ",", with: ".")),
              !weightText.isEmpty else { return false }
        let maxWeight: Double = weightUnit == "kg" ? 500 : 1102
        return value > 0 && value <= maxWeight
    }

    private var heightError: String? {
        guard !heightText.isEmpty else { return nil }
        if heightUnit == "cm" {
            guard let value = Double(heightText.replacingOccurrences(of: ",", with: ".")) else { return nil }
            if value <= 0 { return t.heightErrorZero }
            if value > 300 { return t.heightErrorMax }
        } else {
            let heightInFeet = parseFeetInput(heightText)
            guard let feet = heightInFeet else { return nil }
            if feet <= 0 { return t.heightErrorZero }
            if feet > 9.84 { return t.heightErrorMax }
        }
        return nil
    }

    private var isHeightValid: Bool {
        guard !heightText.isEmpty else { return false }
        if heightUnit == "cm" {
            guard let value = Double(heightText.replacingOccurrences(of: ",", with: ".")) else { return false }
            return value > 0 && value <= 300
        } else {
            guard let feet = parseFeetInput(heightText) else { return false }
            return feet > 0 && feet <= 9.84
        }
    }

    private var bodyFatError: String? {
        guard let value = Double(bodyFatText.replacingOccurrences(of: ",", with: ".")),
              !bodyFatText.isEmpty else { return nil }
        if value <= 0 { return t.bodyFatErrorZero }
        if value > 100 { return t.bodyFatErrorMax }
        return nil
    }

    private var isBodyFatValid: Bool {
        guard let value = Double(bodyFatText.replacingOccurrences(of: ",", with: ".")),
              !bodyFatText.isEmpty else { return false }
        return value > 0 && value <= 100
    }

    private func parseFeetInput(_ input: String) -> Double? {
        let cleaned = input.replacingOccurrences(of: "\"", with: "")
        if cleaned.contains("'") {
            let parts = cleaned.split(separator: "'")
            guard let feet = Double(parts[0]) else { return nil }
            if parts.count > 1, let inches = Double(parts[1]) {
                return feet + inches / 12.0
            }
            return feet
        }
        return Double(cleaned.replacingOccurrences(of: ",", with: "."))
    }

    // MARK: - Navigation helper

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isNavigatingForward ? .trailing : .leading)
                .combined(with: .opacity),
            removal: .move(edge: isNavigatingForward ? .leading : .trailing)
                .combined(with: .opacity)
        )
    }

    private func navigate(to step: Int) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
            isNavigatingForward = step >= currentStep
            currentStep = step
        }
    }

    @ViewBuilder
    private var currentPageView: some View {
        switch currentStep {
        case 0: welcomePage
        case 1: genderPage
        case 2: agePage
        case 3: weightPage
        case 4: heightPage
        case 5: bodyFatPage
        case 6: metabolismPage
        case 7: resultPage
        case 8: accountPage
        case 9: healthKitPage
        default: dashboardPage
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // Fortschrittsleiste (Schritte 1–6)
            if currentStep >= 1 && currentStep <= 6 {
                progressBar
            }

            // Seiteninhalt
            currentPageView
                #if os(iOS)
                .ignoresSafeArea(.keyboard)
                #endif
                .id(currentStep)
                .transition(pageTransition)
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                HStack(spacing: 4) {
                    if activeField == "weight" {
                        Text(weightText.isEmpty ? "–" : weightText).fontWeight(.bold)
                        Text(weightUnit)
                    } else if activeField == "height" {
                        Text(heightText.isEmpty ? "–" : heightText).fontWeight(.bold)
                        if heightUnit == "cm" { Text("cm") }
                    } else if activeField == "bodyFat" {
                        Text(bodyFatText.isEmpty ? "–" : bodyFatText).fontWeight(.bold)
                        Text("%")
                    }
                }
                .font(.system(size: 18))
                .foregroundStyle(accentBlue)
                .fixedSize()

                Spacer()

                Button(t.done) {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    activeField = nil
                }
                .foregroundStyle(accentBlue)
                .fontWeight(.semibold)
            }
        }
        .background(ObsidianBackground())
        #else
        .background(Color(.windowBackgroundColor))
        #endif
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .environment(healthKit)
        .onChange(of: currentStep) {
            activeField = nil
        }
    }

    // MARK: - Fortschrittsleiste

    private var progressBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
                let progressIndex = currentStep - 1
                let isDone = index < progressIndex
                let isCurrent = index == progressIndex
                let isReached = index <= progressIndex

                if index > 0 {
                    Capsule()
                        .fill(index <= progressIndex ? accentBlue : accentBlue.opacity(dimAlpha))
                        .frame(height: 2.5)
                        .animation(.easeInOut, value: currentStep)
                }
                Button {
                    if index <= progressIndex {
                        navigate(to: index + 1)
                    }
                } label: {
                    VStack(spacing: 7) {
                        ZStack {
                            Circle()
                                .fill(isReached ? accentBlue : accentBlue.opacity(dimAlpha))
                                .frame(width: 34, height: 34)
                            // dezenter Glow-Ring um den aktuellen Schritt
                            if isCurrent {
                                Circle()
                                    .strokeBorder(accentBlue.opacity(0.35), lineWidth: 2)
                                    .frame(width: 44, height: 44)
                            }
                            if isDone {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(index + 1)")
                                    .font(.custom("PingFangSC-Semibold", size: 15, relativeTo: .subheadline))
                                    .foregroundStyle(.white)
                            }
                        }
                        .shadow(color: isReached ? accentBlue.opacity(0.3) : .clear, radius: 6, y: 3)
                        Text(t.stepLabels[index])
                            .font(.custom("PingFangSC-Regular", size: 11, relativeTo: .caption2))
                            .foregroundStyle(isReached ? accentBlue : accentBlue.opacity(0.4))
                            .fixedSize()
                    }
                    .frame(width: 44)
                }
                .disabled(index > progressIndex)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, topSafeArea + 10)
        .padding(.bottom, 14)
    }

    // MARK: - Seite 0: Willkommen

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(t.welcome)
                .font(.custom("PingFangSC-Semibold", size: 25, relativeTo: .title))
                .foregroundStyle(Theme.textPrimary)
            Text(t.welcomeSubtitle)
                .font(.custom("PingFangSC-Regular", size: 16, relativeTo: .subheadline))
                .italic()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .padding(.top, 8)
            Button(t.getStarted) {
                navigate(to: 1)
            }
            .font(.custom("PingFangSC-Medium", size: 18, relativeTo: .headline))
            .buttonStyle(.caloricPrimary)
            .padding(.top, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: 35)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.leading, 20)
                .padding(.top, 90)
        }
        .overlay(alignment: .topTrailing) {
            Menu {
                Button { selectedLanguage = "de" } label: {
                    Label("Deutsch", systemImage: selectedLanguage == "de" ? "checkmark" : "")
                }
                Button { selectedLanguage = "en" } label: {
                    Label("English", systemImage: selectedLanguage == "en" ? "checkmark" : "")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe").font(.system(size: 14))
                    Text(selectedLanguage.uppercased()).font(.custom("PingFangSC-Medium", size: 14, relativeTo: .callout))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(accentBlue)
                .background(RoundedRectangle(cornerRadius: 10).fill(accentBlue.opacity(controlAlpha)))
            }
            .padding(.trailing, 20)
            .padding(.top, 90)
        }
    }

    // MARK: - Seite 1: Geschlecht

    private var genderPage: some View {
        VStack(spacing: 25) {
            Text(t.genderQuestion)
                .font(.custom("PingFangSC-Semibold", size: 28, relativeTo: .title))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            hintBox(t.genderInfo)
            VStack(spacing: 16) {
                genderButton(title: t.male, icon: "figure.stand")
                genderButton(title: t.female, icon: "figure.stand.dress")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Seite 2: Alter

    private var agePage: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 25) {
                Text(t.ageQuestion)
                    .font(.custom("PingFangSC-Semibold", size: 28, relativeTo: .title))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                hintBox(t.ageInfo)
                DatePicker("Geburtsdatum", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                    #if os(iOS)
                    .datePickerStyle(.wheel)
                    #endif
                    .labelsHidden()
                Button(t.next) {
                    navigate(to: 3)
                }
                .font(.custom("PingFangSC-Medium", size: 18, relativeTo: .headline))
                .buttonStyle(.caloricPrimary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal)
    }

    // MARK: - Seite 3: Gewicht

    private var weightPage: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 25) {
                Text(t.weightQuestion)
                    .font(.custom("PingFangSC-Semibold", size: 28, relativeTo: .title))
                    .foregroundStyle(Theme.textPrimary)
                hintBox(t.weightInfo)
                    .frame(minHeight: 115, alignment: .top)
                Picker("Einheit", selection: $weightUnit) {
                    Text("kg").tag("kg")
                    Text("lb").tag("lb")
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .onChange(of: weightUnit) {
                    if weightUnit == "lb" {
                        weightLb = max(44, min(661, Int((Double(weightKg) * 2.20462).rounded())))
                        weightText = "\(weightLb)"
                    } else {
                        weightKg = max(20, min(300, Int((Double(weightLb) / 2.20462).rounded())))
                        weightText = "\(weightKg)"
                    }
                }
                HStack(spacing: 4) {
                    Spacer()
                    if weightUnit == "kg" {
                        Picker("", selection: $weightKg) {
                            ForEach(20...300, id: \.self) { v in Text("\(v)").tag(v) }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 110, height: 150)
                        .clipped()
                        .onChange(of: weightKg) { weightText = "\(weightKg)" }
                    } else {
                        Picker("", selection: $weightLb) {
                            ForEach(44...661, id: \.self) { v in Text("\(v)").tag(v) }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 110, height: 150)
                        .clipped()
                        .onChange(of: weightLb) { weightText = "\(weightLb)" }
                    }
                    Text(weightUnit)
                        .font(.custom("PingFangSC-Semibold", size: 24, relativeTo: .title2))
                        .foregroundStyle(accentBlue)
                        .frame(width: 36, alignment: .leading)
                    Spacer()
                }
                Button(t.next) {
                    navigate(to: 4)
                }
                .font(.custom("PingFangSC-Medium", size: 18, relativeTo: .headline))
                .buttonStyle(.caloricPrimary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal)
    }

    // MARK: - Seite 4: Größe

    private var heightPage: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 25) {
                Text(t.heightQuestion)
                    .font(.custom("PingFangSC-Semibold", size: 28, relativeTo: .title))
                    .foregroundStyle(Theme.textPrimary)
                hintBox(t.heightInfo)
                    .frame(minHeight: 115, alignment: .top)
                Picker("Einheit", selection: $heightUnit) {
                    Text("cm").tag("cm")
                    Text("ft").tag("ft")
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .onChange(of: heightUnit) {
                    if heightUnit == "ft" {
                        let totalInches = Int((Double(heightCm) / 2.54).rounded())
                        heightFeet = max(3, min(8, totalInches / 12))
                        heightInches = max(0, min(11, totalInches % 12))
                        heightText = "\(heightFeet)'\(heightInches)\""
                    } else {
                        heightCm = max(100, min(230, Int((Double(heightFeet * 12 + heightInches) * 2.54).rounded())))
                        heightText = "\(heightCm)"
                    }
                }
                if heightUnit == "cm" {
                    HStack(spacing: 4) {
                        Spacer()
                        Picker("", selection: $heightCm) {
                            ForEach(100...230, id: \.self) { v in Text("\(v)").tag(v) }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 110, height: 150)
                        .clipped()
                        .onChange(of: heightCm) { heightText = "\(heightCm)" }
                        Text("cm")
                            .font(.custom("PingFangSC-Semibold", size: 24, relativeTo: .title2))
                            .foregroundStyle(accentBlue)
                            .frame(width: 44, alignment: .leading)
                        Spacer()
                    }
                } else {
                    HStack(spacing: 8) {
                        Spacer()
                        Picker("", selection: $heightFeet) {
                            ForEach(3...8, id: \.self) { v in Text("\(v)").tag(v) }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80, height: 150)
                        .clipped()
                        .onChange(of: heightFeet) { heightText = "\(heightFeet)'\(heightInches)\"" }
                        Text("ft")
                            .font(.custom("PingFangSC-Semibold", size: 22, relativeTo: .title2))
                            .foregroundStyle(accentBlue)
                        Picker("", selection: $heightInches) {
                            ForEach(0...11, id: \.self) { v in Text("\(v)").tag(v) }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80, height: 150)
                        .clipped()
                        .onChange(of: heightInches) { heightText = "\(heightFeet)'\(heightInches)\"" }
                        Text("in")
                            .font(.custom("PingFangSC-Semibold", size: 22, relativeTo: .title2))
                            .foregroundStyle(accentBlue)
                        Spacer()
                    }
                }
                Button(t.next) {
                    navigate(to: 5)
                }
                .font(.custom("PingFangSC-Medium", size: 18, relativeTo: .headline))
                .buttonStyle(.caloricPrimary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal)
    }

    // MARK: - Seite 5: Körperfettanteil

    private var bodyFatPage: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Text(t.bodyFatQuestion)
                    .font(.custom("PingFangSC-Semibold", size: 28, relativeTo: .title))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                hintBox(t.bodyFatInfo)

                VStack(spacing: 12) {
                    // Ja-Button — hebt sich ab wenn aktiv, Toggle bei erneutem Tap
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            if knowsBodyFat == true {
                                knowsBodyFat = nil
                                bodyFatText = ""
                            } else {
                                knowsBodyFat = true
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 24))
                            Text(t.yes).font(.custom("PingFangSC-Medium", size: 20, relativeTo: .title3))
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .foregroundStyle(knowsBodyFat == true ? .white : accentBlue)
                        .background(RoundedRectangle(cornerRadius: 16)
                            .fill(knowsBodyFat == true ? accentBlue : accentBlue.opacity(controlAlpha)))
                    }
                    .padding(.horizontal, 30)

                    // Inline-Eingabe klappt unter "Ja" auf
                    if knowsBodyFat == true {
                        VStack(spacing: 14) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                TextField("15", text: $bodyFatText, onEditingChanged: { editing in
                                    activeField = editing ? "bodyFat" : nil
                                })
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .font(.custom("PingFangSC-Semibold", size: 48, relativeTo: .largeTitle))
                                .foregroundStyle(accentBlue)
                                .multilineTextAlignment(.center)
                                .frame(width: 140)
                                Text("%")
                                    .font(.custom("PingFangSC-Regular", size: 22, relativeTo: .title2))
                                    .foregroundStyle(accentBlue.opacity(0.6))
                            }
                            if let error = bodyFatError {
                                Text(error)
                                    .font(.custom("PingFangSC-Regular", size: 13, relativeTo: .callout))
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                            }
                            Button(t.next) {
                                navigate(to: 6)
                            }
                            .font(.custom("PingFangSC-Medium", size: 18, relativeTo: .headline))
                            .buttonStyle(.caloricPrimary)
                            .disabled(!isBodyFatValid)
                        }
                        .padding(.vertical, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Nein-Button öffnet das Schätz-Sheet
                    Button {
                        withAnimation { showBodyFatHelp = true }
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 24))
                            Text(t.no).font(.custom("PingFangSC-Medium", size: 20, relativeTo: .title3))
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .foregroundStyle(accentBlue)
                        .background(RoundedRectangle(cornerRadius: 16).fill(accentBlue.opacity(controlAlpha)))
                    }
                    .padding(.horizontal, 30)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showBodyFatHelp) {
            BodyFatHelpView(accentBlue: accentBlue, t: t, heightInCm: heightInCm,
                            selectedGender: selectedGender, femaleText: t.female) { estimatedFat in
                bodyFatText = estimatedFat
                knowsBodyFat = true
                showBodyFatHelp = false
                navigate(to: 6)
            }
        }
    }

    // MARK: - Seite 6: Stoffwechsel

    private var metabolismPage: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 20)

                Text(t.metabolismQuestion)
                    .font(.custom("PingFangSC-Semibold", size: 24, relativeTo: .title2))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                hintBox(t.metabolismInfo)

                // Schilddrüse
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
                .padding(.horizontal, 30)

                // Therapiestatus
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
                    .padding(.horizontal, 30)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Symptome Schilddrüsenunterfunktion
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
                    .padding(.horizontal, 30)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Symptome Schilddrüsenüberfunktion
                if thyroidCondition == "hyper" && thyroidWellControlled == false {
                    questionnaireSectionCard(title: t.thyroidSymptomQuestion) {
                        VStack(spacing: 8) {
                            ForEach(
                                selectedGender == t.female
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
                    .padding(.horizontal, 30)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // PCOS (nur für Frauen)
                if selectedGender == t.female {
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
                    .padding(.horizontal, 30)
                }

                // Insulinresistenz
                if selectedGender == t.female && hasPCOS == true {
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
                    .padding(.horizontal, 30)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // PCOS Symptome
                if selectedGender == t.female && hasPCOS == true && pcosInsulinResistance == false {
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
                    .padding(.horizontal, 30)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button(t.calculateBMR) {
                    metabolismFactor = computedMetabolismFactor
                    navigate(to: 7)
                }
                .font(.custom("PingFangSC-Medium", size: 18, relativeTo: .headline))
                .buttonStyle(.caloricPrimary)
                .disabled(!isReadyToCalculate)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            .padding(.top, 10)
            .animation(.spring(response: 0.42, dampingFraction: 0.9), value: thyroidCondition)
            .animation(.spring(response: 0.42, dampingFraction: 0.9), value: thyroidWellControlled)
            .animation(.spring(response: 0.42, dampingFraction: 0.9), value: hasPCOS)
            .animation(.spring(response: 0.42, dampingFraction: 0.9), value: pcosInsulinResistance)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Seite 7: Ergebnis

    private var resultPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 60)

                Spacer().frame(height: 44)

                // Haupt-Zahl mit Glow-Hintergrund
                ZStack {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [accentBlue.opacity(0.18), accentBlue.opacity(0)],
                                center: .center,
                                startRadius: 20,
                                endRadius: 130
                            )
                        )
                        .frame(width: 280, height: 200)
                        .blur(radius: 8)
                        .scaleEffect(showResult ? 1 : 0.4)
                        .animation(.easeOut(duration: 1.0).delay(0.2), value: showResult)

                    VStack(spacing: 2) {
                        Text("\(Int(animatedBMR))")
                            .font(.custom("PingFangSC-Semibold", size: 84, relativeTo: .largeTitle))
                            .foregroundStyle(accentBlue)
                            .contentTransition(.numericText())

                        Text(t.resultUnit)
                            .font(.custom("PingFangSC-Regular", size: 17, relativeTo: .headline))
                            .foregroundStyle(.secondary)
                    }
                }
                .scaleEffect(showResult ? 1 : 0.65)
                .opacity(showResult ? 1 : 0)
                .animation(.spring(response: 0.65, dampingFraction: 0.72).delay(0.15), value: showResult)

                // Untertitel direkt unter der Zahl
                Text(selectedLanguage == "de" ? "dein persönlicher Wert" : "your personal value")
                    .font(.custom("PingFangSC-Regular", size: 14, relativeTo: .callout))
                    .foregroundStyle(.secondary.opacity(0.55))
                    .opacity(showResult ? 1 : 0)
                    .offset(y: showResult ? 0 : 8)
                    .animation(.easeOut(duration: 0.5).delay(0.5), value: showResult)

                Spacer().frame(height: 36)

                // Drei Kennzahlen-Karten
                HStack(spacing: 10) {
                    metricCard(
                        icon: "clock.fill",
                        value: String(format: "%.0f", finalBMR / 24),
                        unit: "kcal/h",
                        delay: 0.0
                    )
                    metricCard(
                        icon: "calendar",
                        value: String(format: "%.0f", finalBMR * 7),
                        unit: selectedLanguage == "de" ? "kcal/Woche" : "kcal/week",
                        delay: 0.12
                    )
                    metricCard(
                        icon: "figure.strengthtraining.traditional",
                        value: String(format: "%.1f", leanBodyMass),
                        unit: selectedLanguage == "de" ? "kg Muskelmasse" : "kg lean mass",
                        delay: 0.24
                    )
                }
                .padding(.horizontal, 20)

                Spacer().frame(height: 28)

                // Info-Text
                Text(t.resultInfo)
                    .font(.custom("PingFangSC-Regular", size: 13, relativeTo: .callout))
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(showCards ? 1 : 0)
                    .offset(y: showCards ? 0 : 16)
                    .animation(.easeOut(duration: 0.5).delay(0.5), value: showCards)

                Spacer().frame(height: 36)

                // Weiter-Button
                Button(t.resultContinue) {
                    navigate(to: 8)
                }
                .font(.custom("PingFangSC-Medium", size: 18, relativeTo: .headline))
                .buttonStyle(.caloricPrimary)
                .opacity(showCards ? 1 : 0)
                .offset(y: showCards ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.6), value: showCards)

                // Neu-berechnen
                Button {
                    showResult = false
                    animatedBMR = 0
                    showCards = false
                    navigate(to: 1)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .font(.system(size: 16))
                .foregroundStyle(accentBlue.opacity(0.5))
                .padding(.top, 16)
                .padding(.bottom, 50)
                .opacity(showCards ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.65), value: showCards)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) { showResult = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                withAnimation { showCards = true }
            }
            let target = finalBMR
            let steps = 80
            let stepDuration = 1.2 / Double(steps)
            for i in 0...steps {
                DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) {
                    withAnimation(.easeOut) { animatedBMR = target * Double(i) / Double(steps) }
                }
            }
        }
    }

    private func metricCard(icon: String, value: String, unit: String, delay: Double) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(accentBlue)
            Text(value)
                .font(.custom("PingFangSC-Semibold", size: 20, relativeTo: .title3))
                .foregroundStyle(accentBlue)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(unit)
                .font(.custom("PingFangSC-Regular", size: 11, relativeTo: .caption2))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(GlassCardBackground(cornerRadius: 16))
        .opacity(showCards ? 1 : 0)
        .offset(y: showCards ? 0 : 20)
        .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.35 + delay), value: showCards)
    }



    // MARK: - Seite 8: Konto erstellen

    private var accountPage: some View {
        VStack(spacing: 0) {
            Spacer()

            // Lock-Icon
            ZStack {
                Circle()
                    .fill(accentBlue.opacity(isDark ? 0.18 : 0.08))
                    .frame(width: 76, height: 76)
                Circle()
                    .strokeBorder(accentBlue.opacity(isDark ? 0.30 : 0.15), lineWidth: 1)
                    .frame(width: 76, height: 76)
                Image(systemName: "lock.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(accentBlue)
            }
            .padding(.bottom, 22)

            Text(selectedLanguage == "de" ? "Konto erstellen" : "Create account")
                .font(.custom("PingFangSC-Semibold", size: 26, relativeTo: .title))
                .foregroundStyle(Theme.textPrimary)

            Spacer().frame(height: 8)

            Text(selectedLanguage == "de"
                 ? "Damit dein Profil nicht verloren geht."
                 : "So your profile doesn't get lost.")
                .font(.custom("PingFangSC-Regular", size: 15, relativeTo: .subheadline))
                .italic()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)

            Spacer().frame(height: 36)

            VStack(spacing: 12) {
                // Apple
                Button { } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 17, weight: .semibold))
                        Text(selectedLanguage == "de" ? "Mit Apple anmelden" : "Sign in with Apple")
                            .font(.custom("PingFangSC-Semibold", size: 16, relativeTo: .subheadline))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(isDark ? Color.black : Color.white)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isDark ? Color.white : Color.black)
                    )
                }
                .padding(.horizontal, 30)

                // Google
                Button { } label: {
                    HStack(spacing: 12) {
                        Text("G")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                        Text(selectedLanguage == "de" ? "Mit Google anmelden" : "Sign in with Google")
                            .font(.custom("PingFangSC-Semibold", size: 16, relativeTo: .subheadline))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(accentBlue.opacity(isDark ? 0.14 : 0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(accentBlue.opacity(isDark ? 0.28 : 0.14), lineWidth: 1)
                            )
                    )
                }
                .padding(.horizontal, 30)

                // Divider
                HStack(spacing: 10) {
                    Rectangle().fill(.secondary.opacity(0.22)).frame(height: 1)
                    Text(selectedLanguage == "de" ? "oderrrrrr" : "orrrrrrrr")
                        .font(.custom("PingFangSC-Regular", size: 13, relativeTo: .callout))
                        .foregroundStyle(.secondary)
                    Rectangle().fill(.secondary.opacity(0.22)).frame(height: 1)
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 2)

                if showEmailSignUp {
                    VStack(spacing: 10) {
                        accountField(icon: "person", placeholder: selectedLanguage == "de" ? "Benutzername" : "Username", text: $accountUsername, secure: false)
                        accountField(icon: "envelope", placeholder: "E-Mail", text: $accountEmail, secure: false)
                        accountField(icon: "lock", placeholder: selectedLanguage == "de" ? "Passwort" : "Password", text: $accountPassword, secure: true)

                        Button(selectedLanguage == "de" ? "Speichern & starten" : "Save & start") {
                            navigate(to: 9)
                        }
                        .buttonStyle(.caloricPrimary(fullWidth: true))
                        .disabled(accountEmail.isEmpty || accountPassword.isEmpty || accountUsername.isEmpty)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 30)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) { showEmailSignUp = true }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 17))
                            Text(selectedLanguage == "de" ? "Mit E-Mail anmelden" : "Sign up with Email")
                                .font(.custom("PingFangSC-Semibold", size: 16, relativeTo: .subheadline))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .foregroundStyle(accentBlue)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(accentBlue.opacity(isDark ? 0.14 : 0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(accentBlue.opacity(isDark ? 0.28 : 0.14), lineWidth: 1)
                                )
                        )
                    }
                    .padding(.horizontal, 30)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func accountField(icon: String, placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(accentBlue.opacity(0.6))
                .frame(width: 22)
            if secure {
                SecureField(placeholder, text: text)
                    .font(.custom("PingFangSC-Regular", size: 16, relativeTo: .subheadline))
            } else {
                TextField(placeholder, text: text)
                    .font(.custom("PingFangSC-Regular", size: 16, relativeTo: .subheadline))
                    #if os(iOS)
                    .autocapitalization(.none)
                    #endif
                    .disableAutocorrection(true)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(GlassCardBackground(cornerRadius: 14))
    }

    // MARK: - Seite 9: Apple Health

    private var healthKitPage: some View {
        HealthKitPermissionView(
            accentBlue: accentBlue,
            language:   selectedLanguage,
            topPadding: topSafeArea,
            onComplete: {
                saveUserProfile()
                navigate(to: 10)
            }
        )
    }

    private func saveUserProfile() {
        let profile = UserProfile(
            name:               accountUsername,
            birthDate:          birthDate,
            geschlecht:         selectedGender ?? "",
            weightText:         weightText,
            weightUnit:         weightUnit,
            heightText:         heightText,
            heightUnit:         heightUnit,
            bodyFatText:        bodyFatText,
            weissKfa:           knowsBodyFat == true,
            sprache:            selectedLanguage,
            stoffwechselFaktor: metabolismFactor,
            schlafStunden:      sleepHours,
            selectedConditions: Array(selectedConditions)
        )
        profile.isOnboardingCompleted = true
        modelContext.insert(profile)
        try? modelContext.save()
    }

    // MARK: - Seite 10: Dashboard

    private var dashboardPage: some View {
        MainTabView(
            accentBlue: accentBlue,
            language: selectedLanguage,
            finalBMR: finalBMR,
            sleepHoursValue: sleepHours,
            leanBodyMass: leanBodyMass,
            userAge: userAge,
            selectedGender: selectedGender,
            noConditionText: t.noCondition,
            femaleText: t.female,
            accountUsername: $accountUsername,
            birthDate: $birthDate,
            weightText: $weightText,
            weightUnit: $weightUnit,
            heightText: $heightText,
            heightUnit: $heightUnit,
            bodyFatText: $bodyFatText,
            knowsBodyFat: $knowsBodyFat,
            sleepHours: $sleepHours,
            selectedConditions: $selectedConditions,
            metabolismFactor: $metabolismFactor
        )
    }

    // MARK: - Hilfsfunktionen (Views)

    private func genderButton(title: String, icon: String) -> some View {
        Button {
            selectedGender = title
            navigate(to: 2)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 32))
                Text(title).font(.custom("PingFangSC-Medium", size: 20, relativeTo: .title3))
                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .foregroundStyle(selectedGender == title ? .white : accentBlue)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selectedGender == title ? accentBlue : accentBlue.opacity(controlAlpha))
            )
        }
        .padding(.horizontal, 30)
    }

    private func hintBox(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Good to Know")
                    .font(.custom("PingFangSC-Semibold", size: 12, relativeTo: .caption))
                    .foregroundStyle(accentBlue)
                Text(text)
                    .font(.custom("PingFangSC-Regular", size: 13, relativeTo: .callout))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(GlassCardBackground(cornerRadius: 14, tint: accentBlue, tintStrength: 0.05))
        .padding(.horizontal, 30)
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
        .background(GlassCardBackground(cornerRadius: 14))
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

#Preview {
    ContentView()
}
