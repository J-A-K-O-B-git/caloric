//
//  ProfileInputs.swift
//  caloric
//
//  The input controls for the profile fields, shared by the onboarding pages
//  and the edit sheets under "Meine Daten".
//
//  They used to exist twice: the onboarding had wheel pickers, unit switching
//  and the body-fat estimator, while the edit sheet had a simplified rebuild
//  that had drifted — its ft/in case rendered the raw string with a "Logic for
//  ft/in input if needed" note instead of an input. One implementation each, so
//  editing a value later works exactly like entering it the first time.
//

import SwiftUI

// MARK: - Shared chrome

struct ProfileHintBox: View {
    let text: String
    let accentBlue: Color

    var body: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(GlassCardBackground(cornerRadius: 14, tint: accentBlue, tintStrength: 0.05))
    }
}

private struct ControlAlpha {
    static func value(for scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.22 : 0.10
    }
}

// MARK: - Gender

struct GenderInput: View {
    let accentBlue: Color
    let maleTitle: String
    let femaleTitle: String
    @Binding var selectedGender: String?
    /// Onboarding advances to the next page on pick; the edit sheet does not.
    var onSelect: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            button(title: maleTitle, icon: "figure.stand")
            button(title: femaleTitle, icon: "figure.stand.dress")
        }
    }

    private func button(title: String, icon: String) -> some View {
        Button {
            selectedGender = title
            onSelect?()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 32))
                Text(title).font(.poppins(size: 20, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .foregroundStyle(selectedGender == title ? .white : accentBlue)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selectedGender == title
                          ? accentBlue
                          : accentBlue.opacity(ControlAlpha.value(for: colorScheme)))
            )
        }
    }
}

// MARK: - Birth date

struct BirthDateInput: View {
    @Binding var birthDate: Date

    var body: some View {
        DatePicker("", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
            #if os(iOS)
            .datePickerStyle(.wheel)
            #endif
            .labelsHidden()
    }
}

// MARK: - Weight

struct WeightInput: View {
    let accentBlue: Color
    @Binding var weightText: String
    @Binding var weightUnit: String

    /// Wheel positions are derived from the text binding, so the control can be
    /// dropped anywhere the two strings live without extra plumbing.
    @State private var kg: Int = 70
    @State private var lb: Int = 154

