//
//  DayNarrativeCard.swift
//  caloric
//
//  Sits directly under the ring widget and explains the day's numbers in plain
//  language. Generated automatically — the user should find a text waiting,
//  not a button to press.
//
//  The card is deliberately styled unlike the rest of the dashboard: gradient
//  frame, sparkle mark, an explicit "KI" badge and a disclosure line. The text
//  is the one place in the app where the numbers are phrased by a model rather
//  than measured, and it should be recognisable as such at a glance.
//

import SwiftUI

struct DayNarrativeCard: View {

    let language: String
    let accentBlue: Color
    let narrative: DayNarrativeService.Narrative?
    let isLoading: Bool
    let errorMessage: String?
    let isStale: Bool
    let onRegenerate: () -> Void

    @State private var shimmerPhase: CGFloat = -1

    private var aiGradient: LinearGradient {
        LinearGradient(
            colors: [Theme.accentSky, accentBlue, Theme.segTEF],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let narrative {
                content(narrative)
            } else if isLoading {
                shimmerPlaceholder
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language == "de"
                         ? "Die Erklärung konnte gerade nicht erstellt werden."
                         : "The explanation could not be generated right now.")
                        .font(.poppins(size: 12, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // The reason, not just the fact. A generic sentence gave
                    // no way to tell a spent key from a routing problem
                    // without attaching a debugger.
                    Text(errorMessage.prefix(300))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            footer
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(aiGradient.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(aiGradient.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: accentBlue.opacity(0.10), radius: 12, x: 0, y: 4)
        )
    }

    // MARK: - Content

    private func content(_ narrative: DayNarrativeService.Narrative) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(narrative.headline)
                .font(.poppins(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(narrative.body)
                .font(.poppins(size: 12, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            // Set apart from the body on purpose: this is the line worth
            // staying for, and it should not read as a third sentence.
            if !narrative.insight.isEmpty {
                insightBlock(narrative.insight)
                    .padding(.top, 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// The insight, as its own small panel rather than a bulleted line.
    ///
    /// A lightbulb is the most worn-out symbol in software, and hanging one
    /// beside a sentence still leaves it looking like part of the paragraph.
    /// Giving the line its own surface, a hairline and a label does the work
    /// the icon was failing to do: the eye lands here separately, and it is
    /// obvious this is a find rather than a continuation.
    private func insightBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .bold))
                Text(language == "de" ? "WUSSTEST DU?" : "DID YOU KNOW?")
                    .font(.poppins(size: 8, weight: .bold))
                    .kerning(1.2)
            }
            .foregroundStyle(aiGradient)

            Text(text)
                .font(.poppins(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.9))
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(aiGradient.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(aiGradient.opacity(0.22), lineWidth: 0.8)
                )
        )
    }

    /// Three sweeping bars while the first text is on its way.
    private var shimmerPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            shimmerBar(widthFactor: 0.55, height: 13)
            shimmerBar(widthFactor: 1.00, height: 10)
            shimmerBar(widthFactor: 0.80, height: 10)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                shimmerPhase = 2
            }
        }
    }

    private func shimmerBar(widthFactor: CGFloat, height: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(Theme.trackFill)
                .overlay(
                    Capsule().fill(
                        LinearGradient(
                            colors: [.clear, accentBlue.opacity(0.25), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .offset(x: shimmerPhase * geo.size.width)
                )
                .clipShape(Capsule())
                .frame(width: geo.size.width * widthFactor, height: height)
        }
        .frame(height: height)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text("KI")
                .font(.poppins(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(aiGradient))

            if isStale {
                Text(language == "de" ? "Zahlen veraltet" : "Numbers stale")
                    .font(.poppins(size: 9, weight: .regular))
                    .foregroundStyle(Theme.textSecondary.opacity(0.65))
            }

            Spacer()

            if isLoading && narrative != nil {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: accentBlue))
                    .scaleEffect(0.6)
            }

            Button(action: onRegenerate) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentBlue.opacity(isLoading ? 0.35 : 0.8))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
    }
}

// MARK: - Deep dive entry point

/// The row that opens the long version of the day.
///
/// A button rather than a second card, for two reasons. It costs one line of
/// the dashboard instead of a screenful — and nothing is generated until it is
/// pressed, so a day nobody asks about is a day nobody pays a model for.
struct DayDeepDiveButton: View {

