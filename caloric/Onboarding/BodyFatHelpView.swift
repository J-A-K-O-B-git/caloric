//
//  BodyFatHelpView.swift
//  caloric
//
//  Sheet zum Schätzen des Körperfettanteils (Beispielbilder + Berechnung)
//

import SwiftUI

struct BodyFatHelpView: View {
    let accentBlue: Color
    let t: Translations
    let heightInCm: Double
    let selectedGender: String?
    let femaleText: String
    var onEstimate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    @State private var expandedPercent: Int? = nil

    private enum OutOfRangeField { case below, above }
    @State private var activeOutOfRange: OutOfRangeField? = nil
    @State private var belowRangeText = ""
    @State private var aboveRangeText = ""

    @State private var waistNavelText = ""
    @State private var waistNarrowText = ""
    @State private var neckText = ""
    @State private var showSavedBadge = false
    @State private var showCalcResult = false

    private var isFemale: Bool { selectedGender == femaleText }

    private let femaleValues = [10, 15, 20, 25, 30, 35, 40]
    private let maleValues   = [10, 15, 20, 25, 30, 35, 40]

    private var calculatedBF: Double? {
        guard heightInCm > 0,
              let waistNavel = Double(waistNavelText.replacingOccurrences(of: ",", with: ".")),
              let waistNarrow = Double(waistNarrowText.replacingOccurrences(of: ",", with: ".")),
              let neck = Double(neckText.replacingOccurrences(of: ",", with: ".")),
              waistNavel > 0, waistNarrow > 0, neck > 0
        else { return nil }
        let trueWaist = (waistNavel + waistNarrow) / 2.0
        let diff = trueWaist - neck
        guard diff > 0 else { return nil }
        let bf = 86.010 * log10(diff) - 70.041 * log10(heightInCm) + 36.76
        guard bf > 0 && bf <= 100 else { return nil }
        return bf
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 25) {
                Text(t.bodyFatHelpTitle)
                    .font(.poppins(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(t.bodyFatHelpSubtitle)
                    .font(.poppins(size: 14, weight: .regular))
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                Picker("Methode", selection: $selectedTab) {
                    Text(t.referenceImages).tag(0)
                    Text(t.calculation).tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                if selectedTab == 0 {
                    referenceImagesView
                } else {
                    calculationView
                }

                Spacer()
            }
            .padding(.top, 20)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t.cancel) { dismiss() }
                        .foregroundStyle(accentBlue)
                }
            }
            .overlay {
                if let percent = expandedPercent {
                    expandOverlay(percent: percent)
                }
            }
            .overlay(alignment: .top) {
                if showSavedBadge {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 16))
                        Text(t.language == "de" ? "Gespeichert!" : "Saved!")
                            .font(.poppins(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(accentBlue))
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSavedBadge)
        }
        
        .presentationBackground(Theme.canvas)
    }

    private func estimateWithBadge(_ value: String) {
        withAnimation { showSavedBadge = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            onEstimate(value)
        }
    }

    // MARK: - Expand Overlay

    private func expandOverlay(percent: Int) -> some View {
        let values = isFemale ? femaleValues : maleValues
        return ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { expandedPercent = nil }
                }

            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { expandedPercent = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.secondary)
                    }
                }

                if isFemale {
                    Image("bf_female_\(percent)")
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    Image(systemName: "figure.stand")
                        .font(.system(size: 120))
                        .foregroundStyle(accentBlue)
                        .frame(height: 200)
                }

                Text("~\(percent)%")
                    .font(.poppins(size: 30, weight: .semibold))
                    .foregroundStyle(accentBlue)

                HStack(spacing: 20) {
                    if let idx = values.firstIndex(of: percent), idx > 0 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { expandedPercent = values[idx - 1] }
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(accentBlue.opacity(0.7))
                        }
                    } else {
                        Color.clear.frame(width: 30, height: 30)
                    }

                    Button(t.calcUseResult) { estimateWithBadge("\(percent)") }
                        .font(.poppins(size: 16, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(accentBlue)
                        .controlSize(.large)

                    if let idx = values.firstIndex(of: percent), idx < values.count - 1 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { expandedPercent = values[idx + 1] }
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(accentBlue.opacity(0.7))
                        }
                    } else {
                        Color.clear.frame(width: 30, height: 30)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Theme.card)
                    .shadow(color: Theme.ink.opacity(0.16), radius: 24, x: 0, y: 10)
            )
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }

    // MARK: - Tab 1: Beispielbilder

    private var referenceImagesView: some View {
        ScrollView {
            VStack(spacing: 12) {
                infoBox(header: "Good to know", body: t.bfDisclaimer)
                infoBox(header: "Tipp", body: t.bfTip)

                Spacer().frame(height: 4)

                outOfRangeSection(label: t.bfBelowRange, field: .below, text: $belowRangeText)

                if isFemale {
                    femalePairSection
                } else {
                    malePairSection
                }

                outOfRangeSection(label: t.bfAboveRange, field: .above, text: $aboveRangeText)
            }
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Frauen: echte Bilder mit In-Between

    private var femalePairSection: some View {
        VStack(spacing: 8) {
            ForEach(Array(femaleValues.indices), id: \.self) { index in
                if index > 0 {
                    inBetweenButton(a: femaleValues[index - 1], b: femaleValues[index])
                }
                femaleThumbnailRow(percent: femaleValues[index])
                    .padding(.horizontal, 20)
            }
        }
    }

    private func femaleThumbnailRow(percent: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.76)) {
                expandedPercent = percent
            }
        } label: {
            HStack(spacing: 14) {
                Image("bf_female_\(percent)")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("~\(percent)%")
                        .font(.poppins(size: 18, weight: .semibold))
                        .foregroundStyle(accentBlue)
                    Text(t.language == "de" ? "Tippen zum Vergrößern" : "Tap to expand")
                        .font(.poppins(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13))
                    .foregroundStyle(accentBlue.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(accentBlue.opacity(isDark ? 0.16 : 0.07)))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(accentBlue.opacity(isDark ? 0.25 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Männer: SF Symbols mit In-Between

    private var malePairSection: some View {
        VStack(spacing: 8) {
            ForEach(Array(maleValues.indices), id: \.self) { index in
                if index > 0 {
                    inBetweenButton(a: maleValues[index - 1], b: maleValues[index])
                }
                maleThumbnailRow(percent: maleValues[index])
                    .padding(.horizontal, 20)
            }
        }
    }

    private func maleThumbnailRow(percent: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.76)) {
                expandedPercent = percent
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "figure.stand")
                    .font(.system(size: 36))
                    .foregroundStyle(accentBlue)
                    .frame(width: 52, height: 80)

                VStack(alignment: .leading, spacing: 3) {
                    Text("~\(percent)%")
                        .font(.poppins(size: 18, weight: .semibold))
                        .foregroundStyle(accentBlue)
                    Text(t.language == "de" ? "Tippen zum Vergrößern" : "Tap to expand")
                        .font(.poppins(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13))
                    .foregroundStyle(accentBlue.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(accentBlue.opacity(isDark ? 0.22 : 0.10)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - In-Between Button

    private func inBetweenButton(a: Int, b: Int) -> some View {
        let mid = Double(a + b) / 2.0
        let midStr = mid.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", mid) : String(format: "%.1f", mid)
        return Button { estimateWithBadge(midStr) } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.and.right").font(.system(size: 12))
                Text("\(t.inBetween) (~\(midStr)%)")
                    .font(.poppins(size: 13, weight: .regular))
            }
            .foregroundStyle(accentBlue.opacity(0.7))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(accentBlue.opacity(isDark ? 0.45 : 0.25), lineWidth: 1))
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Out-of-range

    private func outOfRangeSection(label: String, field: OutOfRangeField, text: Binding<String>) -> some View {
        let isShown = activeOutOfRange == field
        return VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    activeOutOfRange = isShown ? nil : field
                    text.wrappedValue = ""
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isShown ? "chevron.up" : "chevron.down").font(.system(size: 11))
                    Text(label).font(.poppins(size: 13, weight: .regular))
                }
                .foregroundStyle(accentBlue.opacity(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(accentBlue.opacity(isDark ? 0.35 : 0.20), lineWidth: 1))
            }
            .padding(.horizontal, 20)

            if isShown {
                HStack(spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        TextField("", text: text)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .font(.poppins(size: 26, weight: .semibold))
                            .foregroundStyle(accentBlue)
                            .multilineTextAlignment(.center)
                            .frame(width: 70)
                        Text("%")
                            .font(.poppins(size: 18, weight: .regular))
                            .foregroundStyle(accentBlue.opacity(0.6))
                    }
                    Spacer()
                    Button(t.calcUseResult) {
                        let val = text.wrappedValue.replacingOccurrences(of: ",", with: ".")
                        if !val.isEmpty { estimateWithBadge(val) }
                    }
                    .font(.poppins(size: 15, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .tint(accentBlue)
                    .controlSize(.regular)
                    .disabled(text.wrappedValue.isEmpty)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(accentBlue.opacity(isDark ? 0.18 : 0.07)))
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Info-Box

    private func infoBox(header: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(header)
                .font(.poppins(size: 12, weight: .semibold))
                .foregroundStyle(accentBlue)
            Text(body)
                .font(.poppins(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(accentBlue.opacity(isDark ? 0.18 : 0.07)))
        .padding(.horizontal, 20)
    }

    // MARK: - Tab 2: Berechnung

    private var calculationView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    infoBox(header: "Good to Know", body: t.calcInfo)
                    infoBox(header: "Tipp", body: t.bfTip)

                    if heightInCm <= 0 {
                        Text(t.calcHeightMissing)
                            .font(.poppins(size: 13, weight: .regular))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }

                    VStack(spacing: 14) {
                        circumferenceField(label: t.calcWaistNavel, placeholder: "90", text: $waistNavelText)
                        circumferenceField(label: t.calcWaistNarrow, placeholder: "80", text: $waistNarrowText)
                        circumferenceField(label: t.calcNeck, placeholder: "38", text: $neckText)
                    }
                    .padding(.horizontal, 20)
                    .onChange(of: waistNavelText) { showCalcResult = false }
                    .onChange(of: waistNarrowText) { showCalcResult = false }
                    .onChange(of: neckText) { showCalcResult = false }

                    Button(t.language == "de" ? "KFA berechnen" : "Calculate BF%") {
                        #if os(iOS)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        #endif
                        showCalcResult = true
                    }
                    .font(.poppins(size: 17, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .tint(accentBlue)
                    .controlSize(.large)
                    .disabled(waistNavelText.isEmpty || waistNarrowText.isEmpty || neckText.isEmpty)

                    if showCalcResult {
                        if let bf = calculatedBF {
                            VStack(spacing: 6) {
                                Text(t.calcResult)
                                    .font(.poppins(size: 14, weight: .regular))
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f%%", bf))
                                    .font(.poppins(size: 48, weight: .semibold))
                                    .foregroundStyle(accentBlue)
                            }
                            .padding(.top, 4)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            Button(t.calcUseResult) { estimateWithBadge(String(format: "%.1f", bf)) }
                                .font(.poppins(size: 18, weight: .medium))
                                .buttonStyle(.borderedProminent)
                                .tint(accentBlue)
                                .controlSize(.large)
                                .id("calcResult")
                        } else {
                            Text(t.calcInvalidInput)
                                .font(.poppins(size: 13, weight: .regular))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .transition(.opacity)
                                .id("calcResult")
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 30)
                .animation(.easeInOut(duration: 0.25), value: showCalcResult)
            }
            .onChange(of: showCalcResult) {
                if showCalcResult {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo("calcResult", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func circumferenceField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.poppins(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField(placeholder, text: text)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .font(.poppins(size: 22, weight: .semibold))
                    .foregroundStyle(accentBlue)
                    .multilineTextAlignment(.trailing)
                Text("cm")
                    .font(.poppins(size: 16, weight: .regular))
                    .foregroundStyle(accentBlue.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(accentBlue.opacity(isDark ? 0.18 : 0.07)))
        }
    }
}
