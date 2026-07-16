//
//  DailyJournalView.swift
//  caloric
//
//  Separater Tab für das tägliche Tracking (Menstruation, Krankheit, Makros)
//

import SwiftUI
import Speech
import AVFoundation

struct DailyJournalView: View {

    // MARK: - Nested Types

    private typealias SickEnergyLevel = TDEECalculationService.JournalInputs.SickEnergyLevel
    private typealias FeverLevel      = TDEECalculationService.JournalInputs.FeverLevel

    // MARK: - Props

    let accentBlue: Color
    let language: String
    let selectedGender: String?
    let femaleText: String
    @Binding var selectedDate: Date

    // MARK: - State

    @State private var menstruationActive: Bool? = nil

    // Krankheit
    @State private var sickToggle      = false
    @State private var sickEnergyLevel: SickEnergyLevel? = nil
    @State private var feverLevel:      FeverLevel?       = nil

    // Koffein
    @State private var caffeineText: String = "0"
    @State private var caffeineInfoExpanded = false
    @State private var showAddDrinkSheet = false
    @State private var newDrinkName = ""
    @State private var newDrinkCaffeine = ""
    @FocusState private var caffeineFocused: Bool

    // Makros
    @State private var selectedMeal: String? = "breakfast" // Default to breakfast for better UX
    @State private var proteinByMeal:  [String: String] = ["breakfast": "", "lunch": "", "dinner": "", "daily": ""]
    @State private var carbsByMeal:    [String: String] = ["breakfast": "", "lunch": "", "dinner": "", "daily": ""]
    @State private var fatByMeal:      [String: String] = ["breakfast": "", "lunch": "", "dinner": "", "daily": ""]

    // KI-Tracking State
    @State private var aiInputText: String = ""
    @State private var aiIsLoading: Bool = false
    @State private var aiErrorMessage: String? = nil

