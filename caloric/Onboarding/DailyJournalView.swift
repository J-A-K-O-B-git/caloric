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
    /// Needed to turn a described meal into grams — "high protein" has to
    /// mean something different at 60 kg than at 95 kg.
    let weightText: String
    let weightUnit: String
    /// Energy the estimate is anchored to. A weight-stable person eats roughly
    /// what they burn, so their own daily total is the honest starting point;
    /// the portion control is what moves a meal off that anchor.
    let estimatedDailyEnergy: Double
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

    @State private var showCalendarPicker = false
    /// 0 = full header, 1 = collapsed to the pinned date bar.
    @State private var headerCollapseProgress: Double = 0

    // MARK: - Check-in

    /// Date key of the last finished check-in. An explicit marker rather than
    /// "has anything been entered": answering no to every question is a
    /// complete check-in, and is indistinguishable from an untouched day.
    @AppStorage("journal.checkInCompletedFor") private var checkInCompletedFor = ""
    @State private var checkInStep = 0
    /// Single question opened from the summary, without walking the flow.
    @State private var editingStep: CheckInStep? = nil
    /// Whether the illness question has been touched at all. Until it has,
    /// neither pill is filled — a pre-selected "Nein" reads as an answer
    /// already given and stops anyone from reading the question.
    @State private var sicknessTouched = false
    /// The flow waits behind a start screen rather than beginning the moment
    /// the tab opens.
    @State private var checkInStarted = false

    enum CheckInStep: String, CaseIterable, Identifiable {
        case menstruation, sickness, caffeine, macros
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .menstruation: return "drop.fill"
            case .sickness:     return "thermometer.medium"
            case .caffeine:     return "cup.and.heat.waves.fill"
            case .macros:       return "fork.knife"
            }
        }

        func question(language: String) -> String {
            let de = language == "de"
            switch self {
            case .menstruation: return de ? "Hast du deine Periode?" : "Are you on your period?"
            case .sickness:     return de ? "Bist du krank?" : "Are you unwell?"
            case .caffeine:     return de ? "Wie viel Koffein heute?" : "How much caffeine today?"
            case .macros:       return de ? "Was hast du gegessen?" : "What did you eat?"
            }
        }

        /// Whether the card is tall enough that it should scroll on its own
        /// rather than taking the heading with it.
        var scrollsCardOnly: Bool {
            switch self {
            case .caffeine, .macros:      return true
            case .menstruation, .sickness: return false
            }
        }

        /// Why the question is asked. Every one of these costs a tap, and a
        /// tap is easier to give when the reason is on the screen.
        func reason(language: String) -> String {
            let de = language == "de"
            switch self {
            case .menstruation:
                return de ? "In der zweiten Zyklushälfte liegt dein Grundumsatz rund 5 % höher."
                          : "Your basal rate runs about 5 % higher in the luteal phase."
            case .sickness:
                return de ? "Fieber treibt den Grundumsatz um 10 bis 18 % nach oben."
                          : "A fever pushes basal burn up by 10 to 18 %."
            case .caffeine:
                return de ? "Koffein hebt den Umsatz leicht an — bis zu 60 kcal am Tag."
                          : "Caffeine lifts expenditure slightly — up to 60 kcal a day."
            case .macros:
                return de ? "Die Verdauung ist nach Grundumsatz und Alltag der größte Posten des Tages."
                          : "Digestion is the third largest part of your day."
            }
        }
    }

    /// Steps in order, menstruation only where it applies.
    private var checkInSteps: [CheckInStep] {
        selectedGender == femaleText
            ? CheckInStep.allCases
            : CheckInStep.allCases.filter { $0 != .menstruation }
    }

    /// Whether the current slide still needs "Weiter" and "Überspringen".
    ///
    /// A slide that advances on the answer needs neither — the tap is the
    /// answer and the continuation at once. Illness is the one that changes
    /// its mind: saying yes unfolds the energy and fever questions, and from
    /// that moment there is something to confirm, so the footer returns.
    private var currentStepNeedsFooter: Bool {
        let steps = checkInSteps
        guard checkInStep >= 0, checkInStep < steps.count else { return true }
        switch steps[checkInStep] {
        case .menstruation:      return false
        // Confirmed rather than auto-advanced: illness is the answer people
        // most often tap by accident on the way past.
        case .sickness:          return true
        case .caffeine, .macros: return true
        }
    }

    private var checkInIsDone: Bool {
        checkInCompletedFor == DateKey.string(from: selectedDate)
    }

    /// The flow runs for today only. A past day is something you correct, not
    /// something you check in for, so those open straight into the summary.
    private var showsCheckInFlow: Bool {
        Calendar.current.isDateInToday(selectedDate) && !checkInIsDone && !isFutureDate
    }
    
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

    // MARK: - Mahlzeiten in Worten

    private var weightKg: Double {
        MeasurementParsing.weightKg(text: weightText, unit: weightUnit)
    }

    /// Descriptions per meal for the selected day, persisted as JSON so the
    /// chips still show what was picked after a relaunch. Keyed by date: the
    /// grams they produce are stored separately and would otherwise be
    /// impossible to trace back to the words that made them.
    @AppStorage("journal.mealDescriptions") private var mealDescriptionsRaw = "{}"

    private func mealDescriptions() -> [String: MealEstimator.Description] {
        guard let data = mealDescriptionsRaw.data(using: .utf8),
              let all = try? JSONDecoder().decode(
                  [String: [String: MealEstimator.Description]].self, from: data)
        else { return [:] }
        return all[DateKey.string(from: selectedDate)] ?? [:]
    }

    func mealDescription(_ meal: MealEstimator.Meal) -> MealEstimator.Description {
        mealDescriptions()[meal.rawValue] ?? MealEstimator.Description()
    }

    /// Writes the description and immediately the grams it implies, so the
    /// rest of the app keeps reading macros from the one place it always has.
    func setMealDescription(_ description: MealEstimator.Description,
                            for meal: MealEstimator.Meal) {
        var all: [String: [String: MealEstimator.Description]] = [:]
        if let data = mealDescriptionsRaw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(
               [String: [String: MealEstimator.Description]].self, from: data) {
            all = decoded
        }
        let key = DateKey.string(from: selectedDate)
        var day = all[key] ?? [:]
        day[meal.rawValue] = description
        all[key] = day

        // Thirty days is as far back as anything else in the app looks.
        let cutoff = Calendar.current.date(byAdding: .day, value: -30,
                                           to: Calendar.current.startOfDay(for: Date()))
        if let cutoff {
            all = all.filter { (DateKey.date(from: $0.key) ?? .distantPast) >= cutoff }
        }
        if let data = try? JSONEncoder().encode(all),
           let json = String(data: data, encoding: .utf8) {
            mealDescriptionsRaw = json
        }

        applyEstimate(description, to: meal)
    }

    private func applyEstimate(_ description: MealEstimator.Description,
                               to meal: MealEstimator.Meal) {
        guard !description.isUntouched else { return }
        let m = MealEstimator.macros(
            for: description,
            meal: meal,
            dailyEnergyKcal: estimatedDailyEnergy,
            weightKg: weightKg
        )
        proteinByMeal[meal.rawValue] = "\(Int(m.proteinG.rounded()))"
        carbsByMeal[meal.rawValue]   = "\(Int(m.carbsG.rounded()))"
        fatByMeal[meal.rawValue]     = "\(Int(m.fatG.rounded()))"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            CaloricBackground()

            if showsCheckInFlow {
                // A check-in is a focused task: no collapsing header, no page
                // to scroll past, just the question in front of you.
                if checkInStarted {
                    checkInFlow.transition(.opacity)
                } else {
                    checkInStart.transition(.opacity)
                }
            } else {
                journalOverview
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: showsCheckInFlow)
        .animation(.easeInOut(duration: 0.28), value: checkInStarted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Attached here rather than to the overview: the flow edits the same
        // values, and left below the switch nothing typed in a slide would
        // ever reach the store.
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
        .scrollDismissesKeyboard(.interactively)
        .toolbar { keyboardToolbar }
        .onAppear { loadFromStore() }
        .onChange(of: selectedDate) { _, _ in
            loadFromStore()
            checkInStep = 0
            // Otherwise stepping to another day would drop straight into
            // question one, having skipped the doorstep the gate exists for.
            checkInStarted = false
            sicknessTouched = false
        }
        .sheet(item: $editingStep) { checkInEditSheet($0) }
        .sheet(isPresented: $showCalendarPicker) {
            calendarPickerSheet
        }
    }

    private var journalOverview: some View {
        ZStack {
            // Header scrolls with the content instead of sitting above the
            // ScrollView, so the page simply runs top to bottom.
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(language == "de" ? "Dein Check-in" : "Daily Journal")
                                .font(.poppins(size: LayoutMetrics.titleFontSize, weight: .heavy))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        .frame(height: 40)
                        dateNavigationRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                    .opacity(1 - headerCollapseProgress)
                    .offset(y: -headerCollapseProgress * 10)
                    .scaleEffect(1 - headerCollapseProgress * 0.04, anchor: .topLeading)
                    .allowsHitTesting(headerCollapseProgress < 0.5)
                    .animation(.easeOut(duration: 0.12), value: headerCollapseProgress)

                    VStack(spacing: LayoutMetrics.cardSpacing) {
                        checkInSummary

                        Spacer().frame(height: 20)
                    }
                }
            }
            // Rounded before it reaches state so this body is not re-evaluated
            // on every scroll frame — see the same treatment on the dashboard.
            .onScrollGeometryChange(for: Double.self) { geometry in
                let travelled = geometry.contentOffset.y + geometry.contentInsets.top
                let raw = Double(travelled / Self.headerCollapseDistance)
                let clamped = min(max(raw, 0), 1)
                let steps = Self.headerCollapseSteps
                return (clamped * steps).rounded() / steps
            } action: { _, newValue in
                headerCollapseProgress = newValue
            }
            .collapsingHeaderFade(progress: headerCollapseProgress)

            pinnedHeaderRow
        }
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

    /// All four cards, or a single one when the check-in flow asks for one
    /// question at a time.
    ///
    /// Filtered in place rather than split into four properties: every card
    /// carries its own sheets and pickers, and moving those would have meant
    /// re-attaching each one somewhere it could fire twice.
    @ViewBuilder
    private func cardsSection(only step: CheckInStep? = nil) -> some View {
        VStack(spacing: 16) {
            if step == nil || step == .menstruation, selectedGender == femaleText {
                MenstruationCard(
                    language: language,
                    menstruationActive: $menstruationActive,
                    accentBlue: accentBlue,
                    showsHeader: step == nil,
                    onAnswered: step == nil ? nil : { advanceCheckIn() }
                )
            }
            
            if step == nil || step == .sickness {
            SicknessCard(
                language: language,
                showsHeader: step == nil,
                hasAnswer: step == nil || sicknessTouched,
                onAnswered: step == nil ? nil : { sicknessTouched = true },
                sickToggle: $sickToggle,
                sickEnergyLevel: $sickEnergyLevel,
                feverLevel: $feverLevel,
                accentBlue: accentBlue
            )
            }

            if step == nil || step == .caffeine {
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
            }

            if step == nil || step == .macros {
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
                macroFocus: $macroFocus,
                mealDescription: { mealDescription($0) },
                setMealDescription: { setMealDescription($0, for: $1) }
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
        }

        .padding(.horizontal, 20)
        .disabled(isFutureDate)
        .opacity(isFutureDate ? 0.45 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFutureDate)
    }

    // MARK: - Check-in Start

    /// The doorstep. Opening a tab straight into question one leaves no moment
    /// to decide whether now is the time — and a check-in you were pushed into
    /// is one you abandon on slide two.
    private var checkInStart: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.accentGradient.opacity(0.14))
                    .frame(width: 108, height: 108)
                Image(systemName: "checklist")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Theme.accentGradient)
            }

            Text(language == "de" ? "Dein Check-in" : "Your check-in")
                .font(.poppins(size: 28, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 26)

            Text(checkInStartDateLine)
                .font(.poppins(size: 13, weight: .medium))
                .foregroundStyle(accentBlue)
                .padding(.top, 4)

            Text(language == "de"
                 ? "\(checkInSteps.count) kurze Fragen. Danach weiß Caloric, was deinen Tag über die Bewegung hinaus geprägt hat."
                 : "\(checkInSteps.count) short questions. Then Caloric knows what shaped your day beyond movement.")
                .font(.poppins(size: 14, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 34)
                .padding(.top, 12)

            // What is coming, so the commitment is visible before it is made.
            HStack(spacing: 10) {
                ForEach(checkInSteps) { step in
                    VStack(spacing: 7) {
                        Image(systemName: step.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(accentBlue)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(accentBlue.opacity(0.12)))
                        Text(checkInStartLabel(step))
                            .font(.poppins(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(.top, 28)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    checkInStep = 0
                    checkInStarted = true
                }
            } label: {
                Text(language == "de" ? "Loslegen" : "Get started")
                    .font(.poppins(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        Capsule()
                            .fill(Theme.accentGradient)
                            .shadow(color: accentBlue.opacity(0.3), radius: 12, y: 5)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)

            Button {
                checkInCompletedFor = DateKey.string(from: selectedDate)
            } label: {
                Text(language == "de" ? "Heute nicht" : "Not today")
                    .font(.poppins(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .padding(.bottom, 46)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: checkInStarted)
    }

    private var checkInStartDateLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: language == "de" ? "de_DE" : "en_US")
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f.string(from: selectedDate)
    }

    private func checkInStartLabel(_ step: CheckInStep) -> String {
        let de = language == "de"
        switch step {
        case .menstruation: return de ? "Zyklus" : "Cycle"
        case .sickness:     return de ? "Befinden" : "Health"
        case .caffeine:     return de ? "Koffein" : "Caffeine"
        case .macros:       return de ? "Essen" : "Food"
        }
    }

    // MARK: - Check-in Flow

    /// One question per screen, swipeable, with a light tap of haptic feedback
    /// each time a slide is left behind and a success tap at the end.
    private var checkInFlow: some View {
        let steps = checkInSteps
        return VStack(spacing: 0) {
            checkInHeader(steps: steps)

            TabView(selection: $checkInStep) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    checkInSlide(step).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if currentStepNeedsFooter {
                checkInFooter(steps: steps)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentStepNeedsFooter)
        // Fires on every change of step, which is exactly once per slide left
        // behind — forwards or backwards, swiped or tapped.
        .sensoryFeedback(.impact(weight: .light), trigger: checkInStep)
        .sensoryFeedback(.success, trigger: checkInCompletedFor)
    }

    private func checkInHeader(steps: [CheckInStep]) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text(language == "de" ? "Dein Check-in" : "Your check-in")
                    .font(.poppins(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(min(checkInStep + 1, steps.count))/\(steps.count)")
                    .font(.poppins(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            // A continuous bar rather than dots: it reads as "nearly there",
            // which dots at this count do not.
            GeometryReader { geo in
                Capsule()
                    .fill(Theme.trackFill)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.accentGradient)
                            .frame(width: geo.size.width
                                   * CGFloat(checkInStep + 1) / CGFloat(max(steps.count, 1)))
                    }
                    .clipShape(Capsule())
            }
            .frame(height: 5)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: checkInStep)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 22)
    }

    private func checkInSlide(_ step: CheckInStep) -> some View {
        GeometryReader { geo in
            if step.scrollsCardOnly {
                // Question and icon stay put; the card scrolls inside itself.
                // Scrolling the whole slide dragged the heading off the top,
                // and a form you scroll away from is one you lose your place in.
                VStack(alignment: .leading, spacing: 0) {
                    slideHeading(step)
                    ScrollView(showsIndicators: false) {
                        cardsSection(only: step)
                            .padding(.top, 20)
                            .padding(.bottom, 8)
                    }
                }
                .padding(.top, 24)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        slideHeading(step)
                        cardsSection(only: step)
                            .padding(.top, 26)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                    .frame(minHeight: geo.size.height, alignment: .center)
                }
            }
        }
    }

    /// Icon, question and reason — the part of a slide that never scrolls.
    private func slideHeading(_ step: CheckInStep) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: step.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(Theme.accentGradient)
                        .shadow(color: accentBlue.opacity(0.28), radius: 10, y: 4)
                )

            Text(step.question(language: language))
                .font(.poppins(size: 26, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            Text(step.reason(language: language))
                .font(.poppins(size: 13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Matches the 20 cardsSection carries, so heading and card share an edge.
        .padding(.horizontal, 20)
    }

    private func checkInFooter(steps: [CheckInStep]) -> some View {
        let isLast = checkInStep >= steps.count - 1
        return VStack(spacing: 10) {
            Button {
                if isLast {
                    finishCheckIn()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        checkInStep += 1
                    }
                }
            } label: {
                Text(isLast ? (language == "de" ? "Fertig" : "Done")
                            : (language == "de" ? "Weiter" : "Continue"))
                    .font(.poppins(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Capsule().fill(Theme.accentGradient))
            }
            .buttonStyle(.plain)

            // Skipping is not failure: an unanswered question simply leaves
            // that factor out, and pretending otherwise is what makes people
            // abandon a check-in halfway.
            Button {
                if isLast { finishCheckIn() }
                else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        checkInStep += 1
                    }
                }
            } label: {
                Text(language == "de" ? "Überspringen" : "Skip")
                    .font(.poppins(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .opacity(isLast ? 0 : 1)
        }
        .padding(.horizontal, 24)
        // Just clear of the floating tab bar.
        .padding(.bottom, 46)
    }

    /// Moves to the next slide, or ends the check-in on the last one.
    ///
    /// A question answered with one tap should not then ask for a second on
    /// "Weiter". Slides that open follow-ups when answered — "yes, I am ill" —
    /// deliberately do not call this.
    private func advanceCheckIn() {
        let steps = checkInSteps
        guard checkInStep < steps.count - 1 else {
            finishCheckIn()
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            checkInStep += 1
        }
    }

    private func finishCheckIn() {
        withAnimation(.easeOut(duration: 0.25)) {
            checkInCompletedFor = DateKey.string(from: selectedDate)
        }
        checkInStep = 0
        checkInStarted = false
    }

    // MARK: - Check-in Übersicht

    /// What the day looks like once the flow is behind you. Each row opens its
    /// own question, so correcting one value never means walking all of them.
    private var checkInSummary: some View {
        VStack(spacing: 10) {
            ForEach(checkInSteps) { step in
                Button {
                    editingStep = step
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: step.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accentBlue)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(accentBlue.opacity(0.13)))

                        Text(step.question(language: language))
                            .font(.poppins(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 8)

                        Text(checkInAnswer(step))
                            .font(.poppins(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.trailing)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.textSecondary.opacity(0.5))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(16)
                }
                .buttonStyle(.plain)
            }

            if Calendar.current.isDateInToday(selectedDate) {
                Button {
                    checkInCompletedFor = ""
                    checkInStep = 0
                } label: {
                    Text(language == "de" ? "Check-in wiederholen" : "Run check-in again")
                        .font(.poppins(size: 13, weight: .medium))
                        .foregroundStyle(accentBlue)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .disabled(isFutureDate)
        .opacity(isFutureDate ? 0.45 : 1.0)
    }

    /// The short form of an answer for the summary row.
    private func checkInAnswer(_ step: CheckInStep) -> String {
        let de = language == "de"
        let dash = de ? "offen" : "open"
        switch step {
        case .menstruation:
            guard let active = menstruationActive else { return dash }
            return active ? (de ? "Ja" : "Yes") : (de ? "Nein" : "No")
        case .sickness:
            guard sickToggle else { return de ? "Nein" : "No" }
            switch feverLevel {
            case .low:  return de ? "Krank, leichtes Fieber" : "Unwell, mild fever"
            case .high: return de ? "Krank, hohes Fieber" : "Unwell, high fever"
            default:    return de ? "Krank" : "Unwell"
            }
        case .caffeine:
            let mg = Int(caffeineText) ?? 0
            return mg == 0 ? dash : "\(mg) mg"
        case .macros:
            let p = macroTotal(proteinByMeal)
            let c = macroTotal(carbsByMeal)
            let f = macroTotal(fatByMeal)
            guard p + c + f > 0 else { return dash }
            return "\(Int(p))/\(Int(c))/\(Int(f)) g"
        }
    }

    private func macroTotal(_ byMeal: [String: String]) -> Double {
        byMeal.values.reduce(0) { $0 + (Double($1.replacingOccurrences(of: ",", with: ".")) ?? 0) }
    }

    /// Editing one question from the summary.
    private func checkInEditSheet(_ step: CheckInStep) -> some View {
        NavigationStack {
            ZStack {
                CaloricBackground()
                ScrollView(showsIndicators: false) {
                    cardsSection(only: step)
                        .padding(.top, 12)
                }
            }
            .navigationTitle(step.question(language: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language == "de" ? "Fertig" : "Done") { editingStep = nil }
                        .foregroundStyle(accentBlue)
                        .fontWeight(.semibold)
                }
            }
        }
        .caloricAppearance()
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.canvas)
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

    // MARK: - Collapsing header

    /// Same travel and rounding as the dashboard, so both tabs collapse at an
    /// identical rate — a difference between them would be felt when switching.
    private static let headerCollapseDistance: CGFloat = 76
    private static let headerCollapseSteps: Double = 20

    /// The date strip shrunk to a bar, pinned top-left. No profile button here:
    /// that one lives on the dashboard, and the journal's header never had it.
    private var compactDateButton: some View {
        Button {
            showCalendarPicker = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentBlue)
                Text(selectedDateString)
                    .font(.poppins(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Theme.card)
                    .overlay(Capsule().strokeBorder(Theme.cardStroke, lineWidth: 1))
                    .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 3)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(SpringyButtonStyle())
    }

    private var pinnedHeaderRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                compactDateButton
                    .opacity(headerCollapseProgress)
                    .scaleEffect(0.9 + 0.1 * headerCollapseProgress, anchor: .leading)
                    .allowsHitTesting(headerCollapseProgress > 0.6)
                Spacer(minLength: 12)
            }
            .frame(height: 40)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.12), value: headerCollapseProgress)
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
