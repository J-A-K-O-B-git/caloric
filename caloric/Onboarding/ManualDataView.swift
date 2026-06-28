//
//  ManualDataView.swift
//  caloric
//
//  Dedicated tab for health and manual data.
//

import SwiftUI
import HealthKit

struct ManualDataView: View {
    let accentBlue: Color
    let language: String
    let femaleText: String
    let noConditionText: String
    let selectedGender: String?
    let userAge: Int

    @Binding var weightText: String
    @Binding var weightUnit: String
    @Binding var heightText: String
    @Binding var heightUnit: String
    @Binding var bodyFatText: String
    @Binding var knowsBodyFat: Bool?
    @Binding var sleepHours: Double
    @Binding var selectedConditions: Set<String>
    @Binding var metabolismFactor: Double

    @State private var editingField: String? = nil
    @State private var editWeightKg: Int = 70
    @State private var editWeightLb: Int = 154
    @State private var editHeightCm: Int = 170
    @State private var editHeightFeet: Int = 5
    @State private var editHeightInches: Int = 9
    @State private var showBodyFatHelp = false
    @State private var thyroidCondition: String? = nil
    @State private var thyroidWellControlled: Bool? = nil
    @State private var selectedHypoSymptoms: Set<String> = []
    @State private var selectedHyperSymptoms: Set<String> = []
    @State private var hasPCOS: Bool? = nil
    @State private var pcosInsulinResistance: Bool? = nil
    @State private var selectedPCOSSymptoms: Set<String> = []

    @Environment(\.colorScheme) private var colorScheme
    @Environment(HealthKitImportService.self) private var healthKit

