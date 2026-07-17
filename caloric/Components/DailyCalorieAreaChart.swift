//
//  DailyCalorieAreaChart.swift
//  caloric
//
//  Ersatz für die BarMark-Darstellung im Tagesverlauf.
//  Features:
//    · AreaMark + LineMark (catmullRom) statt BarMark
//    · Vergangenheit: voller Gradient, Zukunft: ≈13 % Opacity
//    · Schlafzone: dezente RectangleMark-Hintergrundschraffur
//    · Workout-EAT-Band am Fuß der Fläche
//    · Peak-Markierungen: PointMark wenn Wert > 30 % über 2h-Schnitt
//    · „Jetzt"-RuleMark
//    · Alle Farben über Theme-Tokens (Dark-Mode-safe)
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
    /// Stunde, zu der der Schlaf endet (= Beginn der Wachphase). Typisch 6–8.
    let sleepEndHour: Double
    let language: String
    /// Faktor, ab dem ein Slot als Peak gilt (1.30 = 30 % über Schnitt).
    var peakThreshold: Double = 1.30

    // MARK: Environment

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    // MARK: Internal types

    /// Datenpunkt für einen Chart-Series-Eintrag.
    private struct AreaPt: Identifiable { let id: Int; let x, y: Double }
    private struct LinePt: Identifiable { let id: Int; let x, y: Double }
    private struct PeakPt: Identifiable { let id: Int; let x, y: Double }

    // MARK: Derived series

    private var pastArea: [AreaPt] {
        slots.enumerated().compactMap { i, s in
            guard !s.isFuture else { return nil }
            return AreaPt(id: i, x: s.hour + 0.25, y: s.total)
        }
    }

    private var pastLine: [LinePt] {
        slots.enumerated().compactMap { i, s in
            guard !s.isFuture else { return nil }
            return LinePt(id: i, x: s.hour + 0.25, y: s.total)
        }
    }

    private var futureArea: [AreaPt] {
        slots.enumerated().compactMap { i, s in
            guard s.isFuture else { return nil }
            return AreaPt(id: i, x: s.hour + 0.25, y: s.calories)
        }
    }

    private var futureLine: [LinePt] {
        slots.enumerated().compactMap { i, s in
            guard s.isFuture else { return nil }
            return LinePt(id: i, x: s.hour + 0.25, y: s.calories)
        }
    }

    private var workoutArea: [AreaPt] {
        slots.enumerated().compactMap { i, s in
            guard !s.isFuture, s.isWorkout, s.workoutKcal > 0 else { return nil }
            return AreaPt(id: i + 10_000, x: s.hour + 0.25, y: s.workoutKcal)
        }
    }

    private var peakMarkers: [PeakPt] {
        var result: [PeakPt] = []
        for (i, s) in slots.enumerated() {
            guard !s.isFuture, !s.isSleep, s.total > 0 else { continue }
            let windowStart = max(0, i - 4)
            let window = slots[windowStart..<i].filter { !$0.isSleep && !$0.isFuture }
            guard window.count >= 2 else { continue }
            let avg = window.reduce(0.0) { $0 + $1.total } / Double(window.count)
            guard avg > 5, s.total > avg * peakThreshold else { continue }
            result.append(PeakPt(id: i, x: s.hour + 0.25, y: s.total))
        }
        return result
    }

    // MARK: Gradients

    private var pastGradient: LinearGradient {
        LinearGradient(
            colors: [accentBlue.opacity(0.58), accentBlue.opacity(0.02)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var futureGradient: LinearGradient {
        LinearGradient(
            colors: [accentBlue.opacity(0.13), accentBlue.opacity(0.01)],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: Body

    var body: some View {
        Chart {
            // ① Schlaf-Hintergrundzone
            if sleepEndHour > 0 {
                RectangleMark(
                    xStart: .value("", 0.0),
                    xEnd:   .value("", sleepEndHour)
                )
                .foregroundStyle(Theme.ink.opacity(isDark ? 0.08 : 0.04))
            }

            // ② Vergangenheit — Fläche
            ForEach(pastArea) { pt in
                AreaMark(
                    x:      .value("Zeit", pt.x),
                    yStart: .value("",     0.0),
                    yEnd:   .value("kcal", pt.y)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(pastGradient)
            }

            // ② Vergangenheit — Linie
            ForEach(pastLine) { pt in
                LineMark(
                    x: .value("Zeit", pt.x),
                    y: .value("kcal", pt.y)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(accentBlue)
                .lineStyle(StrokeStyle(lineWidth: 1.8))
            }

            // ③ Zukunft — blasse Fläche
            ForEach(futureArea) { pt in
                AreaMark(
                    x:      .value("Zeit", pt.x),
                    yStart: .value("",     0.0),
                    yEnd:   .value("kcal", pt.y)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(futureGradient)
            }

            // ③ Zukunft — sehr blasse Linie
            ForEach(futureLine) { pt in
                LineMark(
                    x: .value("Zeit", pt.x),
                    y: .value("kcal", pt.y)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(accentBlue.opacity(0.22))
                .lineStyle(StrokeStyle(lineWidth: 1.0))
            }

            // ④ Workout-EAT-Band am Fuß
            ForEach(workoutArea) { pt in
                AreaMark(
                    x:      .value("Zeit", pt.x),
                    yStart: .value("",     0.0),
                    yEnd:   .value("kcal", pt.y)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Theme.segEAT.opacity(0.40))
            }

            // ⑤ Peak-Marker
            ForEach(peakMarkers) { pt in
                PointMark(
                    x: .value("Zeit", pt.x),
                    y: .value("kcal", pt.y)
                )
                .foregroundStyle(Theme.segEAT)
                .symbolSize(22)
            }

            // ⑥ „Jetzt"-RuleMark
            if isSelectedToday {
                RuleMark(x: .value("Jetzt", nowFraction))
                    .foregroundStyle(accentBlue)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .annotation(position: .top, spacing: 2) {
                        Text(language == "de" ? "Jetzt" : "Now")
                            .font(.poppins(size: 7, weight: .semibold))
                            .foregroundStyle(accentBlue)
                    }
            }
        }
        .chartXScale(domain: 0...24)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(String(format: "%02d:00", Int(d)))
                            .font(.poppins(size: 8, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel()
                    .font(.poppins(size: 8, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
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
                case 8..<10:   mult = 1.14
                case 12..<13.5: mult = 1.10
                case 17..<19:  mult = 1.20
                case 21..<23:  mult = 0.90
                default:       mult = 1.0
                }
            }
            return CalorieSlot(
                hour: hour,
                calories: base * 0.5 * mult,
                workoutKcal: isWorkout ? 90.0 : 0.0,
                isSleep: sleeping,
                isWorkout: isWorkout,
                isFuture: isFuture
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
