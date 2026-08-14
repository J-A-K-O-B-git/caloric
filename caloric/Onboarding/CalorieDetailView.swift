//
//  CalorieDetailView.swift
//  caloric
//
//  Full-screen view of the day's burn, split into the four phases the
//  dashboard chart shows: asleep, awake, training and the afterburn trailing
//  it. Bars stack the phases on the same half hour rather than colouring a
//  whole bar by its dominant one, so a half hour that was partly a workout
//  reads as exactly that.
//

import SwiftUI
import Charts

struct CalorieDetailView: View {
    let slots: [CalorieSlot]
    let accentBlue: Color
    let language: String
    let isSelectedToday: Bool
    let nowFraction: Double

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    @State private var selectedHour: Double?

    // MARK: - Derived figures

    /// Only elapsed half hours count. Future slots carry a projected resting
    /// share, which belongs in the chart but not in a "burnt so far" total.
    private var pastSlots: [CalorieSlot] { slots.filter { !$0.isFuture } }

    private var sleepKcal:     Double { pastSlots.reduce(0) { $0 + $1.sleepKcal } }
    private var awakeKcal:     Double { pastSlots.reduce(0) { $0 + $1.awakeKcal } }
    private var workoutKcal:   Double { pastSlots.reduce(0) { $0 + $1.workoutKcal } }
    private var afterburnKcal: Double { pastSlots.reduce(0) { $0 + $1.afterburnKcal } }
    private var dayKcal: Double { sleepKcal + awakeKcal + workoutKcal + afterburnKcal }

    private var selectedSlot: CalorieSlot? {
        guard let selectedHour else { return nil }
        return slots.min { abs($0.hour - selectedHour) < abs($1.hour - selectedHour) }
    }

    /// The figure the header shows: the picked half hour, else the whole day.
    private var headlineKcal: Double {
        guard let slot = selectedSlot else { return dayKcal }
        return slot.isFuture ? slot.calories : slot.total
    }

