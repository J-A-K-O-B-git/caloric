//
//  SettingsView.swift
//  caloric
//
//  System settings — everything about how the app behaves, nothing about who
//  the user is. Master data (gender, age, height, weight, body fat,
//  conditions) lives in one place only, "Meine Daten → Stammdaten"; it used to
//  be editable from three screens and the copies disagreed with each other.
//
//  These are the building blocks the dashboard's sidebar assembles. The file
//  once held a settings screen of its own that nothing ever presented; the
//  parts survived, the screen did not.
//

import SwiftUI

// MARK: - Shared chrome

/// One labelled control on a settings card.
struct SettingsRow<Content: View>: View {
    let icon: String
    let label: String
    let accent: Color
    var caption: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.poppins(size: 15, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                if let caption {
                    Text(caption)
                        .font(.poppins(size: 11, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)
            content
        }
        .padding(.vertical, 6)
    }
}

/// The app's two-state segmented control, sized for a settings row.
struct SettingsSegments: View {
    let options: [(value: String, title: String)]
    let accent: Color
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let isOn = selection == option.value
                Button {
                    guard !isOn else { return }
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.poppins(size: 12, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? .white : Theme.textSecondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isOn ? accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.trackFill))
    }
}

// MARK: - Language

/// Writes straight through to the stored profile.
///
/// The language is handed down the view tree as a plain value, not a binding,
/// so there is nothing to write back to — but every screen reads it from the
/// same profile record, and changing that record redraws all of them.
struct LanguageSetting: View {
    let accent: Color
    let language: String
    let onChange: (String) -> Void

    var body: some View {
        SettingsRow(icon: "globe", label: language == "de" ? "Sprache" : "Language", accent: accent) {
            SettingsSegments(
                options: [(value: "de", title: "Deutsch"), (value: "en", title: "English")],
                accent: accent,
                selection: Binding(get: { language }, set: onChange)
            )
        }
    }
}

// MARK: - Units

/// Switching units converts the stored figure instead of relabelling it.
///
/// Relabelling would turn 78 kg into 78 lb — a third of the weight, silently,
/// and every calculation downstream reads it as fact.
struct UnitSettings: View {
    let accent: Color
    let language: String
    @Binding var weightText: String
    @Binding var weightUnit: String
    @Binding var heightText: String
    @Binding var heightUnit: String

    var body: some View {
        VStack(spacing: 4) {
            SettingsRow(icon: "scalemass", label: language == "de" ? "Gewichtseinheit" : "Weight unit", accent: accent) {
                SettingsSegments(
                    options: [(value: "kg", title: "kg"), (value: "lb", title: "lb")],
                    accent: accent,
                    selection: Binding(get: { weightUnit }, set: setWeightUnit)
                )
            }
            Divider().padding(.leading, 40)
            SettingsRow(icon: "ruler", label: language == "de" ? "Größeneinheit" : "Height unit", accent: accent) {
                SettingsSegments(
                    options: [(value: "cm", title: "cm"), (value: "ft", title: "ft")],
                    accent: accent,
                    selection: Binding(get: { heightUnit }, set: setHeightUnit)
                )
            }
        }
    }

    private func setWeightUnit(_ unit: String) {
        guard unit != weightUnit else { return }
        let kg = MeasurementParsing.weightKg(text: weightText, unit: weightUnit)
        weightUnit = unit
        guard kg > 0 else { return }
        weightText = unit == "kg"
            ? String(format: "%.1f", kg)
            : String(format: "%.1f", kg / 0.453592)
    }

    private func setHeightUnit(_ unit: String) {
        guard unit != heightUnit else { return }
        let cm = MeasurementParsing.heightCm(text: heightText, unit: heightUnit)
        heightUnit = unit
        guard cm > 0 else { return }
        if unit == "cm" {
            heightText = String(format: "%.0f", cm)
        } else {
            let totalInches = cm / 2.54
            let feet = Int(totalInches / 12)
            let inches = Int((totalInches - Double(feet) * 12).rounded())
            // 11.6 inches rounds to 12, which is not an inch count — carry it.
            heightText = inches >= 12 ? "\(feet + 1)'0\"" : "\(feet)'\(inches)\""
        }
    }
}

// MARK: - Weight source

enum WeightSource: String, CaseIterable {
    case manual, health

    func title(language: String) -> String {
        switch self {
        case .manual: return language == "de" ? "Manuell" : "Manual"
        case .health: return "Apple Health"
        }
    }
}

/// Lets Apple Health keep the weight current, without taking the manual entry
/// away.
///
/// Weight drives the BMR, and a figure typed in once at onboarding drifts out
/// of date silently — the number keeps looking right while the calculation
/// behind it slowly stops being. Anyone who owns a scale that writes to Health
/// gets that fixed for free; anyone who does not keeps exactly what they had.
struct WeightSourceSetting: View {
    let accent: Color
    let language: String
    let healthKitAuthorized: Bool
    let healthWeightKg: Double?
    let healthWeightDate: Date?
    @Binding var source: String

