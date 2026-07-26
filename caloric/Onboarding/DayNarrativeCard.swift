//
//  DayNarrativeCard.swift
//  caloric
//
//  Dashboard card that explains the day's numbers in plain language.
//
//  The request is triggered explicitly rather than on appear: it keeps the
//  cost predictable, and it makes clear to the user that a text is being
//  generated rather than measured.
//

import SwiftUI

struct DayNarrativeCard: View {

    let language: String
    let accentBlue: Color
    let narrative: DayNarrativeService.Narrative?
    let isLoading: Bool
    let errorMessage: String?
    let isStale: Bool
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let narrative {
                VStack(alignment: .leading, spacing: 6) {
                    Text(narrative.headline)
                        .font(.poppins(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(narrative.body)
                        .font(.poppins(size: 12, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)

                if isStale {
                    Text(language == "de"
                         ? "Die Zahlen haben sich seitdem geändert."
                         : "The numbers have changed since then.")
                        .font(.poppins(size: 10, weight: .regular))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
            } else if !isLoading && errorMessage == nil {
                Text(language == "de"
                     ? "Lass dir in zwei Sätzen erklären, was deinen Tag von gestern unterscheidet."
                     : "Get a two-sentence explanation of what sets today apart from yesterday.")
                    .font(.poppins(size: 12, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.poppins(size: 11, weight: .regular))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            generateButton
        }
        .padding(16)
        .glassCard(20)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(accentBlue.opacity(0.15)).frame(width: 32, height: 32)
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(accentBlue)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(language == "de" ? "Dein Tag erklärt" : "Your day explained")
                    .font(.poppins(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(language == "de" ? "Vergleich zum Vortag" : "Compared to yesterday")
                    .font(.poppins(size: 11, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }

    private var generateButton: some View {
        Button(action: onGenerate) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: narrative == nil ? "sparkles" : "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(buttonTitle)
                    .font(.poppins(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(accentBlue.opacity(isLoading ? 0.6 : 1.0)))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var buttonTitle: String {
        if isLoading { return language == "de" ? "Wird erstellt…" : "Generating…" }
        if narrative == nil { return language == "de" ? "Tag erklären" : "Explain my day" }
        return language == "de" ? "Neu erstellen" : "Regenerate"
    }
}