    private var sleepColor: Color { Theme.slate.opacity(0.55) }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                CaloricBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header
                        chartCard
                        phaseSummary
                        Spacer(minLength: 16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle(language == "de" ? "Detailansicht" : "Detailed View")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(language == "de" ? "Fertig" : "Done") { dismiss() }
                        .font(.poppins(size: 16, weight: .semibold))
                        .foregroundStyle(accentBlue)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text(headerCaption)
                .font(.poppins(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(Int(headlineKcal.rounded()))")
                    .font(.poppins(size: 44, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("kcal")
                    .font(.poppins(size: 16, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }

            // Which phases the selected half hour was actually made of. A slot
            // can hold more than one — waking up mid-slot, or a workout that
            // starts at ten past.
            if let slot = selectedSlot, !slot.isFuture {
                HStack(spacing: 6) {
                    if slot.sleepKcal > 0 {
                        phaseChip(sleepColor, language == "de" ? "Schlaf" : "Sleep", slot.sleepKcal)
                    }
                    if slot.awakeKcal > 0 {
                        phaseChip(accentBlue, language == "de" ? "Wach" : "Awake", slot.awakeKcal)
                    }
                    if slot.workoutKcal > 0 {
                        phaseChip(Theme.segEAT, language == "de" ? "Sport" : "Workout", slot.workoutKcal)
                    }
                    if slot.afterburnKcal > 0 {
                        phaseChip(Theme.segCaf,
                                  language == "de" ? "Nachbrennen" : "Afterburn",
                                  slot.afterburnKcal)
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 128)
        .animation(.easeOut(duration: 0.18), value: selectedHour)
    }

    private var headerCaption: String {
        if let slot = selectedSlot {
            return formatTime(hour: slot.hour)
        }
        if isSelectedToday {
            return language == "de" ? "Bisher heute verbrannt" : "Burnt so far today"
        }
        return language == "de" ? "An diesem Tag verbrannt" : "Burnt on this day"
    }

    private func phaseChip(_ color: Color, _ label: String, _ kcal: Double) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(Int(kcal.rounded()))")
                .font(.poppins(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.10)))
    }

    // MARK: - Chart

    private var chartCard: some View {
        Chart {
            ForEach(slots) { slot in
                if slot.isFuture {
                    BarMark(x: .value("Zeit", slot.hour + 0.25),
                            y: .value("kcal", slot.calories))
                        .foregroundStyle(Theme.ink.opacity(isDark ? 0.13 : 0.09))
                        .cornerRadius(3)
                        .opacity(dimming(slot))
                } else {
                    if slot.sleepKcal > 0 {
                        BarMark(x: .value("Zeit", slot.hour + 0.25),
                                y: .value("kcal", slot.sleepKcal))
                            .foregroundStyle(sleepColor)
                            .cornerRadius(3)
                            .opacity(dimming(slot))
                    }
                    if slot.awakeKcal > 0 {
                        BarMark(x: .value("Zeit", slot.hour + 0.25),
                                y: .value("kcal", slot.awakeKcal))
                            .foregroundStyle(accentBlue.opacity(0.9))
                            .cornerRadius(3)
                            .opacity(dimming(slot))
                    }
                    if slot.workoutKcal > 0 {
                        BarMark(x: .value("Zeit", slot.hour + 0.25),
                                y: .value("kcal", slot.workoutKcal))
                            .foregroundStyle(Theme.segEAT)
                            .cornerRadius(3)
                            .opacity(dimming(slot))
                    }
                    if slot.afterburnKcal > 0 {
                        BarMark(x: .value("Zeit", slot.hour + 0.25),
                                y: .value("kcal", slot.afterburnKcal))
                            .foregroundStyle(Theme.segCaf)
                            .cornerRadius(3)
                            .opacity(dimming(slot))
                    }
                }
            }

            if isSelectedToday {
                RuleMark(x: .value("Jetzt", nowFraction))
                    .foregroundStyle(Theme.textSecondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    .annotation(position: .top, spacing: 3) {
                        Text(language == "de" ? "Jetzt" : "Now")
                            .font(.poppins(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    }
            }
        }
        .frame(height: 300)
        .chartXScale(domain: 0...24)
        .chartXAxis {
            AxisMarks(values: [0, 4, 8, 12, 16, 20, 24]) { value in
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(String(format: "%02d", Int(d)))
                            .font(.poppins(size: 10, weight: .regular))
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    }
                }
                AxisGridLine().foregroundStyle(Theme.divider)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Theme.divider)
                AxisValueLabel()
                    .font(.poppins(size: 9, weight: .regular))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
        }
        .chartXSelection(value: $selectedHour)
        .padding(16)
        .glassCard(Theme.Radius.card)
    }

    /// Nothing selected: everything at full strength. Otherwise the picked
    /// half hour stays lit and the rest recedes.
    private func dimming(_ slot: CalorieSlot) -> Double {
        guard let selected = selectedHour else { return 1.0 }
        return abs(slot.hour + 0.25 - selected) < 0.25 ? 1.0 : 0.28
    }

    // MARK: - Phase summary

    private var phaseSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language == "de" ? "Nach Tagesphase" : "By phase of day")
                .font(.poppins(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            phaseRow(color: sleepColor, icon: "moon.zzz.fill",
                     label: language == "de" ? "Schlafphase" : "Sleep",
                     kcal: sleepKcal)
            phaseRow(color: accentBlue, icon: "figure.walk",
                     label: language == "de" ? "Wachphase" : "Awake",
                     kcal: awakeKcal)
            phaseRow(color: Theme.segEAT, icon: "dumbbell.fill",
                     label: language == "de" ? "Sport" : "Workout",
                     kcal: workoutKcal)
            phaseRow(color: Theme.segCaf, icon: "flame.fill",
                     label: language == "de" ? "Nachbrennen" : "Afterburn",
                     kcal: afterburnKcal)

            Text(language == "de"
                 ? "Die Wachphase enthält den Ruheumsatz dieser Stunden plus Alltagsbewegung, Verdauung und Koffein. Das Nachbrennen ist ein Modellwert: Wir schätzen, wie viele Kalorien nach einem Workout zusätzlich verbannt werden, und verteilen sie gleichmäßig auf die nächsten Stunden auf.": "The awake phase includes the resting metabolic rate for these hours plus everyday activities, digestion, and  caffeine consumption. The afterburn is a model value: we estimate how many calories are burned additionally  after a workout and distribute them evenly over the next few hours.")
                .font(.poppins(size: 10, weight: .regular))
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(Theme.Radius.card)
    }

    private func phaseRow(color: Color, icon: String, label: String, kcal: Double) -> some View {
        let share = dayKcal > 0 ? kcal / dayKcal : 0
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(color.opacity(0.13)))

                Text(label)
                    .font(.poppins(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Text("\(Int(kcal.rounded())) kcal")
                    .font(.poppins(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(String(format: "%.0f%%", share * 100))
                    .font(.poppins(size: 11, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 34, alignment: .trailing)
            }

            GeometryReader { geo in
                Capsule()
                    .fill(Theme.trackFill)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color)
                            .frame(width: max(0, geo.size.width * share))
                    }
                    .clipShape(Capsule())
            }
            .frame(height: 4)
        }
    }

    // MARK: - Helpers

    private func formatTime(hour: Double) -> String {
        let h = Int(hour)
        let m = Int((hour - Double(h)) * 60)
        let end = hour + 0.5
        let hEnd = Int(end)
        let mEnd = Int((end - Double(hEnd)) * 60)
        return String(format: "%02d:%02d – %02d:%02d", h, m, hEnd % 24, mEnd)
    }
}
