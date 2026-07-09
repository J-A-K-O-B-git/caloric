//
//  SettingsView.swift
//  caloric
//
//  Stammdaten-Tab: statische Nutzerdaten (Name & Alter).
//  Fundament für künftige Systemeinstellungen.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    let accentBlue: Color
    let language: String
    let userAge: Int

    @Binding var accountUsername: String
    @Binding var birthDate: Date

    @State private var editingField: String? = nil
    @State private var nameDraft: String = ""
    @State private var showResetConfirmation = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    private var isDark: Bool { colorScheme == .dark }

    private var displayName: String {
        accountUsername.trimmingCharacters(in: .whitespaces).isEmpty
            ? (language == "de" ? "Dein Profil" : "Your Profile")
            : accountUsername
    }

    private var initial: String {
        let trimmed = accountUsername.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1)).uppercased()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                Spacer().frame(height: 50)

                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language == "de" ? "Einstellungen" : "Settings")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text(language == "de" ? "Deine Stammdaten" : "Your master data")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, Theme.Space.l)

                // Profil-Avatar
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(accentBlue.opacity(isDark ? 0.20 : 0.10))
                            .frame(width: 88, height: 88)
                        Circle()
                            .strokeBorder(accentBlue.opacity(isDark ? 0.34 : 0.18), lineWidth: 1)
                            .frame(width: 88, height: 88)
                        Text(initial)
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                            .foregroundStyle(accentBlue)
                    }
                    Text(displayName)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                // Stammdaten-Karte
                VStack(alignment: .leading, spacing: 10) {
                    Text(language == "de" ? "Persönliche Daten" : "Personal data")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                        .padding(.bottom, 2)

                    settingsRow(
                        icon: "person.fill",
                        label: language == "de" ? "Name" : "Name",
                        value: accountUsername.isEmpty ? (language == "de" ? "Hinzufügen" : "Add") : accountUsername,
                        isPlaceholder: accountUsername.isEmpty
                    ) {
                        nameDraft = accountUsername
                        editingField = "name"
                    }

                    settingsRow(
                        icon: "calendar",
                        label: language == "de" ? "Alter" : "Age",
                        value: "\(userAge) \(language == "de" ? "Jahre" : "years")",
                        isPlaceholder: false
                    ) {
                        editingField = "age"
                    }
                }
                .padding(Theme.Space.m)
                .background(cardBackground)
                .padding(.horizontal, Theme.Space.l)

                // Fundament-Hinweis (Platzhalter für künftige Settings)
                VStack(spacing: 8) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(accentBlue.opacity(0.5))
                    Text(language == "de"
                         ? "Weitere Einstellungen folgen bald."
                         : "More settings coming soon.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                        )
                        .foregroundStyle(accentBlue.opacity(isDark ? 0.22 : 0.16))
                )
                .padding(.horizontal, Theme.Space.l)

                // MARK: Developer reset
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .medium))
                        Text(language == "de" ? "Datenbank zurücksetzen" : "Reset database")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                    }
                    .foregroundStyle(.secondary.opacity(0.55))
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
                .confirmationDialog(
                    language == "de" ? "Onboarding zurücksetzen?" : "Reset onboarding?",
                    isPresented: $showResetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(language == "de" ? "Zurücksetzen" : "Reset", role: .destructive) {
                        profiles.forEach { modelContext.delete($0) }
                        try? modelContext.save()
                    }
                    Button(language == "de" ? "Abbrechen" : "Cancel", role: .cancel) { }
                } message: {
                    Text(language == "de"
                         ? "Das Profil wird gelöscht und das Onboarding startet neu."
                         : "The profile will be deleted and onboarding will restart.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CaloricBackground())
        .sheet(isPresented: Binding(
            get: { editingField != nil },
            set: { if !$0 { editingField = nil } }
        )) {
            editSheet()
        }
    }

    private var cardBackground: some View {
        GlassCardBackground(cornerRadius: Theme.Radius.card)
    }

    // MARK: - Stammdaten-Zeile

    private func settingsRow(icon: String, label: String, value: String,
                             isPlaceholder: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(accentBlue)
                    .frame(width: 26)
                Text(label)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(isPlaceholder ? accentBlue.opacity(0.7) : .secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accentBlue.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .fill(Theme.fieldFill)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        .strokeBorder(Theme.divider, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Edit-Sheets

    @ViewBuilder
    private func editSheet() -> some View {
        NavigationStack {
            Group {
                switch editingField {
                case "name": nameEditView
                case "age":  ageEditView
                default:     EmptyView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language == "de" ? "Fertig" : "Done") { editingField = nil }
                        .foregroundStyle(accentBlue)
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.light)
        .presentationDetents([.medium])
    }

    private var nameEditView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(accentBlue.opacity(isDark ? 0.20 : 0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: "person.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(accentBlue)
            }
            .padding(.top, 8)

            TextField(language == "de" ? "Dein Name" : "Your name", text: $nameDraft)
                #if os(iOS)
                .autocapitalization(.words)
                #endif
                .disableAutocorrection(true)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(accentBlue)
                .multilineTextAlignment(.center)
                .onChange(of: nameDraft) { accountUsername = nameDraft }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accentBlue.opacity(isDark ? 0.14 : 0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(accentBlue.opacity(isDark ? 0.28 : 0.14), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 24)

            Spacer()
        }
        .padding()
        .navigationTitle(language == "de" ? "Name ändern" : "Edit Name")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var ageEditView: some View {
        VStack(spacing: 20) {
            DatePicker("", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                #if os(iOS)
                .datePickerStyle(.wheel)
                #endif
                .labelsHidden()
        }
        .padding()
        .navigationTitle(language == "de" ? "Alter ändern" : "Edit Age")
        .navigationBarTitleDisplayMode(.inline)
    }
}
