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
