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
                        hkStatsList
                    }
                }

                // 2) MANUELL
                VStack(spacing: 8) {
                    panelSectionHeader(
                        title: language == "de" ? "Manuell" : "Manual",
                        subtitle: language == "de"
                            ? "Bitte aktuell halten, wenn sich etwas ändert."
                            : "Please keep up to date when something changes."
                    )
                    VStack(spacing: 12) {
                        adjustRow(icon: "scalemass",
                                   label: language == "de" ? "Gewicht" : "Weight",
                                   value: "\(weightText) \(weightUnit)",
                                   field: "weight")
                        adjustRow(icon: "ruler",
                                   label: language == "de" ? "Größe" : "Height",
                                   value: "\(heightText) \(heightUnit)",
                                   field: "height")
                        
                        let bf = Double(bodyFatText.replacingOccurrences(of: ",", with: ".")) ?? 0
                        adjustRow(icon: "percent",
                                   label: "KFA / BF%",
                                   value: bodyFatText.isEmpty ? "–" : "\(bodyFatText) %",
                                   field: "bodyFat",
                                   progress: min(1.0, bf / 40.0))
                        
                        adjustRow(icon: "waveform.path.ecg",
                                   label: language == "de" ? "Stoffwechsel" : "Conditions",
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

    private func adjustRow(icon: String, label: String, value: String, field: String, progress: Double? = nil) -> some View {
        Button {
            editingField = field
        } label: {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(accentBlue.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(accentBlue)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.custom("PingFangSC-Regular", size: 12, relativeTo: .caption))
                            .foregroundStyle(Theme.textSecondary)
                        Text(value)
                            .font(.custom("PingFangSC-Semibold", size: 17, relativeTo: .headline))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accentBlue.opacity(0.4))
                }
                
                if let p = progress {
                    InstrumentProgressBar(progress: p, color: accentBlue, height: 4, showScale: false)
                        .padding(.top, 4)
                }
            }
            .padding(14)
            .background(GlassCardBackground(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var hkStatsList: some View {
        VStack(spacing: 12) {
            let steps = Double(healthKit.activity.steps)
            dataRow(icon: "figure.walk", iconColor: .orange, label: language == "de" ? "Schritte" : "Steps", value: "\(healthKit.activity.steps)", unit: "", progress: min(1.0, steps / 10000))
            
            let dist = healthKit.activity.distanceMeters / 1000
            dataRow(icon: "map", iconColor: accentBlue, label: language == "de" ? "Distanz" : "Distance", value: String(format: "%.1f", dist), unit: "km", progress: min(1.0, dist / 8.0))
            
            let sleepH = (healthKit.sleep?.durationSeconds ?? 0) / 3600
            dataRow(icon: "moon.zzz.fill", iconColor: Color(red: 0.42, green: 0.35, blue: 0.95), label: language == "de" ? "Schlaf" : "Sleep", value: healthKit.sleep != nil ? String(format: "%.1f", sleepH) : "–", unit: "h", progress: min(1.0, sleepH / 8.0))
            
            let workouts = Double(healthKit.workouts.count)
            dataRow(icon: "dumbbell.fill", iconColor: Color(red: 0.20, green: 0.78, blue: 0.35), label: "Workouts", value: "\(Int(workouts))", unit: "", progress: min(1.0, workouts / 2.0))
        }
        .padding(.horizontal, 16)
    }

    private func dataRow(icon: String, iconColor: Color, label: String, value: String, unit: String, progress: Double? = nil) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.custom("PingFangSC-Regular", size: 12, relativeTo: .caption))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value)
                            .font(.custom("PingFangSC-Semibold", size: 18, relativeTo: .headline))
                            .foregroundStyle(Theme.textPrimary)
                        if !unit.isEmpty {
                            Text(unit)
                                .font(.custom("PingFangSC-Regular", size: 12, relativeTo: .caption))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                
                Spacer()
            }
            
            if let p = progress {
                InstrumentProgressBar(progress: p, color: iconColor, height: 4, showScale: true)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .background(GlassCardBackground(cornerRadius: 18))
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