    // Speech State
    @State private var isRecording = false
    @State private var audioEngine = AVAudioEngine()
    @State private var request = SFSpeechAudioBufferRecognitionRequest()
    @State private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))

    private enum MacroField: Hashable {
        case protein(String), carbs(String), fat(String)
    }
    @FocusState private var macroFocus: MacroField?

    @State private var showSavedBadge = false
    @State private var showCalendarPicker = false
    @State private var confirmPulse = false
    
    @Environment(JournalStore.self) private var store
    @Environment(HealthKitImportService.self) private var healthKit
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    private var macroKeyboardLabel: String {
        if caffeineFocused {
            let v = Int(caffeineText) ?? 0
            return v == 0 ? "– mg" : "\(v) mg Koffein"
        }
        switch macroFocus {
        case .protein(let m):
            let v = proteinByMeal[m] ?? ""
            return v.isEmpty ? "–" : "\(v) g Protein"
        case .carbs(let m):
            let v = carbsByMeal[m] ?? ""
            return v.isEmpty ? "–" : "\(v) g \(language == "de" ? "Kohlenhydrate" : "Carbs")"
        case .fat(let m):
            let v = fatByMeal[m] ?? ""
            return v.isEmpty ? "–" : "\(v) g \(language == "de" ? "Fett" : "Fat")"
        case nil: return ""
        }
    }

    // MARK: - Store Sync

    private func loadFromStore() {
        let e = store.entry(for: selectedDate)
        menstruationActive = e.menstruationActive
        sickToggle = e.sickActive
        sickEnergyLevel = e.sickEnergyLevel
        feverLevel = e.feverLevel == .none ? nil : e.feverLevel
        caffeineText = e.caffeineMg == 0 ? "0" : "\(Int(e.caffeineMg))"
        proteinByMeal = [
            "breakfast": e.proteinByMeal["breakfast"].map { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "lunch":     e.proteinByMeal["lunch"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "dinner":    e.proteinByMeal["dinner"].map    { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "daily":     e.proteinByMeal["daily"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? ""
        ]
        carbsByMeal = [
            "breakfast": e.carbsByMeal["breakfast"].map { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "lunch":     e.carbsByMeal["lunch"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "dinner":    e.carbsByMeal["dinner"].map    { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "daily":     e.carbsByMeal["daily"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? ""
        ]
        fatByMeal = [
            "breakfast": e.fatByMeal["breakfast"].map { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "lunch":     e.fatByMeal["lunch"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "dinner":    e.fatByMeal["dinner"].map    { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "daily":     e.fatByMeal["daily"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? ""
        ]
    }

        private var isFutureDate: Bool {
        selectedDate > Calendar.current.startOfDay(for: Date())
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            CaloricBackground()

            journalScrollView

            // Floating Confirm Button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    confirmButton
                }
                .padding(.trailing, 24)
                .padding(.bottom, 106)
            }
            .ignoresSafeArea(edges: .bottom)

            if showSavedBadge {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(language == "de" ? "Bestätigt" : "confirmed")
                                .font(.poppins(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))
                                .font(.poppins(size: 11, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 6)
                    )
                    .padding(.top, (UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?.windows.first?.safeAreaInsets.top ?? 50) + 6)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadFromStore() }
        .onChange(of: selectedDate) { _, _ in loadFromStore() }
        .sheet(isPresented: $showCalendarPicker) {
            calendarPickerSheet
        }
        .onChange(of: menstruationActive) { _, v in
            store.update(for: selectedDate) { $0.menstruationActive = v }
        }
        .onChange(of: sickToggle) { _, v in
            store.update(for: selectedDate) { $0.sickActive = v }
        }
        .onChange(of: sickEnergyLevel) { _, v in
            store.update(for: selectedDate) { $0.sickEnergyLevel = v }
        }
        .onChange(of: feverLevel) { _, v in
            store.update(for: selectedDate) { $0.feverLevel = v ?? .none }
        }
        .onChange(of: caffeineText) { _, v in
            store.update(for: selectedDate) { $0.caffeineMg = Double(v) ?? 0 }
        }
        .onChange(of: proteinByMeal) { _, v in
            store.update(for: selectedDate) { e in
                e.proteinByMeal = v.compactMapValues {
                    Double($0.replacingOccurrences(of: ",", with: "."))
                }
            }
        }
        .onChange(of: carbsByMeal) { _, v in
            store.update(for: selectedDate) { e in
                e.carbsByMeal = v.compactMapValues {
                    Double($0.replacingOccurrences(of: ",", with: "."))
                }
            }
        }
        .onChange(of: fatByMeal) { _, v in
            store.update(for: selectedDate) { e in
                e.fatByMeal = v.compactMapValues {
                    Double($0.replacingOccurrences(of: ",", with: "."))
                }
            }
        }
    }

    // MARK: - Cards Section

    private var cardsSection: some View {
        VStack(spacing: 16) {
            if selectedGender == femaleText {
                MenstruationCard(
                    language: language,
                    menstruationActive: $menstruationActive,
                    accentBlue: accentBlue,
                    cardBackground: AnyView(cardBackground),
                    trackingToggle: { label, isSelected, tint, action in
                        AnyView(trackingToggle(label: label, isSelected: isSelected, tint: tint, action: action))
                    }
                )
            }
            
            SicknessCard(
                language: language,
                sickToggle: $sickToggle,
                sickEnergyLevel: $sickEnergyLevel,
                feverLevel: $feverLevel,
                accentBlue: accentBlue,
                cardBackground: AnyView(cardBackground),
                energyButton: { label, level in
                    AnyView(energyButton(label: label, icon: "", level: level))
                },
                feverButton: { label, sublabel, level, tint in
                    AnyView(feverButton(label: label, sublabel: sublabel, level: level, tint: tint))
                }
            )

            CaffeineCard(
                accentBlue: accentBlue,
                language: language,
                caffeineText: $caffeineText,
                caffeineInfoExpanded: $caffeineInfoExpanded,
                showAddDrinkSheet: $showAddDrinkSheet,
                caffeineFocused: $caffeineFocused,
                store: store,
                cardBackground: AnyView(cardBackground)
            )
            .sheet(isPresented: $showAddDrinkSheet) {
                addDrinkSheet
            }
            
            MacrosCard(
                language: language,
                accentBlue: accentBlue,
                selectedMeal: $selectedMeal,
                aiInputText: $aiInputText,
                aiIsLoading: $aiIsLoading,
                aiErrorMessage: $aiErrorMessage,
                proteinByMeal: $proteinByMeal,
                carbsByMeal: $carbsByMeal,
                fatByMeal: $fatByMeal,
                analyzeFoodWithAI: { Task { await analyzeFoodWithAI() } },
                copyYesterdayBreakfast: { copyYesterdayBreakfast() },
                isRecording: isRecording,
                startRecording: { startRecording() },
                stopRecording: { stopRecording() },
                macroInputField: { label, placeholder, text, focus, tint in
                    let field: MacroField
                    if let f = focus as? MacrosCardMacroField {
                        switch f {
                        case .protein(let m): field = .protein(m)
                        case .carbs(let m):   field = .carbs(m)
                        case .fat(let m):     field = .fat(m)
                        }
                    } else {
                        field = .protein("")
                    }
                    return AnyView(macroInputField(label: label, placeholder: placeholder, text: text, focusValue: field, tint: tint))
                },
                cardBackground: AnyView(cardBackground)
            )
        }

        .padding(.horizontal, 20)
        .disabled(isFutureDate)
        .opacity(isFutureDate ? 0.45 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFutureDate)
    }

    private var addDrinkSheet: some View {
        NavigationStack {
            ZStack {
                CaloricBackground()
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(language == "de" ? "Name des Getränks" : "Drink Name")
                            .font(.poppins(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        TextField(language == "de" ? "z.B. Mein Special Tee" : "e.g. My Special Tea", text: $newDrinkName)
                            .font(.poppins(size: 18, weight: .semibold))
                            .padding()
                            .background(Theme.fieldFill)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(language == "de" ? "Koffeingehalt (mg)" : "Caffeine content (mg)")
                            .font(.poppins(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        TextField("0", text: $newDrinkCaffeine)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .font(.poppins(size: 18, weight: .semibold))
                            .padding()
                            .background(Theme.fieldFill)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Spacer()
                    
                    Button {
                        if let mg = Int(newDrinkCaffeine), !newDrinkName.isEmpty {
                            store.addCustomDrink(name: newDrinkName, caffeineMg: mg)
                            newDrinkName = ""
                            newDrinkCaffeine = ""
                            showAddDrinkSheet = false
                        }
                    } label: {
                        Text(language == "de" ? "Getränk speichern" : "Save Drink")
                            .font(.poppins(size: 16, weight: .semibold))
                            .foregroundStyle(accentBlue)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(accentBlue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accentBlue.opacity(0.2), lineWidth: 1))
                    }
                    .disabled(newDrinkName.isEmpty || Int(newDrinkCaffeine) == nil)
                    .opacity(newDrinkName.isEmpty || Int(newDrinkCaffeine) == nil ? 0.5 : 1.0)
                }
                .padding(24)
            }
            .navigationTitle(language == "de" ? "Neues Getränk" : "New Drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language == "de" ? "Abbrechen" : "Cancel") {
                        showAddDrinkSheet = false
                    }
                    .foregroundStyle(accentBlue)
                }
            }
        }
    }

    private var journalScrollView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack {
                    Text("Daily Journal")
                        .font(.poppins(size: LayoutMetrics.titleFontSize, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(accentBlue)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(Theme.card)
                                        .overlay(Circle().strokeBorder(Theme.cardStroke, lineWidth: 1))
                                )
                        }
                        .buttonStyle(SpringyButtonStyle())

                        Button {
                            showCalendarPicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(accentBlue)
                                Text(selectedDateString)
                                    .font(.poppins(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Theme.card)
                                    .overlay(Capsule().strokeBorder(Theme.cardStroke, lineWidth: 1))
                                    .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 4)
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(SpringyButtonStyle())

                        let maxDate = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date()))!
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                                if next <= maxDate {
                                    selectedDate = next
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(selectedDate >= maxDate ? accentBlue.opacity(0.3) : accentBlue)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(Theme.card)
                                        .overlay(Circle().strokeBorder(Theme.cardStroke, lineWidth: 1))
                                )
                        }
                        .buttonStyle(SpringyButtonStyle())
                        .disabled(selectedDate >= maxDate)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 4)
            
        ScrollView {
            VStack(spacing: LayoutMetrics.sectionSpacing) {
                if isFutureDate {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(accentBlue.opacity(0.6))
                        Text(language == "de"
                             ? "Einträge für zukünftige Tage gesperrt"
                             : "Entries locked for future dates")
                            .font(.poppins(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .glassCard(16)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
                }
                
                cardsSection
                
                Spacer().frame(height: (140 * LayoutMetrics.scale).rounded())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Text(macroKeyboardLabel)
                    .font(.poppins(size: 15, weight: .semibold))
                    .foregroundStyle(accentBlue)
                Spacer()
                Button(language == "de" ? "Fertig" : "Done") {
                    macroFocus = nil
                    caffeineFocused = false
                }
                .font(.poppins(size: 15, weight: .semibold))
                .foregroundStyle(accentBlue)
            }
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedDateString: String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.locale = Locale(identifier: language == "de" ? "de_DE" : "en_US")
        return f.string(from: selectedDate)
    }

    private var calendarPickerSheet: some View {
        NavigationStack {
            ZStack {
                CaloricBackground()
                VStack(spacing: 0) {
                    DatePicker(
                        "",
                        selection: $selectedDate,
                        in: ...Calendar.current.date(byAdding: .day, value: 7, to: Date())!,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .tint(accentBlue)
                    .padding()
                    .glassCard(20)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            selectedDate = Calendar.current.startOfDay(for: Date())
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                            Text(language == "de" ? "Zurück zu Heute" : "Back to Today")
                        }
                        .font(.poppins(size: 16, weight: .semibold))
                        .foregroundStyle(accentBlue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(accentBlue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accentBlue.opacity(0.2), lineWidth: 1))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    Spacer()
                }
            }
            .navigationTitle(language == "de" ? "Datum wählen" : "Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(language == "de" ? "Fertig" : "Done") {
                        showCalendarPicker = false
                    }
                    .foregroundStyle(accentBlue)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.visible)
    }

    struct SpringyButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .opacity(configuration.isPressed ? 0.8 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }

    // MARK: - Confirm Button (Sticky)

            private var confirmButton: some View {
        Button {
            macroFocus = nil
            caffeineFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { showSavedBadge = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.4)) { showSavedBadge = false }
            }
        } label: {
            ZStack {
                // Pulsing glow effect
                Circle()
                    .fill(accentBlue)
                    .frame(width: 62, height: 62)
                    .scaleEffect(confirmPulse ? 1.25 : 1.0)
                    .opacity(confirmPulse ? 0.0 : 0.3)
                
                Circle()
                    .fill(
                        LinearGradient(colors: [Theme.accentSky, accentBlue],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 62, height: 62)
                    .shadow(color: accentBlue.opacity(0.35), radius: 10, x: 0, y: 6)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                confirmPulse = true
            }
        }
        .disabled(isFutureDate)
        .opacity(isFutureDate ? 0.45 : 1.0)
    }

        
    // MARK: - KI-Netzwerk-Logik
    
        private func analyzeFoodWithAI() async {
            let trimmed = aiInputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let meal = selectedMeal else { return }
            
            aiIsLoading = true
            aiErrorMessage = nil
            
            // 1. Dein funktionierender API-Key aus dem Terminal-Test
            let apiKey = Secrets.gcpApiKey
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key=\(apiKey)") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let payload: [String: Any] = [
                "systemInstruction": [
                    "parts": [
                        ["text": "Du bist ein präziser Ernährungsanalyst für die App Caloric. Analysiere die Mahlzeit des Nutzers. Schätze das Gesamtgewicht der Zutaten, falls keine genauen Grammangaben vorhanden sind. Berechne Protein, Kohlenhydrate und Fett in Gramm für die gesamte Mahlzeit. Antworte ausschließlich im vorgegebenen JSON-Schema ohne Erklärungen oder Markdown."]
                    ]
                ],
                "contents": [
                    ["parts": [["text": trimmed]]]
                ],
                "generationConfig": [
                    "responseMimeType": "application/json",
                    "responseSchema": [
                        "type": "OBJECT",
                        "properties": [
                            "protein": ["type": "NUMBER"],
                            "carbs": ["type": "NUMBER"],
                            "fat": ["type": "NUMBER"]
                        ],
                        "required": ["protein", "carbs", "fat"]
                    ]
                ]
            ]

            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let body = String(data: data, encoding: .utf8) ?? "–"
                    throw NSError(domain: "GeminiAPI", code: statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode): \(body)"])
                }
                
                // 3. Google API Wrapper-Strukturen für das Parsing
                struct GeminiResponse: Codable {
                    let candidates: [Candidate]
                }
                struct Candidate: Codable {
                    let content: Content
                }
                struct Content: Codable {
                    let parts: [Part]
                }
                struct Part: Codable {
                    let text: String
                }
                
                struct MacroValues: Codable {
                    let protein: Double
                    let carbs: Double
                    let fat: Double
                }
                
                // 4. Verschachteltes JSON decodieren
                let geminiResult = try JSONDecoder().decode(GeminiResponse.self, from: data)
                
                if let jsonString = geminiResult.candidates.first?.content.parts.first?.text,
                   let jsonData = jsonString.data(using: .utf8) {
                    
                    let result = try JSONDecoder().decode(MacroValues.self, from: jsonData)
                    
                    await MainActor.run {
                        // Werte runden und als String in deine TextFields eintragen
                        proteinByMeal[meal] = "\(Int(result.protein))"
                        carbsByMeal[meal]   = "\(Int(result.carbs))"
                        fatByMeal[meal]     = "\(Int(result.fat))"
                        
                        aiInputText = "" // Eingabefeld nach Erfolg leeren
                    }
                } else {
                    throw URLError(.cannotParseResponse)
                }
            } catch {
                await MainActor.run {
                    aiErrorMessage = error.localizedDescription
                }
            }
            
            aiIsLoading = false
        }
   

    // MARK: - Helpers

    private var cardBackground: some View {
        GlassCardBackground(cornerRadius: 20)
    }

    private func macroInputField(label: String, placeholder: String,
                                  text: Binding<String>, focusValue: MacroField, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.poppins(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                TextField(placeholder, text: text)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .focused($macroFocus, equals: focusValue)
                    .font(.poppins(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                Text("g")
                    .font(.poppins(size: 12, weight: .medium))
                    .foregroundStyle(tint.opacity(0.6))
            }
            
            // Integrated mini instrument bar for feedback
            let val = Double(text.wrappedValue.replacingOccurrences(of: ",", with: ".")) ?? 0
            let ref: Double = label.contains("Protein") ? 150 : (label.contains("Fat") || label.contains("Fett") ? 80 : 300)
            InstrumentProgressBar(progress: min(1.0, val / ref), color: tint, height: 3, showScale: false)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.15), lineWidth: 1))
        )
    }

    private func energyButton(label: String, icon: String, level: SickEnergyLevel) -> some View {
        let isSelected = sickEnergyLevel == level
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                sickEnergyLevel = isSelected ? nil : level
            }
        } label: {
            Text(label)
                .font(.poppins(size: 12, weight: .medium))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .foregroundStyle(isSelected ? .white : accentBlue)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? accentBlue : accentBlue.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(accentBlue.opacity(isSelected ? 0 : 0.2), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func feverButton(label: String, sublabel: String?, level: FeverLevel, tint: Color) -> some View {
        let isSelected = feverLevel == level
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                feverLevel = isSelected ? nil : level
            }
        } label: {
            VStack(spacing: 1) {
                Text(label)
                    .font(.poppins(size: 13, weight: .semibold))
                if let sub = sublabel {
                    Text(sub)
                        .font(.poppins(size: 10, weight: .regular))
                        .opacity(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundStyle(isSelected ? .white : tint)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? tint : tint.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(tint.opacity(isSelected ? 0 : 0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func trackingToggle(label: String, isSelected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.poppins(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? .white : tint)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? tint : tint.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(tint.opacity(isSelected ? 0 : 0.2), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    private func copyYesterdayBreakfast() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        let entry = store.entry(for: yesterday)
        
        if let p = entry.proteinByMeal["breakfast"] { proteinByMeal["breakfast"] = p == 0 ? "" : "\(Int(p))" }
        if let c = entry.carbsByMeal["breakfast"]   { carbsByMeal["breakfast"]   = c == 0 ? "" : "\(Int(c))" }
        if let f = entry.fatByMeal["breakfast"]     { fatByMeal["breakfast"]     = f == 0 ? "" : "\(Int(f))" }
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedMeal = "breakfast"
        }
    }

    private func startRecording() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                if authStatus == .authorized {
                    do {
                        try self.performStartRecording()
                    } catch {
                        self.aiErrorMessage = "Mic error"
                    }
                } else {
                    self.aiErrorMessage = "Mic permission denied"
                }
            }
        }
    }

    private func performStartRecording() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        request = SFSpeechAudioBufferRecognitionRequest()
        let inputNode = audioEngine.inputNode
        request.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
            if let result = result {
                self.aiInputText = result.bestTranscription.formattedString
            }
            if error != nil || result?.isFinal == true {
                self.stopRecording()
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.request.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request.endAudio()
        isRecording = false
    }
}