    private var caption: String? {
        guard source == WeightSource.health.rawValue else { return nil }
        guard healthKitAuthorized else {
            return language == "de"
                ? "Apple Health ist nicht verbunden — das Gewicht bleibt manuell."
                : "Apple Health is not connected — weight stays manual."
        }
        guard let kg = healthWeightKg else {
            return language == "de"
                ? "In Apple Health steht noch kein Gewicht."
                : "No weight recorded in Apple Health yet."
        }
        let stamp = healthWeightDate?.formatted(.dateTime.day().month().year()) ?? "–"
        return String(format: language == "de" ? "%.1f kg, zuletzt %@" : "%.1f kg, last %@", kg, stamp)
    }

    var body: some View {
        SettingsRow(icon: "figure.stand",
                    label: language == "de" ? "Gewicht" : "Weight",
                    accent: accent,
                    caption: caption) {
            SettingsSegments(
                options: WeightSource.allCases.map { (value: $0.rawValue, title: $0.title(language: language)) },
                accent: accent,
                selection: $source
            )
        }
    }
}

// MARK: - Daily goal

/// An optional target for the day's burn.
///
/// Caloric measures what a body spends; it does not net that against what goes
/// in, and a goal does not change that. This is a line to reach, not a budget
/// to stay under — which is why zero means "no goal" and the app says nothing
/// about it until one is set.
struct DailyGoalSetting: View {
    let accent: Color
    let language: String
    /// What the user has actually been burning, when the app knows. Rounded to
    /// the nearest 50 so it lands on the slider's own steps.
    let suggestedKcal: Double?
    @Binding var goalKcal: Double

    private var startingPoint: Double {
        guard let suggested = suggestedKcal, suggested > 0 else { return 2500 }
        return min(5000, max(1200, (suggested / 50).rounded() * 50))
    }

    private var isOn: Binding<Bool> {
        Binding(get: { goalKcal > 0 }, set: { goalKcal = $0 ? startingPoint : 0 })
    }

    var body: some View {
        VStack(spacing: 10) {
            SettingsRow(icon: "target",
                        label: language == "de" ? "Tagesziel" : "Daily goal",
                        accent: accent,
                        caption: goalKcal > 0
                            ? nil
                            : (language == "de"
                               ? "Ohne Ziel vergleicht der Ring mit deinem eigenen Schnitt."
                               : "Without a goal the ring compares against your own average.")) {
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(accent)
            }

            if goalKcal > 0 {
                HStack(spacing: 12) {
                    Text("\(Int(goalKcal)) kcal")
                        .font(.poppins(size: 17, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 96, alignment: .leading)

                    Slider(value: $goalKcal, in: 1200...5000, step: 50)
                        .tint(accent)
                }
                .padding(.leading, 40)
            }
        }
    }
}

// MARK: - Apple Health status

struct HealthStatusSetting: View {
    let accent: Color
    let language: String
    let isAuthorized: Bool
    let onConnect: () -> Void

    var body: some View {
        SettingsRow(icon: "heart.text.square.fill",
                    label: "Apple Health",
                    accent: accent,
                    caption: isAuthorized
                        ? (language == "de" ? "Verbunden" : "Connected")
                        : (language == "de"
                           ? "Ohne Health fehlen Schritte, Herzfrequenz und Workouts."
                           : "Without Health there are no steps, heart rate or workouts.")) {
            if isAuthorized {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.segNEAT)
            } else {
                Button(action: onConnect) {
                    Text(language == "de" ? "Verbinden" : "Connect")
                        .font(.poppins(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Export

/// A day per row, the same decomposition the dashboard shows.
///
/// Plain CSV rather than a report: the point is that the data can leave the
/// app at all, and a spreadsheet is where anyone would take it next.
enum HistoryExport {

    static func csv(history: [String: HealthKitImportService.DaySnapshot]) -> String {
        var lines = ["date;steps;distance_km;stand_minutes;resting_hr;avg_hr;sleep_hours;workouts;workout_minutes"]

        for key in history.keys.sorted() {
            guard let day = history[key] else { continue }
            let a = day.activity
            let workoutMinutes = day.workouts.reduce(0.0) { $0 + $1.duration } / 60.0
            let sleepHours = (day.sleep?.totalAsleepSeconds ?? 0) / 3600.0
            let fields: [String] = [
                key,
                "\(a.steps)",
                String(format: "%.2f", a.distanceMeters / 1000),
                String(format: "%.0f", a.standTimeMinutes),
                a.restingHeartRate.map { String(format: "%.0f", $0) } ?? "",
                a.avgHeartRateWaking.map { String(format: "%.0f", $0) } ?? "",
                String(format: "%.2f", sleepHours),
                "\(day.workouts.count)",
                String(format: "%.0f", workoutMinutes)
            ]
            lines.append(fields.joined(separator: ";"))
        }
        return lines.joined(separator: "\n")
    }

    /// Written to a real file because ShareLink can hand over a URL but not a
    /// string that should arrive as a document.
    static func writeCSV(history: [String: HealthKitImportService.DaySnapshot]) -> URL? {
        let name = "caloric-export-\(DateKey.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try csv(history: history).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - About

struct AboutSetting: View {
    let language: String

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    var body: some View {
        HStack {
            Text(language == "de" ? "Version" : "Version")
                .font(.poppins(size: 13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(version)
                .font(.poppins(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
