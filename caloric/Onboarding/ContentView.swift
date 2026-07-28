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
    @State private var knowsBodyFat: Bool? = nil
    @State private var bodyFatText = ""
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
    @State private var showBMRInfo = false
    
    // Welcome Animations
    @State private var welcomeAnimScale: Double = 1.0
    @State private var welcomeAnimOpacity: Double = 1.0
    @State private var welcomeAnimOffset: CGFloat = 0
    @State private var welcomeHaloScale: Double = 1.0

    @State private var isNavigatingForward = true

    // Metabolism questionnaire
    @State private var metabolismAnswers = MetabolismAnswers()
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
        MeasurementParsing.weightKg(text: weightText, unit: weightUnit)
    }

    private var heightInCm: Double {
        MeasurementParsing.heightCm(text: heightText, unit: heightUnit)
    }

    private var bodyFatPercent: Double {
        MeasurementParsing.percent(bodyFatText)
    }

    private var leanBodyMass: Double {
        BMRCalculationService.leanBodyMass(weightKg: weightInKg, bodyFatPercent: bodyFatPercent)
    }
    private var baseBMR: Double { BMRCalculationService.baseBMR(leanBodyMass: leanBodyMass) }
    private var ageFactor: Double { BMRCalculationService.ageFactor(age: userAge) }
    private var ageAdjustedBMR: Double { baseBMR * ageFactor }

    private var hormoneFactor: Double { metabolismFactor }

    private var isFemale: Bool { selectedGender == t.female }

    private var computedMetabolismFactor: Double {
        metabolismAnswers.factor(t: t, isFemale: isFemale)
    }

    private var isReadyToCalculate: Bool {
        metabolismAnswers.isComplete(isFemale: isFemale)
    }

    private var hormoneAdjustedBMR: Double { ageAdjustedBMR * hormoneFactor }

    private var finalBMR: Double {
        BMRCalculationService.sleepWeighted(dailyBMR: hormoneAdjustedBMR, sleepHours: sleepHours)
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
        MeasurementParsing.feet(from: input)
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
        isNavigatingForward = step >= currentStep
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
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
            // Fortschrittsleiste
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
        .sheet(isPresented: $showBMRInfo) {
            bmrInfoSheet
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
        .background(CaloricBackground())
        #else
        .background(Color(.windowBackgroundColor))
        #endif
        .ignoresSafeArea()
        
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
                                    .font(.poppins(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .shadow(color: isReached ? accentBlue.opacity(0.3) : .clear, radius: 6, y: 3)
                        Text(t.stepLabels[index])
                            .font(.poppins(size: 11, weight: .regular))
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

    // MARK: - BMR Info Sheet
    private var bmrInfoSheet: some View {
        VStack(spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accentBlue)
                    .frame(width: 44, height: 44)
                    .background(accentBlue.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(selectedLanguage == "de" ? "Dein Grundumsatz" : "Your BMR")
                        .font(.poppins(size: 18, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(selectedLanguage == "de" ? "Hintergrund & Informationen" : "Background & Information")
                        .font(.poppins(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button { showBMRInfo = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.textSecondary.opacity(0.3))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            ScrollView {
                Text(t.resultInfo)
                    .font(.poppins(size: 15, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvas)
    }

    // MARK: - Seite 0: Willkommen

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()

            // Brand-Hero: Logo in weichem Caloric-Blau-Halo
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(colors: [Theme.accentSky.opacity(0.30), .clear],
                                       center: .center, startRadius: 0, endRadius: 110)
                    )
                    .frame(width: 200, height: 200)
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Theme.accentBlue.opacity(0.25), radius: 18, x: 0, y: 10)
            }
            .padding(.bottom, 4)

            Text(t.welcome)
                .font(.poppins(size: 30, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Text(t.welcomeSubtitle)
                .font(.poppins(size: 16, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
                .padding(.top, 10)
            Button(t.getStarted) {
                navigate(to: 1)
            }
            .buttonStyle(.caloricPrimary)
            .padding(.top, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    Text(selectedLanguage.uppercased()).font(.poppins(size: 14, weight: .medium))
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
                .font(.poppins(size: 28, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            hintBox(t.genderInfo)
            GenderInput(
                accentBlue: accentBlue,
                maleTitle: t.male,
                femaleTitle: t.female,
                selectedGender: $selectedGender,
                onSelect: { navigate(to: 2) }
            )
            .padding(.horizontal, 30)
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
                    .font(.poppins(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                hintBox(t.ageInfo)
                BirthDateInput(birthDate: $birthDate)
                Button(t.next) {
                    navigate(to: 3)
                }
                .font(.poppins(size: 18, weight: .medium))
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
                    .font(.poppins(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                hintBox(t.weightInfo)
                    .frame(minHeight: 115, alignment: .top)
                WeightInput(accentBlue: accentBlue,
                            weightText: $weightText,
                            weightUnit: $weightUnit)
                Button(t.next) {
                    navigate(to: 4)
                }
                .font(.poppins(size: 18, weight: .medium))
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
                    .font(.poppins(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                hintBox(t.heightInfo)
                    .frame(minHeight: 115, alignment: .top)
                HeightInput(accentBlue: accentBlue,
                            heightText: $heightText,
                            heightUnit: $heightUnit)
                Button(t.next) {
                    navigate(to: 5)
                }
                .font(.poppins(size: 18, weight: .medium))
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
                    .font(.poppins(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                hintBox(t.bodyFatInfo)

                BodyFatInput(
                    accentBlue: accentBlue,
                    t: t,
                    heightInCm: heightInCm,
                    selectedGender: selectedGender,
                    bodyFatText: $bodyFatText,
                    knowsBodyFat: $knowsBodyFat,
                    errorText: bodyFatError,
                    onCommit: { navigate(to: 6) }
                )
                .padding(.horizontal, 30)

                if knowsBodyFat == true {
                    Button(t.next) { navigate(to: 6) }
                        .font(.poppins(size: 18, weight: .medium))
                        .buttonStyle(.caloricPrimary)
                        .disabled(!isBodyFatValid)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Seite 6: Stoffwechsel

    private var metabolismPage: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 20)

                Text(t.metabolismQuestion)
                    .font(.poppins(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                hintBox(t.metabolismInfo)

                MetabolismQuestionnaire(
                    accentBlue: accentBlue,
                    t: t,
                    isFemale: isFemale,
                    answers: $metabolismAnswers
                )
                .padding(.horizontal, 30)

                Button(t.calculateBMR) {
                    metabolismAnswers.save()
                    metabolismFactor = computedMetabolismFactor
                    navigate(to: 7)
                }
                .font(.poppins(size: 18, weight: .medium))
                .buttonStyle(.caloricPrimary)
                .disabled(!isReadyToCalculate)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Seite 7: Ergebnis

    private var resultPage: some View {
        ZStack {
            CaloricBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 100)

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
                                .font(.poppins(size: 84, weight: .semibold))
                                .foregroundStyle(accentBlue)
                                .contentTransition(.numericText())

                            Text(t.resultUnit)
                                .font(.poppins(size: 17, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .scaleEffect(showResult ? 1 : 0.65)
                    .opacity(showResult ? 1 : 0)
                    .animation(.spring(response: 0.65, dampingFraction: 0.72).delay(0.15), value: showResult)

                    // Untertitel direkt unter der Zahl
                    Text(selectedLanguage == "de" ? "dein persönlicher Wert" : "your personal value")
                        .font(.poppins(size: 14, weight: .regular))
                        .foregroundStyle(.secondary.opacity(0.55))
                        .opacity(showResult ? 1 : 0)
                        .offset(y: showResult ? 0 : 8)
                        .animation(.easeOut(duration: 0.5).delay(0.5), value: showResult)

                    Spacer().frame(height: 40)

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

                    Spacer().frame(height: 32)

                    // Info-Button statt Text
                    Button {
                        showBMRInfo = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 16))
                            Text(selectedLanguage == "de" ? "Was bedeutet dieser Wert?" : "What does this value mean?")
                                .font(.poppins(size: 14, weight: .medium))
                        }
                        .foregroundStyle(accentBlue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(accentBlue.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .opacity(showCards ? 1 : 0)
                    .offset(y: showCards ? 0 : 16)
                    .animation(.easeOut(duration: 0.5).delay(0.5), value: showCards)

                    Spacer().frame(height: 40)

                    // Weiter-Button
                    Button(t.resultContinue) {
                        navigate(to: 8)
                    }
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
                .font(.poppins(size: 20, weight: .semibold))
                .foregroundStyle(accentBlue)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(unit)
                .font(.poppins(size: 11, weight: .regular))
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
                .font(.poppins(size: 26, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Spacer().frame(height: 8)

            Text(selectedLanguage == "de"
                 ? "Damit dein Profil nicht verloren geht."
                 : "So your profile doesn't get lost.")
                .font(.poppins(size: 15, weight: .regular))
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
                            .font(.poppins(size: 16, weight: .semibold))
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
                            .font(.poppins(size: 16, weight: .semibold))
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
                        .font(.poppins(size: 13, weight: .regular))
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
                                .font(.poppins(size: 16, weight: .semibold))
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
                    .font(.poppins(size: 16, weight: .regular))
            } else {
                TextField(placeholder, text: text)
                    .font(.poppins(size: 16, weight: .regular))
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
            userAge: userAge,
            noConditionText: t.noCondition,
            femaleText: t.female,
            accountUsername: $accountUsername,
            birthDate: $birthDate,
            selectedGender: $selectedGender,
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

    private func hintBox(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Good to Know")
                    .font(.poppins(size: 12, weight: .semibold))
                    .foregroundStyle(accentBlue)
                Text(text)
                    .font(.poppins(size: 13, weight: .regular))
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

}

#Preview {
    ContentView()
}
