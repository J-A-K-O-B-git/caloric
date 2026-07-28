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
    /// The figure the text explains — the same one the KPI tile shows, echoed
    /// here so the connection between card and number is visible.
    let percentVsPreviousDay: Double
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
            header

            if isLoading && narrative == nil {
                shimmerPlaceholder
            } else if let narrative {
                content(narrative)
            } else if errorMessage != nil {
                Text(language == "de"
                     ? "Die Erklärung konnte gerade nicht erstellt werden."
                     : "The explanation could not be generated right now.")
                    .font(.poppins(size: 12, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text(language == "de" ? "Dein Tagesüberblick" : "Your Day Overview")
                .font(.poppins(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            // Same figure as the KPI tile below — the card explains this number.
            Text(String(format: "%+.0f %%", percentVsPreviousDay))
                .font(.poppins(size: 13, weight: .semibold))
                .foregroundStyle(percentVsPreviousDay >= 0 ? .green : .red)

            if isLoading && narrative != nil {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: accentBlue))
                    .scaleEffect(0.6)
            }
        }
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
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
        HStack(spacing: 6) {
            Text(disclosure)
                .font(.poppins(size: 9, weight: .regular))
                .foregroundStyle(Theme.textSecondary.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: onRegenerate) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentBlue.opacity(isLoading ? 0.35 : 0.8))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
    }

    private var disclosure: String {
        if isStale {
            return language == "de"
                ? "KI-generiert"
                : "AI-generated"
        }
        return language == "de"
            ? "KI-generiert"
            : "AI-generated"
    }
}
