//
//  CalorieDetailView.swift
//  caloric
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
    
    var body: some View {
        NavigationStack {
            ZStack {
                CaloricBackground()
                
                VStack(spacing: 20) {
                    // Header with selection info
                    VStack(spacing: 8) {
                        if let selectedHour = selectedHour,
                           let slot = slots.min(by: { abs($0.hour - selectedHour) < abs($1.hour - selectedHour) }) {
                            Text(formatTime(hour: slot.hour))
                                .font(.poppins(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(Int(slot.isFuture ? slot.calories : slot.total))")
                                    .font(.poppins(size: 48, weight: .bold))
                                    .foregroundStyle(accentBlue)
                                Text("kcal")
                                    .font(.poppins(size: 20, weight: .semibold))
                                    .foregroundStyle(accentBlue.opacity(0.7))
                            }
                        } else {
                            Text(language == "de" ? "Tippe auf einen Balken" : "Tap on a bar")
                                .font(.poppins(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            Text("—")
                                .font(.poppins(size: 48, weight: .bold))
                                .foregroundStyle(accentBlue.opacity(0.3))
                        }
                    }
                    .padding(.top, 30)
                    .frame(height: 120)
                    
                    // The Chart
                    Chart {
                        ForEach(slots) { slot in
                            BarMark(
                                x: .value("Zeit", slot.hour),
                                y: .value("kcal", slot.isFuture ? slot.calories : slot.total)
                            )
                            .foregroundStyle(slotBarColor(slot))
                            .cornerRadius(4)
                            .opacity(isHighlighted(slot: slot) ? 1.0 : 0.3)
                        }
                        
                        if isSelectedToday {
                            RuleMark(x: .value("Jetzt", nowFraction))
                                .foregroundStyle(accentBlue)
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                                .annotation(position: .top, spacing: 4) {
                                    Text(language == "de" ? "Jetzt" : "Now")
                                        .font(.poppins(size: 10, weight: .semibold))
                                        .foregroundStyle(accentBlue)
                                }
                        }
                        
                        if let selectedHour = selectedHour {
                            RuleMark(x: .value("Auswahl", selectedHour))
                                .foregroundStyle(accentBlue.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1))
                        }
                    }
                    .frame(height: 320)
                    .chartXScale(domain: 0...24)
                    .chartXAxis {
                        AxisMarks(values: [0, 4, 8, 12, 16, 20, 24]) { value in
                            AxisValueLabel {
                                if let d = value.as(Double.self) {
                                    Text(String(format: "%02d:00", Int(d)))
                                        .font(.poppins(size: 12, weight: .regular))
                                }
                            }
                            AxisGridLine()
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine()
                            AxisValueLabel()
                                .font(.poppins(size: 10, weight: .regular))
                        }
                    }
                    .chartXSelection(value: $selectedHour)
                    .padding(20)
                    .glassCard(Theme.Radius.card)
                    .padding(.horizontal, 20)
                    
                    // Legend
                    HStack(spacing: 16) {
                        legendItem(color: accentBlue.opacity(isDark ? 0.40 : 0.25),
                                   label: language == "de" ? "Schlaf" : "Sleep")
                        legendItem(color: accentBlue,
                                   label: language == "de" ? "Wachphase" : "Awake")
                        legendItem(color: Theme.segEAT,
                                   label: language == "de" ? "Sport" : "Workout")
                        legendItem(color: Theme.ink.opacity(isDark ? 0.15 : 0.10),
                                   label: language == "de" ? "Zukunft" : "Future")
                    }
                    .padding(.top, 10)
                    
                    Spacer()
                }
            }
            .navigationTitle(language == "de" ? "Detailansicht" : "Detailed View")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(language == "de" ? "Fertig" : "Done") {
                        dismiss()
                    }
                    .font(.poppins(size: 16, weight: .semibold))
                    .foregroundStyle(accentBlue)
                }
            }
        }
    }
    
    private func isHighlighted(slot: CalorieSlot) -> Bool {
        guard let selected = selectedHour else { return true }
        // Da wir 30-Minuten-Slots haben (0.0, 0.5, 1.0, ...),
        // prüfen wir, ob das ausgewählte Datum in diesen Slot fällt.
        return abs(slot.hour - selected) < 0.25
    }
    
    private func slotBarColor(_ slot: CalorieSlot) -> Color {
        if slot.isFuture  { return Theme.ink.opacity(isDark ? 0.13 : 0.09) }
        if slot.isWorkout { return Theme.segEAT }
        if slot.isSleep   { return accentBlue.opacity(isDark ? 0.40 : 0.25) }
        return accentBlue.opacity(0.85)
    }
    
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.poppins(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
    
    private func formatTime(hour: Double) -> String {
        let h = Int(hour)
        let m = Int((hour - Double(h)) * 60)
        
        let endHour = hour + 0.5
        let hEnd = Int(endHour)
        let mEnd = Int((endHour - Double(hEnd)) * 60)
        
        return String(format: "%02d:%02d - %02d:%02d", h, m, hEnd % 24, mEnd)
    }
}