    let language: String
    let accentBlue: Color
    let action: () -> Void

    /// Slow, endless drift across the pill. Just enough motion to read as
    /// "there is something here" without pulling the eye off the ring above.
    @State private var shinePhase: CGFloat = -1

    private var aiGradient: LinearGradient {
        LinearGradient(
            colors: [Theme.accentSky, accentBlue, Theme.segTEF],
            startPoint: .leading, endPoint: .trailing
        )
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(aiGradient)

                Text(language == "de" ? "Dein Tag im Vergleich" : "Your day in context")
                    .font(.poppins(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.55))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(aiGradient.opacity(0.10))
                    )
                    .overlay(shine)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(aiGradient.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.linear(duration: 3.4).repeatForever(autoreverses: false)) {
                shinePhase = 2
            }
        }
    }

    private var shine: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.30), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: geo.size.width * 0.4)
                .offset(x: shinePhase * geo.size.width)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// The long version itself — nothing but the generated text.
///
/// No charts, no rows, no controls beyond closing and asking again: the point
/// of the sheet is that someone reads a few paragraphs and puts the phone
/// down.
struct DayDeepDiveSheet: View {

    let language: String
    let accentBlue: Color
    let deepDive: DayNarrativeService.DeepDive?
    let isLoading: Bool
    let errorMessage: String?
    let onRegenerate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shimmerPhase: CGFloat = -1

    private var aiGradient: LinearGradient {
        LinearGradient(
            colors: [Theme.accentSky, accentBlue, Theme.segTEF],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CaloricBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        badge

                        if let deepDive, !deepDive.paragraphs.isEmpty {
                            ForEach(deepDive.paragraphs.indices, id: \.self) { i in
                                // LocalizedStringKey is what turns the model's
                                // **…** into actual bold — a plain String
                                // initialiser would print the asterisks.
                                Text(LocalizedStringKey(deepDive.paragraphs[i]))
                                    .font(.poppins(size: 15, weight: .regular))
                                    .foregroundStyle(Theme.textPrimary.opacity(0.92))
                                    .lineSpacing(6)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else if isLoading {
                            placeholder
                        } else if let errorMessage {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(language == "de"
                                     ? "Der Vergleich konnte gerade nicht erstellt werden."
                                     : "The comparison could not be generated right now.")
                                    .font(.poppins(size: 14, weight: .regular))
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(errorMessage.prefix(300))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)

                                Button(action: onRegenerate) {
                                    Text(language == "de" ? "Erneut versuchen" : "Try again")
                                        .font(.poppins(size: 13, weight: .semibold))
                                        .foregroundStyle(accentBlue)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 4)
                            }
                        }

                        Spacer(minLength: 30)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                }
            }
            .navigationTitle(language == "de" ? "Dein Tag im Vergleich" : "Your day in context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onRegenerate()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(accentBlue.opacity(isLoading ? 0.35 : 0.9))
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language == "de" ? "Fertig" : "Done") { dismiss() }
                        .foregroundStyle(accentBlue)
                        .fontWeight(.semibold)
                }
            }
        }
        .caloricAppearance()
    }

    private var badge: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
            Text(language == "de" ? "VON DER KI GESCHRIEBEN" : "WRITTEN BY AI")
                .font(.poppins(size: 9, weight: .bold))
                .kerning(1.2)
        }
        .foregroundStyle(aiGradient)
    }

    /// Five bars in paragraph shape, so the sheet has the same silhouette
    /// while it waits as it will once the text lands.
    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 11) {
            let widths: [CGFloat] = [1.0, 0.95, 0.6, 1.0, 0.75]
            ForEach(widths.indices, id: \.self) { i in
                shimmerBar(widthFactor: widths[i])
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                shimmerPhase = 2
            }
        }
    }

    private func shimmerBar(widthFactor: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(Theme.trackFill)
                .overlay(
                    Capsule().fill(
                        LinearGradient(
                            colors: [.clear, accentBlue.opacity(0.25), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .offset(x: shimmerPhase * geo.size.width)
                )
                .clipShape(Capsule())
                .frame(width: geo.size.width * widthFactor, height: 12)
        }
        .frame(height: 12)
    }
}