    var body: some View {
        VStack(spacing: 25) {
            Picker("Einheit", selection: $weightUnit) {
                Text("kg").tag("kg")
                Text("lb").tag("lb")
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .onChange(of: weightUnit) {
                if weightUnit == "lb" {
                    lb = clampLb(Int((Double(kg) * 2.20462).rounded()))
                    weightText = "\(lb)"
                } else {
                    kg = clampKg(Int((Double(lb) / 2.20462).rounded()))
                    weightText = "\(kg)"
                }
            }

            HStack(spacing: 4) {
                Spacer()
                if weightUnit == "kg" {
                    Picker("", selection: $kg) {
                        ForEach(20...300, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 110, height: 150)
                    .clipped()
                    .onChange(of: kg) { weightText = "\(kg)" }
                } else {
                    Picker("", selection: $lb) {
                        ForEach(44...661, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 110, height: 150)
                    .clipped()
                    .onChange(of: lb) { weightText = "\(lb)" }
                }
                Text(weightUnit)
                    .font(.poppins(size: 24, weight: .semibold))
                    .foregroundStyle(accentBlue)
                    .frame(width: 36, alignment: .leading)
                Spacer()
            }
        }
        .onAppear(perform: seedFromText)
    }

    private func seedFromText() {
        let value = Int(MeasurementParsing.decimal(weightText)?.rounded() ?? 0)
        if weightUnit == "kg" {
            kg = clampKg(value == 0 ? 70 : value)
            lb = clampLb(Int((Double(kg) * 2.20462).rounded()))
        } else {
            lb = clampLb(value == 0 ? 154 : value)
            kg = clampKg(Int((Double(lb) / 2.20462).rounded()))
        }
    }

    private func clampKg(_ v: Int) -> Int { max(20, min(300, v)) }
    private func clampLb(_ v: Int) -> Int { max(44, min(661, v)) }
}

// MARK: - Height

struct HeightInput: View {
    let accentBlue: Color
    @Binding var heightText: String
    @Binding var heightUnit: String

    @State private var cm: Int = 170
    @State private var feet: Int = 5
    @State private var inches: Int = 9

    var body: some View {
        VStack(spacing: 25) {
            Picker("Einheit", selection: $heightUnit) {
                Text("cm").tag("cm")
                Text("ft").tag("ft")
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .onChange(of: heightUnit) {
                if heightUnit == "ft" {
                    let totalInches = Int((Double(cm) / 2.54).rounded())
                    feet = max(3, min(8, totalInches / 12))
                    inches = max(0, min(11, totalInches % 12))
                    writeFeet()
                } else {
                    cm = clampCm(Int((Double(feet * 12 + inches) * 2.54).rounded()))
                    heightText = "\(cm)"
                }
            }

            if heightUnit == "cm" {
                HStack(spacing: 4) {
                    Spacer()
                    Picker("", selection: $cm) {
                        ForEach(100...230, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 110, height: 150)
                    .clipped()
                    .onChange(of: cm) { heightText = "\(cm)" }
                    Text("cm")
                        .font(.poppins(size: 24, weight: .semibold))
                        .foregroundStyle(accentBlue)
                        .frame(width: 44, alignment: .leading)
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    Spacer()
                    Picker("", selection: $feet) {
                        ForEach(3...8, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 150)
                    .clipped()
                    .onChange(of: feet) { writeFeet() }
                    Text("ft")
                        .font(.poppins(size: 22, weight: .semibold))
                        .foregroundStyle(accentBlue)
                    Picker("", selection: $inches) {
                        ForEach(0...11, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 150)
                    .clipped()
                    .onChange(of: inches) { writeFeet() }
                    Text("in")
                        .font(.poppins(size: 22, weight: .semibold))
                        .foregroundStyle(accentBlue)
                    Spacer()
                }
            }
        }
        .onAppear(perform: seedFromText)
    }

    private func writeFeet() {
        heightText = "\(feet)'\(inches)\""
    }

    private func seedFromText() {
        if heightUnit == "cm" {
            let value = Int(MeasurementParsing.decimal(heightText)?.rounded() ?? 0)
            cm = clampCm(value == 0 ? 170 : value)
            let totalInches = Int((Double(cm) / 2.54).rounded())
            feet = max(3, min(8, totalInches / 12))
            inches = max(0, min(11, totalInches % 12))
        } else {
            let totalFeet = MeasurementParsing.feet(from: heightText) ?? 5.75
            let totalInches = Int((totalFeet * 12).rounded())
            feet = max(3, min(8, totalInches / 12))
            inches = max(0, min(11, totalInches % 12))
            cm = clampCm(Int((Double(feet * 12 + inches) * 2.54).rounded()))
        }
    }

    private func clampCm(_ v: Int) -> Int { max(100, min(230, v)) }
}

// MARK: - Body fat

struct BodyFatInput: View {
    let accentBlue: Color
    let t: Translations
    let heightInCm: Double
    let selectedGender: String?
    @Binding var bodyFatText: String
    @Binding var knowsBodyFat: Bool?
    /// Validation message rendered under the field; nil hides it.
    var errorText: String? = nil
    /// Called after a value was entered or estimated — onboarding advances here.
    var onCommit: (() -> Void)? = nil

    @State private var showHelp = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
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
                choiceLabel(icon: "checkmark.circle.fill", title: t.yes, filled: knowsBodyFat == true)
            }

            if knowsBodyFat == true {
                VStack(spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        TextField("15", text: $bodyFatText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .font(.poppins(size: 48, weight: .semibold))
                            .foregroundStyle(accentBlue)
                            .multilineTextAlignment(.center)
                            .frame(width: 140)
                        Text("%")
                            .font(.poppins(size: 22, weight: .regular))
                            .foregroundStyle(accentBlue.opacity(0.6))
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.poppins(size: 13, weight: .regular))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                withAnimation { showHelp = true }
            } label: {
                choiceLabel(icon: "xmark.circle.fill", title: t.no, filled: false)
            }
        }
        .sheet(isPresented: $showHelp) {
            BodyFatHelpView(accentBlue: accentBlue, t: t, heightInCm: heightInCm,
                            selectedGender: selectedGender, femaleText: t.female) { estimated in
                bodyFatText = estimated
                knowsBodyFat = true
                showHelp = false
                onCommit?()
            }
        }
    }

    private func choiceLabel(icon: String, title: String, filled: Bool) -> some View {
        HStack {
            Image(systemName: icon).font(.system(size: 24))
            Text(title).font(.poppins(size: 20, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .foregroundStyle(filled ? .white : accentBlue)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(filled ? accentBlue : accentBlue.opacity(ControlAlpha.value(for: colorScheme)))
        )
    }
}

// MARK: - Metabolism questionnaire

/// The answers behind the metabolism factor.
///
/// The scoring used to be spelled out in both ContentView and DashboardView.
/// Keeping it next to the questionnaire means the edit sheet cannot score the
/// same answers differently from the onboarding.
struct MetabolismAnswers: Equatable, Codable {
    var thyroidCondition: String? = nil        // "hypo" | "hyper" | "none"
    var thyroidWellControlled: Bool? = nil
    var hypoSymptoms: Set<String> = []
    var hyperSymptoms: Set<String> = []
    var hasPCOS: Bool? = nil
    var insulinResistance: Bool? = nil
    var pcosSymptoms: Set<String> = []

    // MARK: Persistence
    //
    // Only the resulting factor used to be kept, so reopening the
    // questionnaire could not show what had been answered. The answers now
    // survive in UserDefaults; the factor stays the value the rest of the app
    // reads.

    private static let storageKey = "metabolismAnswers.v1"

    static func load() -> MetabolismAnswers {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(MetabolismAnswers.self, from: data)
        else { return MetabolismAnswers() }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func thyroidFactor(t: Translations) -> Double {
        guard let cond = thyroidCondition, cond != "none" else { return 1.0 }
        guard thyroidWellControlled == false else { return 1.0 }
        if cond == "hypo" {
            let count = hypoSymptoms.count
            let fatigue = hypoSymptoms.contains(t.hypoSymptomFatigue)
            let weightGain = hypoSymptoms.contains(t.hypoSymptomWeightGain)
            if count >= 4 || (fatigue && weightGain) { return 0.85 }
            if count >= 2 { return 0.92 }
            if count >= 1 { return 0.97 }
        } else {
            let count = hyperSymptoms.count
            if count >= 3 || hyperSymptoms.contains(t.hyperSymptomWeightLoss) { return 1.15 }
            if count >= 1 { return 1.07 }
        }
        return 1.0
    }

    func pcosFactor(t: Translations, isFemale: Bool) -> Double {
        guard isFemale, hasPCOS == true else { return 1.0 }
        if insulinResistance == true { return 0.85 }
        let count = pcosSymptoms.count
        let blocked = pcosSymptoms.contains(t.pcosSymptomBlocked)
        let carbFatigue = pcosSymptoms.contains(t.pcosSymptomCarbFatigue)
        if count >= 3 || (blocked && carbFatigue) { return 0.85 }
        return 1.0
    }

    /// Most extreme single factor — never multiplied together.
    func factor(t: Translations, isFemale: Bool) -> Double {
        let tf = thyroidFactor(t: t)
        let pf = pcosFactor(t: t, isFemale: isFemale)
        return abs(tf - 1.0) >= abs(pf - 1.0) ? tf : pf
    }

    func isComplete(isFemale: Bool) -> Bool {
        guard thyroidCondition != nil else { return false }
        if thyroidCondition != "none", thyroidWellControlled == nil { return false }
        if isFemale {
            guard let pcos = hasPCOS else { return false }
            if pcos, insulinResistance == nil { return false }
        }
        return true
    }
}

struct MetabolismQuestionnaire: View {
    let accentBlue: Color
    let t: Translations
    let isFemale: Bool
    @Binding var answers: MetabolismAnswers

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            section(title: t.thyroidSectionTitle) {
                VStack(spacing: 8) {
                    choice(t.thyroidHypo, selected: answers.thyroidCondition == "hypo") { setThyroid("hypo") }
                    choice(t.thyroidHyper, selected: answers.thyroidCondition == "hyper") { setThyroid("hyper") }
                    choice(t.thyroidNone, selected: answers.thyroidCondition == "none") { setThyroid("none") }
                }
            }

            if answers.thyroidCondition == "hypo" || answers.thyroidCondition == "hyper" {
                section(title: t.thyroidTherapyQuestion) {
                    VStack(spacing: 8) {
                        choice(t.thyroidOptimal, selected: answers.thyroidWellControlled == true) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                if answers.thyroidWellControlled == true {
                                    answers.thyroidWellControlled = nil
                                } else {
                                    answers.thyroidWellControlled = true
                                    answers.hypoSymptoms = []
                                    answers.hyperSymptoms = []
                                }
                            }
                        }
                        choice(t.thyroidNotOptimal, selected: answers.thyroidWellControlled == false) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                answers.thyroidWellControlled = answers.thyroidWellControlled == false ? nil : false
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if answers.thyroidCondition == "hypo" && answers.thyroidWellControlled == false {
                section(title: t.thyroidSymptomQuestion) {
                    VStack(spacing: 8) {
                        ForEach([t.hypoSymptomFatigue, t.hypoSymptomWeightGain, t.hypoSymptomCold,
                                 t.hypoSymptomSlow, t.hypoSymptomHair], id: \.self) { symptom in
                            checkbox(symptom, selected: answers.hypoSymptoms.contains(symptom)) {
                                toggle(symptom, in: \.hypoSymptoms)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if answers.thyroidCondition == "hyper" && answers.thyroidWellControlled == false {
                section(title: t.thyroidSymptomQuestion) {
                    VStack(spacing: 8) {
                        ForEach(isFemale
                                ? [t.hyperSymptomHeat, t.hyperSymptomWeightLoss, t.hyperSymptomHeart, t.hyperSymptomPeriod]
                                : [t.hyperSymptomHeat, t.hyperSymptomWeightLoss, t.hyperSymptomHeart],
                                id: \.self) { symptom in
                            checkbox(symptom, selected: answers.hyperSymptoms.contains(symptom)) {
                                toggle(symptom, in: \.hyperSymptoms)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isFemale {
                section(title: t.pcosSectionTitle) {
                    VStack(spacing: 8) {
                        choice(t.pcosYes, selected: answers.hasPCOS == true) { setPCOS(true) }
                        choice(t.pcosNo, selected: answers.hasPCOS == false) { setPCOS(false) }
                    }
                }
            }

            if isFemale && answers.hasPCOS == true {
                section(title: t.pcosInsulinQuestion) {
                    VStack(spacing: 8) {
                        choice(t.pcosInsulinYes, selected: answers.insulinResistance == true) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                if answers.insulinResistance == true {
                                    answers.insulinResistance = nil
                                } else {
                                    answers.insulinResistance = true
                                    answers.pcosSymptoms = []
                                }
                            }
                        }
                        choice(t.pcosInsulinNo, selected: answers.insulinResistance == false) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                answers.insulinResistance = answers.insulinResistance == false ? nil : false
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isFemale && answers.hasPCOS == true && answers.insulinResistance == false {
                section(title: t.pcosSymptomQuestion) {
                    VStack(spacing: 8) {
                        ForEach([t.pcosSymptomIrregular, t.pcosSymptomBlocked,
                                 t.pcosSymptomCarbFatigue, t.pcosSymptomHair], id: \.self) { symptom in
                            checkbox(symptom, selected: answers.pcosSymptoms.contains(symptom)) {
                                toggle(symptom, in: \.pcosSymptoms)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: answers.thyroidCondition)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: answers.thyroidWellControlled)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: answers.hasPCOS)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: answers.insulinResistance)
    }

    // MARK: Mutations

    private func setThyroid(_ value: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if answers.thyroidCondition == value {
                answers.thyroidCondition = nil
            } else {
                answers.thyroidCondition = value
                answers.thyroidWellControlled = nil
                answers.hypoSymptoms = []
                answers.hyperSymptoms = []
            }
        }
    }

    private func setPCOS(_ value: Bool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if answers.hasPCOS == value {
                answers.hasPCOS = nil
            } else {
                answers.hasPCOS = value
                answers.insulinResistance = nil
                answers.pcosSymptoms = []
            }
        }
    }

    private func toggle(_ symptom: String, in keyPath: WritableKeyPath<MetabolismAnswers, Set<String>>) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if answers[keyPath: keyPath].contains(symptom) {
                answers[keyPath: keyPath].remove(symptom)
            } else {
                answers[keyPath: keyPath].insert(symptom)
            }
        }
    }

    // MARK: Pieces

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.poppins(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(GlassCardBackground(cornerRadius: 14))
    }

    private func choice(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        optionRow(label, selected: selected,
                  icon: selected ? "checkmark.circle.fill" : "circle", action: action)
    }

    private func checkbox(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        optionRow(label, selected: selected,
                  icon: selected ? "checkmark.square.fill" : "square", action: action)
    }

    private func optionRow(_ label: String, selected: Bool, icon: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.poppins(size: 14, weight: .regular))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: icon).font(.system(size: 18))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .foregroundStyle(selected ? .white : accentBlue)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? accentBlue : accentBlue.opacity(ControlAlpha.value(for: colorScheme)))
            )
        }
    }
}
