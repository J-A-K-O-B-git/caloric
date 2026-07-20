//
//  DailyCalorieAreaChart.swift
//  caloric
//
//  Gradient-Aktivitätsbalken: BarMark mit vertikalem Farbverlauf.
//  · Vergangenheit: sattes Blau oben → transparent unten (globaler Gradient → kurze Balken = heller)
//  · Zukunft: sehr blasse Variante desselben Gradienten
//  · Tooltip auf dem Spitzen-Slot (auto, kein Fingerdruck nötig)
//  · Dashed „Jetzt"-RuleMark
//

import SwiftUI
import Charts

// MARK: - DailyCalorieAreaChart

struct DailyCalorieAreaChart: View {

    // MARK: Input

    let slots: [CalorieSlot]
    let accentBlue: Color
    let nowFraction: Double
    let isSelectedToday: Bool
    let sleepEndHour: Double
    let language: String
    var peakThreshold: Double = 1.30      // unused externally but kept for API compatibility

    // MARK: Environment

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    // MARK: State

    @State private var selectedSlot: CalorieSlot? = nil

    // MARK: Gradients
    // Applied globally across chart height → tall bars appear dark, short bars appear light.

    private var pastGradient: LinearGradient {
        LinearGradient(
            colors: [accentBlue, accentBlue.opacity(0.25)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var futureGradient: LinearGradient {
        LinearGradient(
            colors: [accentBlue.opacity(0.28), accentBlue.opacity(0.06)],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: Body

    var body: some View {
        Chart {
            // ① Past bars
            ForEach(slots.filter { !$0.isFuture }, id: \.id) { slot in
                BarMark(
                    x: .value("Zeit", slot.hour + 0.25),
                    y: .value("kcal", slot.total),
                    width: .fixed(4)
                )
                .foregroundStyle(pastGradient)
                .cornerRadius(2)
            }

            // ② Future bars (lighter)
            ForEach(slots.filter { $0.isFuture }, id: \.id) { slot in
                BarMark(
                    x: .value("Zeit", slot.hour + 0.25),
                    y: .value("kcal", slot.calories),
                    width: .fixed(4)
                )
                .foregroundStyle(futureGradient)
                .cornerRadius(2)
            }

            // ③ Tap-tooltip on selected slot
            if let sel = selectedSlot, sel.total > 0 {
                RuleMark(x: .value("Selected", sel.hour + 0.25))
                    .foregroundStyle(.clear)
                    .annotation(
                        position: .top,
                        spacing: 6,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        tooltipBubble(for: sel)
                    }
            }

            // ④ „Jetzt" dashed line
            if isSelectedToday {
                RuleMark(x: .value("Jetzt", nowFraction))
                    .foregroundStyle(Theme.textSecondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                    .annotation(position: .top, spacing: 2) {
                        Text(language == "de" ? "Jetzt" : "Now")
                            .font(.poppins(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary.opacity(0.55))
                    }
            }
        }
        .chartXScale(domain: 0...24)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(String(format: "%02d:00", Int(d)))
                            .font(.poppins(size: 9, weight: .regular))
                            .foregroundStyle(Theme.textSecondary.opacity(0.55))
                    }
                }
                AxisGridLine().foregroundStyle(.clear)
            }
        }
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let origin = geo[proxy.plotAreaFrame].origin
                                let lx = value.location.x - origin.x
                                guard let x: Double = proxy.value(atX: lx) else { return }
                                let closest = slots.min(by: {
                                    abs($0.hour + 0.25 - x) < abs($1.hour + 0.25 - x)
                                })
                                withAnimation(.easeOut(duration: 0.08)) {
                                    selectedSlot = closest
                                }
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selectedSlot = nil
                                }
                            }
                    )
            }
        }
    }

    // MARK: Tooltip bubble

    private func tooltipBubble(for slot: CalorieSlot) -> some View {
        let hour   = Int(slot.hour)
        let minute = slot.hour.truncatingRemainder(dividingBy: 1) >= 0.5 ? 30 : 0
        let time   = String(format: "%02d:%02d", hour, minute)
        let kcal   = Int(slot.total.rounded())
        return Text("\(time) · \(kcal) kcal")
            .font(.poppins(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(isDark ? Color(white: 0.22) : Color(white: 0.12)))
    }
}

// MARK: - Preview mock data

private extension [CalorieSlot] {
    static func mockDay(sleepHours: Double = 7.0, now: Double = 14.5) -> [CalorieSlot] {
        let base = 75.0
        return stride(from: 0.0, to: 24.0, by: 0.5).map { hour in
            let sleeping  = hour < sleepHours
            let isFuture  = hour >= now
            let isWorkout = hour >= 17.5 && hour < 18.5
            let mult: Double
            if sleeping {
                mult = 0.88
            } else {
                switch hour {
                case sleepHours..<(sleepHours + 1.5): mult = 0.94
                case 8..<10:    mult = 1.14
                case 12..<13.5: mult = 1.10
                case 17..<19:   mult = 1.20
                case 21..<23:   mult = 0.90
                default:        mult = 1.0
                }
            }
            return CalorieSlot(
                hour:       hour,
                calories:   base * 0.5 * mult,
                workoutKcal: isWorkout ? 90.0 : 0.0,
                isSleep:    sleeping,
                isWorkout:  isWorkout,
                isFuture:   isFuture
            )
        }
    }
}

// MARK: - Previews

#Preview("Light – 14:30 Uhr") {
    DailyCalorieAreaChart(
        slots: .mockDay(),
        accentBlue: Theme.accentBlue,
        nowFraction: 14.5,
        isSelectedToday: true,
        sleepEndHour: 7.0,
        language: "de"
    )
    .frame(height: 130)
    .padding()
    .background(Theme.canvas)
}

#Preview("Dark – 14:30 Uhr") {
    DailyCalorieAreaChart(
        slots: .mockDay(),
        accentBlue: Theme.accentBlue,
        nowFraction: 14.5,
        isSelectedToday: true,
        sleepEndHour: 7.0,
        language: "de"
    )
    .frame(height: 130)
    .padding()
    .background(Theme.canvas)
    .preferredColorScheme(.dark)
}
