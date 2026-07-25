//
//  ProfileWizardView.swift
//  caloric
//

import SwiftUI

struct ProfileWizardView: View {
    let accentBlue: Color
    let language: String
    let femaleText: String
    let noConditionText: String
    
    @Binding var birthDate: Date
    @Binding var weightText: String
    @Binding var weightUnit: String
    @Binding var heightText: String
    @Binding var heightUnit: String
    @Binding var bodyFatText: String
    @Binding var knowsBodyFat: Bool?
    @Binding var selectedConditions: Set<String>
    @Binding var metabolismFactor: Double
    @Binding var sleepHours: Double

    @State private var currentStep = 1
    @State private var isNavigatingForward = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    private var dimAlpha: Double { isDark ? 0.42 : 0.25 }
    private var controlAlpha: Double { isDark ? 0.22 : 0.10 }
    private var t: Translations { Translations(language: language) }
    
    private var topSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 50
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isNavigatingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: isNavigatingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func navigate(to step: Int) {
        isNavigatingForward = step >= currentStep
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
            currentStep = step
        }
    }

    var body: some View {
        ZStack {
            CaloricBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with Progress Bar
                progressBar
                    .padding(.top, 10)
                
                // Content
                ZStack {
                    currentPageView
                        .transition(pageTransition)
                        .id(currentStep)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Close Button
                Button {
                    dismiss()
                } label: {
                    Text(language == "de" ? "Schließen" : "Close")
                        .font(.poppins(size: 16, weight: .semibold))
                        .foregroundStyle(accentBlue.opacity(0.7))
                }
                .padding(.bottom, 30)
            }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
                let stepIdx = index + 1
                let isDone = stepIdx < currentStep
                let isCurrent = stepIdx == currentStep
                let isReached = stepIdx <= currentStep

                if index > 0 {
                    Capsule()
                        .fill(isReached ? accentBlue : accentBlue.opacity(dimAlpha))
                        .frame(height: 2.5)
                        .animation(.easeInOut, value: currentStep)
                }
                
                Button {
                    navigate(to: stepIdx)
                } label: {
                    VStack(spacing: 7) {
                        ZStack {
                            Circle()
                                .fill(isReached ? accentBlue : accentBlue.opacity(dimAlpha))
                                .frame(width: 34, height: 34)
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
                                Text("\(stepIdx)")
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
            }
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var currentPageView: some View {
        switch currentStep {
        case 1: genderPage
        case 2: agePage
        case 3: weightPage
        case 4: heightPage
        case 5: bodyFatPage
        case 6: metabolismPage
        default: EmptyView()
        }
    }

    // --- Pages Replicated from Onboarding ---

    private var genderPage: some View {
        VStack(spacing: 25) {
            Text(t.genderQuestion).font(.poppins(size: 28, weight: .semibold)).multilineTextAlignment(.center)
            hintBox(t.genderInfo)
            VStack(spacing: 16) {
                genderButton(title: t.male, icon: "figure.stand")
                genderButton(title: t.female, icon: "figure.stand.dress")
            }
        }.padding()
    }

    private var agePage: some View {
        VStack(spacing: 25) {
            Text(t.ageQuestion).font(.poppins(size: 28, weight: .semibold)).multilineTextAlignment(.center)
            hintBox(t.ageInfo)
            DatePicker("", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                .datePickerStyle(.wheel).labelsHidden()
            Button(t.next) { navigate(to: 3) }.buttonStyle(.caloricPrimary)
        }.padding()
    }

    private var weightPage: some View {
        VStack(spacing: 25) {
            Text(t.weightQuestion).font(.poppins(size: 28, weight: .semibold))
            hintBox(t.weightInfo)
            
            HStack {
                TextField("70", text: $weightText)
                    .keyboardType(.decimalPad)
                    .font(.poppins(size: 44, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(width: 140)
                Text(weightUnit).font(.poppins(size: 22, weight: .semibold)).foregroundStyle(accentBlue)
            }
            .padding().background(GlassCardBackground(cornerRadius: 16))
            
            Button(t.next) { navigate(to: 4) }.buttonStyle(.caloricPrimary)
        }.padding()
    }

    private var heightPage: some View {
        VStack(spacing: 25) {
            Text(t.heightQuestion).font(.poppins(size: 28, weight: .semibold))
            hintBox(t.heightInfo)
            
            HStack {
                TextField("170", text: $heightText)
                    .keyboardType(.numberPad)
                    .font(.poppins(size: 44, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(width: 140)
                Text(heightUnit).font(.poppins(size: 22, weight: .semibold)).foregroundStyle(accentBlue)
            }
            .padding().background(GlassCardBackground(cornerRadius: 16))
            
            Button(t.next) { navigate(to: 5) }.buttonStyle(.caloricPrimary)
        }.padding()
    }

    private var bodyFatPage: some View {
        VStack(spacing: 25) {
            Text(t.bodyFatQuestion).font(.poppins(size: 28, weight: .semibold)).multilineTextAlignment(.center)
            hintBox(t.bodyFatInfo)
            
            VStack(spacing: 12) {
                Button { knowsBodyFat = true } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text(t.yes)
                        Spacer()
                        if knowsBodyFat == true {
                            TextField("15", text: $bodyFatText).keyboardType(.decimalPad).frame(width: 60).multilineTextAlignment(.trailing)
                            Text("%")
                        }
                    }
                    .padding().frame(height: 60)
                    .background(RoundedRectangle(cornerRadius: 16).fill(knowsBodyFat == true ? accentBlue : accentBlue.opacity(controlAlpha)))
                    .foregroundStyle(knowsBodyFat == true ? .white : accentBlue)
                }
                
                Button { knowsBodyFat = false; bodyFatText = "" } label: {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text(t.no)
                        Spacer()
                    }
                    .padding().frame(height: 60)
                    .background(RoundedRectangle(cornerRadius: 16).fill(knowsBodyFat == false ? accentBlue : accentBlue.opacity(controlAlpha)))
                    .foregroundStyle(knowsBodyFat == false ? .white : accentBlue)
                }
            }
            
            Button(t.next) { navigate(to: 6) }.buttonStyle(.caloricPrimary)
        }.padding()
    }

    private var metabolismPage: some View {
        ScrollView {
            VStack(spacing: 25) {
                Text(t.metabolismQuestion).font(.poppins(size: 28, weight: .semibold)).multilineTextAlignment(.center)
                hintBox(t.metabolismInfo)
                
                VStack(spacing: 10) {
                    ForEach([t.hypothyroidism, t.hyperthyroidism, t.pcos, t.menopause, t.noCondition], id: \.self) { cond in
                        Button {
                            if cond == t.noCondition { selectedConditions = [t.noCondition] }
                            else {
                                selectedConditions.remove(t.noCondition)
                                if selectedConditions.contains(cond) { selectedConditions.remove(cond) }
                                else { selectedConditions.insert(cond) }
                            }
                        } label: {
                            HStack {
                                Text(cond).font(.poppins(size: 15, weight: .medium))
                                Spacer()
                                Image(systemName: selectedConditions.contains(cond) ? "checkmark.circle.fill" : "circle")
                            }
                            .padding().background(Theme.fieldFill).clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(selectedConditions.contains(cond) ? accentBlue : .primary)
                        }
                    }
                }
                
                Button(t.done) { dismiss() }.buttonStyle(.caloricPrimary)
            }.padding()
        }
    }

    // --- Helpers ---

    private func genderButton(title: String, icon: String) -> some View {
        Button { navigate(to: 2) } label: { // In edit mode, we just move next
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 32))
                Text(title).font(.poppins(size: 20, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 24).frame(height: 70)
            .background(RoundedRectangle(cornerRadius: 16).fill(accentBlue.opacity(controlAlpha)))
            .foregroundStyle(accentBlue)
        }
    }

    private func hintBox(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Good to Know").font(.poppins(size: 12, weight: .semibold)).foregroundStyle(accentBlue)
            Text(text).font(.poppins(size: 13, weight: .regular)).foregroundStyle(.secondary).lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(GlassCardBackground(cornerRadius: 14, tint: accentBlue, tintStrength: 0.05))
    }
}
