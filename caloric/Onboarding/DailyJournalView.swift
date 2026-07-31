//
//  DailyJournalView.swift
//  caloric
//
//  Separater Tab für das tägliche Tracking (Menstruation, Krankheit, Makros)
//

import SwiftUI
import Speech
import AVFoundation
import PhotosUI

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
    @State private var proteinByMeal:  [String: String] = ["breakfast": "", "lunch": "", "dinner": "", "snack": ""]
    @State private var carbsByMeal:    [String: String] = ["breakfast": "", "lunch": "", "dinner": "", "snack": ""]
    @State private var fatByMeal:      [String: String] = ["breakfast": "", "lunch": "", "dinner": "", "snack": ""]

    // KI-Tracking State
    @State private var aiInputText: String = ""
    @State private var aiIsLoading: Bool = false
    @State private var aiErrorMessage: String? = nil

    // Foto-Eingabe
    @State private var showPhotoSourceDialog = false
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var photoSelection: PhotosPickerItem? = nil
    /// Analysis waiting for the user's confirmation; nil while nothing is pending.
    @State private var pendingAnalysis: PendingAnalysis? = nil

    struct PendingAnalysis: Identifiable {
        let id = UUID()
        let items: [FoodItem]
        let meal: String
    }

    // Speech State
    @State private var isRecording = false
    @State private var audioEngine = AVAudioEngine()
    @State private var request = SFSpeechAudioBufferRecognitionRequest()
    @State private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))

    @FocusState private var macroFocus: MacrosCardMacroField?

    @State private var showSavedSummary = false
    @State private var showCalendarPicker = false
    
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
            "snack":     e.proteinByMeal["snack"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? ""
        ]
        carbsByMeal = [
            "breakfast": e.carbsByMeal["breakfast"].map { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "lunch":     e.carbsByMeal["lunch"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "dinner":    e.carbsByMeal["dinner"].map    { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "snack":     e.carbsByMeal["snack"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? ""
        ]
        fatByMeal = [
            "breakfast": e.fatByMeal["breakfast"].map { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "lunch":     e.fatByMeal["lunch"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "dinner":    e.fatByMeal["dinner"].map    { $0 == 0 ? "" : "\(Int($0))" } ?? "",
            "snack":     e.fatByMeal["snack"].map     { $0 == 0 ? "" : "\(Int($0))" } ?? ""
        ]
    }

    private var isFutureDate: Bool {
        selectedDate > Calendar.current.startOfDay(for: Date())
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            CaloricBackground()

            VStack(spacing: 0) {
                // STATIC HEADER (Aligned with DashboardView)
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(language == "de" ? "Dein Check-in" : "Daily Journal")
                            .font(.poppins(size: LayoutMetrics.titleFontSize, weight: .heavy))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }
                    dateNavigationRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: LayoutMetrics.cardSpacing) {
                        cardsSection
                        
                        Spacer().frame(height: 20)
                    }
                }
                .dataSyncObservers(
                    menstruationActive: $menstruationActive,
                    sickToggle: $sickToggle,
                    sickEnergyLevel: $sickEnergyLevel,
                    feverLevel: $feverLevel,
                    caffeineText: $caffeineText,
                    proteinByMeal: $proteinByMeal,
                    carbsByMeal: $carbsByMeal,
                    fatByMeal: $fatByMeal,
                    selectedDate: selectedDate,
                    store: store
                )
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    saveButton
                }
                .padding(.trailing, 24)
                .padding(.bottom, 106)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadFromStore() }
        .onChange(of: selectedDate) { _, _ in loadFromStore() }
        .sheet(isPresented: $showCalendarPicker) {
            calendarPickerSheet
        }
        .sheet(isPresented: $showSavedSummary) {
            checkinSummarySheet
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar { keyboardToolbar }
    }

    @ToolbarContentBuilder
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            if macroFocus != nil || caffeineFocused {
                Text(macroKeyboardLabel)
                    .font(.poppins(size: 14, weight: .semibold))
                    .foregroundStyle(accentBlue)
            }
            Spacer()
            Button(language == "de" ? "Fertig" : "Done") {
                macroFocus = nil
                caffeineFocused = false
            }
            .font(.poppins(size: 15, weight: .bold))
            .foregroundStyle(accentBlue)
        }
    }

    private var checkinSummarySheet: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accentBlue.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(accentBlue)
                }
                
                Text(language == "de" ? "Check-in gespeichert" : "Check-in saved")
                    .font(.poppins(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.top, 20)

            VStack(spacing: 12) {
                zustandSummary
                macrosSummary
            }
            
            Button {
                showSavedSummary = false
            } label: {
                Text(language == "de" ? "Super" : "Great")
                    .font(.poppins(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(accentBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
        }
        .padding(24)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvas)
    }

    @ViewBuilder
    private var zustandSummary: some View {
        if sickToggle {
            modalRow(icon: "bandage.fill", label: language == "de" ? "Krank" : "Sick today", tint: .orange)
        }
        if menstruationActive == true {
            modalRow(icon: "drop.fill", label: "Menstruation", tint: .pink)
        }
        let caffeine = Int(caffeineText) ?? 0
        if caffeine > 0 {
            modalRow(icon: "cup.and.saucer.fill", label: "\(caffeine) mg Koffein", tint: accentBlue)
        }
    }

    @ViewBuilder
    private var macrosSummary: some View {
        let meals = ["breakfast", "lunch", "dinner", "snack"]
        let totalProtein = meals.compactMap { Int(proteinByMeal[$0] ?? "") }.reduce(0, +)
        let totalCarbs   = meals.compactMap { Int(carbsByMeal[$0] ?? "")   }.reduce(0, +)
        let totalFat     = meals.compactMap { Int(fatByMeal[$0] ?? "")     }.reduce(0, +)
        if totalProtein + totalCarbs + totalFat > 0 {
            HStack(spacing: 10) {
                macroModalPill(label: "Protein", value: totalProtein, color: Theme.segNEAT)
                macroModalPill(label: language == "de" ? "KH" : "Carbs", value: totalCarbs, color: accentBlue)
                macroModalPill(label: language == "de" ? "Fett" : "Fat", value: totalFat, color: .orange)
            }
        }
    }

    private func modalRow(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(label)
                .font(.poppins(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func macroModalPill(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)g")
                .font(.poppins(size: 16, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.poppins(size: 10, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Cards Section

    private var cardsSection: some View {
        VStack(spacing: 16) {
            if selectedGender == femaleText {
                MenstruationCard(
                    language: language,
                    menstruationActive: $menstruationActive,
                    accentBlue: accentBlue
                )
            }
            
            SicknessCard(
                language: language,
                sickToggle: $sickToggle,
                sickEnergyLevel: $sickEnergyLevel,
                feverLevel: $feverLevel,
                accentBlue: accentBlue
            )

            CaffeineCard(
                accentBlue: accentBlue,
                language: language,
                caffeineText: $caffeineText,
                caffeineInfoExpanded: $caffeineInfoExpanded,
                showAddDrinkSheet: $showAddDrinkSheet,
                caffeineFocused: $caffeineFocused,
                store: store
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
                analyzeFoodFromPhoto: { showPhotoSourceDialog = true },
                copyYesterdayBreakfast: { copyYesterdayBreakfast() },
                isRecording: isRecording,
                startRecording: { startRecording() },
                stopRecording: { stopRecording() },
                macroFocus: $macroFocus
            )
            .confirmationDialog(
                language == "de" ? "Mahlzeit fotografieren" : "Photograph meal",
                isPresented: $showPhotoSourceDialog,
                titleVisibility: .visible
            ) {
                Button(language == "de" ? "Kamera" : "Camera") { showCamera = true }
                Button(language == "de" ? "Aus Fotos wählen" : "Choose from library") {
                    showPhotoLibrary = true
                }
                Button(language == "de" ? "Abbrechen" : "Cancel", role: .cancel) {}
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    Task { await analyzeFoodFromImage(image) }
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showPhotoLibrary, selection: $photoSelection, matching: .images)
            .onChange(of: photoSelection) { _, item in
                guard let item else { return }
                Task {
                    defer { photoSelection = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        aiErrorMessage = language == "de"
                            ? "Foto konnte nicht geladen werden."
                            : "Could not load photo."
                        return
                    }
                    await analyzeFoodFromImage(image)
                }
            }
            #endif
            .sheet(item: $pendingAnalysis) { pending in
                FoodConfirmSheet(
                    language: language,
                    accentBlue: accentBlue,
                    mealName: mealDisplayName(pending.meal),
                    items: pending.items,
                    onConfirm: { confirmed in
                        addAnalysis(confirmed, to: pending.meal)
                    }
                )
            }
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
                        Text(language == "de" ? "Hinzufügen" : "Add")
                    }
                    .buttonStyle(.caloricPrimary(fullWidth: true))
                }
                .padding(24)
            }
            .navigationTitle(language == "de" ? "Getränk hinzufügen" : "Add Drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language == "de" ? "Abbrechen" : "Cancel") { showAddDrinkSheet = false }
                }
            }
        }
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
    }

    private var dateNavigationRow: some View {
        let maxDate = Calendar.current.startOfDay(for: Date())
        return HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 34, height: 34)
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
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentBlue)
                    Text(selectedDateString)
                        .font(.poppins(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(Theme.card)
                        .overlay(Capsule().strokeBorder(Theme.cardStroke, lineWidth: 1))
                        .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 3)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(SpringyButtonStyle())
            
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
                    .foregroundStyle(Calendar.current.isDateInToday(selectedDate) ? Theme.textPrimary.opacity(0.25) : Theme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(Theme.card)
                            .overlay(Circle().strokeBorder(Theme.cardStroke, lineWidth: 1))
                    )
            }
            .buttonStyle(SpringyButtonStyle())
            .disabled(Calendar.current.isDateInToday(selectedDate))
        }
    }

    private func changeDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            if newDate <= Calendar.current.startOfDay(for: Date()) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    selectedDate = newDate
                }
            }
        }
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

    // MARK: - Save Button (Floating FAB)

    private var saveButton: some View {
        Button {
            macroFocus = nil
            caffeineFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                showSavedSummary = true
            }
        } label: {
            ZStack {
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
        .disabled(isFutureDate)
        .opacity(isFutureDate ? 0.45 : 1.0)
    }

    
    // MARK: - KI-Netzwerk-Logik

    @MainActor
    private func analyzeFoodWithAI() async {
        let trimmed = aiInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let meal = selectedMeal else { return }

        await runAnalysis(.text(trimmed), for: meal) {
            aiInputText = ""   // Eingabefeld nur bei Erfolg leeren
        }
    }

    #if os(iOS)
    @MainActor
    private func analyzeFoodFromImage(_ image: UIImage) async {
        guard let meal = selectedMeal else { return }
        guard let jpeg = image.jpegForAnalysis() else {
            aiErrorMessage = language == "de"
                ? "Foto konnte nicht verarbeitet werden."
                : "Could not process photo."
            return
        }
        await runAnalysis(.photo(jpeg), for: meal)
    }
    #endif

    /// Shared path for text and photo input: analyse, then hand the result to
    /// the confirmation sheet. Nothing is written to the journal until the user
    /// confirms — the model estimates portions and can be wrong.
    @MainActor
    private func runAnalysis(
        _ input: FoodAnalysisService.Input,
        for meal: String,
        onSuccess: () -> Void = {}
    ) async {
        aiIsLoading = true
        aiErrorMessage = nil
        defer { aiIsLoading = false }

        do {
            let items = try await FoodAnalysisService.analyze(input)
            guard !items.isEmpty else {
                aiErrorMessage = language == "de"
                    ? "Es wurde nichts Essbares erkannt."
                    : "Nothing edible was recognised."
                return
            }
            onSuccess()
            pendingAnalysis = PendingAnalysis(items: items, meal: meal)
        } catch {
            aiErrorMessage = error.localizedDescription
        }
    }

    /// Adds the confirmed macros to whatever the meal already holds.
    /// Adding a second item must not erase the first.
    @MainActor
    private func addAnalysis(_ items: [FoodItem], to meal: String) {
        proteinByMeal[meal] = addGrams(items.totalProtein, to: proteinByMeal[meal])
        carbsByMeal[meal]   = addGrams(items.totalCarbs,   to: carbsByMeal[meal])
        fatByMeal[meal]     = addGrams(items.totalFat,     to: fatByMeal[meal])
    }

    private func addGrams(_ added: Double, to existing: String?) -> String {
        let current = Double((existing ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
        let total = max(0, current + added)
        return total > 0 ? "\(Int(total.rounded()))" : ""
    }

    private func mealDisplayName(_ key: String) -> String {
        switch key {
        case "breakfast": return language == "de" ? "Frühstück"   : "Breakfast"
        case "lunch":     return language == "de" ? "Mittagessen" : "Lunch"
        case "dinner":    return language == "de" ? "Abendessen"  : "Dinner"
        default:          return language == "de" ? "Snack"       : "Snack"
        }
    }
   

    // MARK: - Helpers

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
            Task { @MainActor in
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

    @MainActor
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
            Task { @MainActor in
                if let result = result {
                    self.aiInputText = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self.stopRecording()
                }
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

    @MainActor
    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request.endAudio()
        isRecording = false
    }
}

// MARK: - Helper Modifiers

private extension View {
    func dataSyncObservers(
        menstruationActive: Binding<Bool?>,
        sickToggle: Binding<Bool>,
        sickEnergyLevel: Binding<TDEECalculationService.JournalInputs.SickEnergyLevel?>,
        feverLevel: Binding<TDEECalculationService.JournalInputs.FeverLevel?>,
        caffeineText: Binding<String>,
        proteinByMeal: Binding<[String: String]>,
        carbsByMeal: Binding<[String: String]>,
        fatByMeal: Binding<[String: String]>,
        selectedDate: Date,
        store: JournalStore
    ) -> some View {
        self
            .onChange(of: menstruationActive.wrappedValue) { _, v in store.update(for: selectedDate) { $0.menstruationActive = v } }
            .onChange(of: sickToggle.wrappedValue) { _, v in store.update(for: selectedDate) { $0.sickActive = v } }
            .onChange(of: sickEnergyLevel.wrappedValue) { _, v in store.update(for: selectedDate) { $0.sickEnergyLevel = v } }
            .onChange(of: feverLevel.wrappedValue) { _, v in store.update(for: selectedDate) { $0.feverLevel = v ?? .none } }
            .onChange(of: caffeineText.wrappedValue) { _, v in store.update(for: selectedDate) { $0.caffeineMg = Double(v) ?? 0 } }
            .onChange(of: proteinByMeal.wrappedValue) { _, v in
                store.update(for: selectedDate) { e in
                    e.proteinByMeal = v.compactMapValues { Double($0.replacingOccurrences(of: ",", with: ".")) }
                }
            }
            .onChange(of: carbsByMeal.wrappedValue) { _, v in
                store.update(for: selectedDate) { e in
                    e.carbsByMeal = v.compactMapValues { Double($0.replacingOccurrences(of: ",", with: ".")) }
                }
            }
            .onChange(of: fatByMeal.wrappedValue) { _, v in
                store.update(for: selectedDate) { e in
                    e.fatByMeal = v.compactMapValues { Double($0.replacingOccurrences(of: ",", with: ".")) }
                }
            }
    }
}
