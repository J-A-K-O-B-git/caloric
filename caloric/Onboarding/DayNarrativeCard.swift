//
//  DayNarrativeCard.swift
//  caloric
//
//  The dashboard's AI surface: a button under the ring and the sheet it
//  opens.
//
//  There used to be a card here that generated two sentences on every visit,
//  read or not. It was replaced by this pair — the text now costs nothing
//  until someone asks for it, and when they do they get the long version
//  rather than a teaser.
//
//  Both are deliberately styled unlike the rest of the dashboard: gradient
//  frame, sparkle mark, an explicit AI label. This is the one place in the app
//  where the numbers are phrased by a model rather than measured, and it
//  should be recognisable as such at a glance.
//

import SwiftUI

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
