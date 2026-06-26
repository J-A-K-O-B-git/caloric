//
//  MainTabView.swift
//  caloric
//
//  Tab-Struktur: Übersicht · Daily Journal · Einstellungen
//

import SwiftUI

struct MainTabView: View {
    let accentBlue: Color
    let language: String
    let finalBMR: Double
    let sleepHoursValue: Double
    let leanBodyMass: Double
    let userAge: Int
    let selectedGender: String?
    let noConditionText: String
    let femaleText: String

    @Binding var accountUsername: String
    @Binding var birthDate: Date
    @Binding var weightText: String
    @Binding var weightUnit: String
    @Binding var heightText: String
    @Binding var heightUnit: String
    @Binding var bodyFatText: String
    @Binding var knowsBodyFat: Bool?
    @Binding var sleepHours: Double
    @Binding var selectedConditions: Set<String>
    @Binding var metabolismFactor: Double

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var journalStore = JournalStore()
    @State private var healthKit = HealthKitImportService()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            DashboardView(
                accentBlue: accentBlue,
                language: language,
                finalBMR: finalBMR,
                sleepHoursValue: sleepHoursValue,
                leanBodyMass: leanBodyMass,
                userAge: userAge,
                selectedGender: selectedGender,
                noConditionText: noConditionText,
                femaleText: femaleText,
                birthDate: $birthDate,
                weightText: $weightText,
                weightUnit: $weightUnit,
                heightText: $heightText,
                heightUnit: $heightUnit,
                bodyFatText: $bodyFatText,
                knowsBodyFat: $knowsBodyFat,
                sleepHours: $sleepHours,
                selectedConditions: $selectedConditions,
                metabolismFactor: $metabolismFactor,
                selectedDate: $selectedDate
            )
            .tabItem {
                Label(language == "de" ? "Übersicht" : "Overview",
                      systemImage: "square.grid.2x2.fill")
            }

            DailyJournalView(
                accentBlue: accentBlue,
                language: language,
                selectedGender: selectedGender,
                femaleText: femaleText,
                selectedDate: $selectedDate
            )
            .tabItem {
                Label("Journal", systemImage: "book.pages.fill")
            }

            SettingsView(
                accentBlue: accentBlue,
                language: language,
                userAge: userAge,
                accountUsername: $accountUsername,
                birthDate: $birthDate
            )
            .tabItem {
                Label(language == "de" ? "Einstellungen" : "Settings",
                      systemImage: "gearshape.fill")
            }
        }
        .tint(accentBlue)
        .ignoresSafeArea()
        .environment(journalStore)
        .environment(healthKit)
        .task {
            healthKit.modelContext = modelContext
            try? await healthKit.requestAuthorization()
        }
    }
}