    private var isDark: Bool { colorScheme == .dark }
    private var t: Translations { Translations(language: language) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                Spacer().frame(height: 50)

                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language == "de" ? "Meine Daten" : "My Data")
                            .font(.custom("PingFangSC-Semibold", size: 28, relativeTo: .title))
                            .foregroundStyle(Theme.textPrimary)
                        Text(language == "de" ? "Aktivität & manuelle Werte" : "Activity & manual values")
                            .font(.custom("PingFangSC-Regular", size: 13, relativeTo: .callout))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 22)

                // 1) FITNESS-DATEN (HealthKit)
                VStack(spacing: 8) {
                    panelSectionHeader(
                        title: language == "de" ? "Fitness-Daten" : "Fitness Data",
                        subtitle: language == "de"
                            ? "Wird von Apple Health synchronisiert."
                            : "Synced automatically via Apple Health."
                    )
                    if healthKit.isAuthorized {
                        hkStatsGrid
                    }
                }

                // 2) MANUELL
                VStack(spacing: 4) {
                    panelSectionHeader(
                        title: language == "de" ? "Manuell" : "Manual",
                        subtitle: language == "de"
                            ? "Bitte aktuell halten, wenn sich etwas ändert."
                            : "Please keep up to date when something changes."
                    )
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        adjustTile(icon: "scalemass",
                                   label: language == "de" ? "Gewicht" : "Weight",
                                   value: "\(weightText) \(weightUnit)",
                                   field: "weight")
                        adjustTile(icon: "ruler",
                                   label: language == "de" ? "Größe" : "Height",
                                   value: "\(heightText) \(heightUnit)",
                                   field: "height")
                        adjustTile(icon: "percent",
                                   label: "KFA / BF%",
                                   value: bodyFatText.isEmpty ? "–" : "\(bodyFatText) %",
                                   field: "bodyFat")
                        adjustTile(icon: "waveform.path.ecg",
                                   label: language == "de" ? "Besonder-\nheiten" : "Conditions",
                                   value: {
                                       let active = selectedConditions.filter { $0 != noConditionText }
                                       if active.isEmpty { return "100 %" }
                                       return String(format: "%.0f %%", metabolismFactor * 100)
                                   }(),
                                   field: "conditions")
                    }
                    .padding(.horizontal, 16)
                }

                Spacer().frame(height: 40)
            }
        }
        .background(ObsidianBackground())
        .sheet(isPresented: Binding(
            get: { editingField != nil },
            set: { if !$0 { editingField = nil } }
        )) {
            editFieldSheet()
        }
    }

    private func panelSectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.custom("PingFangSC-Semibold", size: 16, relativeTo: .headline))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.custom("PingFangSC-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
    }

    private func adjustTile(icon: String, label: String, value: String, field: String) -> some View {
        Button {
            editingField = field
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(accentBlue)
                Text(value)
                    .font(.custom("PingFangSC-Semibold", size: 14, relativeTo: .callout))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.custom("PingFangSC-Regular", size: 11, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 8)
            .background(GlassCardBackground(cornerRadius: 16, tint: accentBlue, tintStrength: 0.10))
        }
        .buttonStyle(.plain)
    }

    private var hkStatsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            hkStatTile(icon: "figure.walk", iconColor: .orange, value: "\(healthKit.activity.steps)", unit: language == "de" ? "Schritte" : "Steps")
            hkStatTile(icon: "map", iconColor: accentBlue, value: String(format: "%.1f", healthKit.activity.distanceMeters / 1000), unit: "km")
            hkStatTile(icon: "moon.zzz.fill", iconColor: Color(red: 0.42, green: 0.35, blue: 0.95), value: healthKit.sleep.map { String(format: "%.1fh", $0.durationSeconds / 3600) } ?? "–", unit: language == "de" ? "Schlaf" : "Sleep")
            hkStatTile(icon: "dumbbell.fill", iconColor: Color(red: 0.20, green: 0.78, blue: 0.35), value: "\(healthKit.workouts.count)", unit: "Workouts")
        }
        .padding(.horizontal, 16)
    }

    private func hkStatTile(icon: String, iconColor: Color, value: String, unit: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundStyle(iconColor)
            Text(value).font(.custom("PingFangSC-Semibold", size: 17, relativeTo: .headline)).foregroundStyle(.primary).minimumScaleFactor(0.7).lineLimit(1)
            Text(unit).font(.custom("PingFangSC-Regular", size: 10, relativeTo: .caption2)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).background(GlassCardBackground(cornerRadius: 16))
    }

    @ViewBuilder
    private func editFieldSheet() -> some View {
        NavigationStack {
            Group {
                switch editingField {
                case "weight": weightEditView
                case "height": heightEditView
                default:      EmptyView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t.done) { editingField = nil }.foregroundStyle(accentBlue).fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark).presentationDetents([.medium, .large])
    }

    private var weightEditView: some View {
        VStack(spacing: 28) {
            Picker("Einheit", selection: $weightUnit) { Text("kg").tag("kg"); Text("lb").tag("lb") }
                .pickerStyle(.segmented).frame(width: 160)
            HStack(spacing: 4) {
                Spacer()
                Picker("", selection: weightUnit == "kg" ? $editWeightKg : $editWeightLb) {
                    if weightUnit == "kg" { ForEach(20...300, id: \.self) { v in Text("\(v)").tag(v) } }
                    else { ForEach(44...661, id: \.self) { v in Text("\(v)").tag(v) } }
                }
                .pickerStyle(.wheel).frame(width: 110, height: 180).clipped()
                .onChange(of: weightUnit == "kg" ? editWeightKg : editWeightLb) { 
                    weightText = weightUnit == "kg" ? "\(editWeightKg)" : "\(editWeightLb)"
                }
                Text(weightUnit).font(.custom("PingFangSC-Semibold", size: 24, relativeTo: .title2)).foregroundStyle(accentBlue).frame(width: 36, alignment: .leading)
                Spacer()
            }
        }
        .padding()
    }

    private var heightEditView: some View {
        VStack(spacing: 28) {
            Picker("Einheit", selection: $heightUnit) { Text("cm").tag("cm"); Text("ft").tag("ft") }
                .pickerStyle(.segmented).frame(width: 160)
            HStack(spacing: 4) {
                Spacer()
                Picker("", selection: $editHeightCm) { ForEach(100...230, id: \.self) { v in Text("\(v)").tag(v) } }
                .pickerStyle(.wheel).frame(width: 110, height: 180).clipped()
                .onChange(of: editHeightCm) { heightText = "\(editHeightCm)" }
                Text("cm").font(.custom("PingFangSC-Semibold", size: 24, relativeTo: .title2)).foregroundStyle(accentBlue).frame(width: 44, alignment: .leading)
                Spacer()
            }
        }
        .padding()
    }
}
