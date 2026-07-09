    private func calculationDetailView(for type: EnergySegmentType) -> some View {
        let lbm = weightInKg * (1.0 - bodyFatPercent / 100.0)
        let baseBMR = 370 + 21.6 * lbm
        let isMale = selectedGender != femaleText
        
        let nWalkMin      = Double(healthKit.activity.steps) / 100.0
        let nWalkH        = nWalkMin / 60.0
        let nBmrH         = activeFinalBMR / 24.0
        let nStepsKcal    = nWalkH * 2.0 * nBmrH
        let nStandMin     = healthKit.activity.standTimeMinutes
        let nPureStandMin = max(0, nStandMin - nWalkMin)
        let nPureStandH   = nPureStandMin / 60.0
        let nStandKcal    = nPureStandH * 0.18 * nBmrH
        let nHrMax        = 208.0 - 0.7 * Double(userAge)
        let nWorkoutMin   = healthKit.workouts.reduce(0.0) { $0 + $1.duration } / 60.0
        let nEffSleepH    = sleepHours > 0 ? sleepHours : 8.0
        let nWakeMin      = (24.0 - nEffSleepH) * 60.0
        let nGapMin       = max(0, nWakeMin - nWalkMin - nStandMin - nWorkoutMin)
        let nHrAvg        = healthKit.activity.avgHeartRateWaking
        let nHrRest       = healthKit.activity.restingHeartRate

        let nMicroKcal: Double = {
            guard let avg = nHrAvg, let rest = nHrRest, avg > rest, nHrMax > rest else { return 0 }
            let divisor = nHrMax - rest
            guard divisor > 0 else { return 0 }
            let geschaetzterLückenPuls = min(avg - (nWorkoutMin > 0 ? 15.0 : 0.0), rest + 25.0)
            let saubererPuls = max(rest + 2.0, geschaetzterLückenPuls)
            let kJ: Double = isMale
                ? -55.0969 + 0.6309 * nHrMax + 0.1988 * weightInKg + 0.2017 * Double(userAge)
                : -20.4022 + 0.4472 * nHrMax - 0.1263 * weightInKg + 0.0740 * Double(userAge)
            let kNetto = max(0, kJ / 4.184 - activeFinalBMR / (24.0 * 60.0))
            let micro = ((saubererPuls - rest) / divisor) * nGapMin * kNetto * 0.10
            return min(max(0, micro), 500.0)
        }()

        return ZStack {
            CaloricBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    Spacer().frame(height: 10)
                    
                    switch type {
                    case .bmr:
                        calcSection(
                            icon: "moon.zzz.fill", iconColor: Theme.segBMR,
                            title: "BMR — Katch-McArdle",
                            rows: [
                                calcRow(label: language == "de" ? "Magermasse (LBM)" : "Lean Body Mass",
                                        formula: "Gewicht × (1 − Fett%)", value: String(format: "%.1f kg", lbm)),
                                calcRow(label: "BMR Basis", formula: "370 + 21.6 × LBM", value: String(format: "%.0f kcal", baseBMR)),
                                calcRow(label: language == "de" ? "Altersfaktor" : "Age factor",
                                        formula: "Stoffwechsel-Anpassung", value: String(format: "×%.3f", activeFinalBMR / (baseBMR * metabolismFactor))),
                                calcRow(label: language == "de" ? "Stoffwechselfaktor" : "Metabolism factor",
                                        formula: language == "de" ? "Benutzerdefiniert" : "User-defined", value: String(format: "×%.2f", metabolismFactor)),
                                calcRow(label: language == "de" ? "Schlafkorrektur" : "Sleep correction",
                                        formula: "Wach/Schlaf-Verhältnis", value: String(format: "%.0f kcal", activeFinalBMR))
                            ]
                        )
                        
                    case .neat:
                        calcSection(
                            icon: "figure.walk", iconColor: Theme.segNEAT,
                            title: "NEAT — 3-Komponenten",
                            rows: [
                                calcRow(label: language == "de" ? "① Geh-Kalorien" : "① Walk Calories",
                                        formula: String(format: "%d Schr · ×2.0 MET", healthKit.activity.steps),
                                        value: String(format: "%.0f kcal", nStepsKcal)),
                                calcRow(label: language == "de" ? "② Steh-Kalorien" : "② Stand Calories",
                                        formula: String(format: "%.0f min reines Stehen", nPureStandMin),
                                        value: String(format: "%.0f kcal", nStandKcal)),
                                {
                                    if let avg = nHrAvg, let rest = nHrRest, avg > rest {
                                        let hrr = (min(avg, rest + 25) - rest) / max(1, nHrMax - rest)
                                        return calcRow(label: language == "de" ? "③ Mikro-NEAT (HR)" : "③ Micro-NEAT (HR)",
                                                formula: String(format: "HRR %.2f · %.0f min · ×0.1", hrr, nGapMin),
                                                value: String(format: "%.0f kcal", nMicroKcal))
                                    } else {
                                        return calcRow(label: "③ Mikro-NEAT", formula: "Keine HR-Daten", value: "0 kcal")
                                    }
                                }()
                            ]
                        )
                        
                    case .eat:
                        calcSection(
                            icon: "dumbbell.fill", iconColor: Theme.segEAT,
                            title: "EAT — Keytel-Formel",
                            rows: {
                                var r: [AnyView] = [
                                    calcRow(label: "EPOC / Nachbrenneffekt", formula: "Kraft: +20% · Cardio: variabel", value: "")
                                ]
                                if healthKit.workouts.isEmpty {
                                    r.append(calcRow(label: language == "de" ? "Keine Workouts" : "No workouts", formula: "–", value: "0 kcal"))
                                } else {
                                    for w in healthKit.workouts {
                                        let kcal = ActivityCalculationService.eat(workout: w, weightKg: weightInKg, vo2Max: healthKit.vo2Max, hrRest: healthKit.activity.restingHeartRate, age: userAge, isMale: isMale)
                                        r.append(calcRow(label: workoutActivityName(w.activityType), formula: String(format: "%.0f min · Ø %.0f bpm", w.duration/60, w.averageHeartRate ?? 0), value: String(format: "%.0f kcal", kcal)))
                                    }
                                }
                                return r
                            }()
                        )
                        
                    case .tef:
                        calcSection(
                            icon: "fork.knife.circle.fill", iconColor: Theme.segTEF,
                            title: "TEF — Thermogenese",
                            rows: [
                                calcRow(label: "Proteine", formula: "25% thermische Last", value: String(format: "%.0f kcal", tdeeResult.tefKcal * 0.7)),
                                calcRow(label: "Kohlenhydrate", formula: "7.5% thermische Last", value: String(format: "%.0f kcal", tdeeResult.tefKcal * 0.2)),
                                calcRow(label: "Fette", formula: "1.5% thermische Last", value: String(format: "%.0f kcal", tdeeResult.tefKcal * 0.1))
                            ]
                        )
                        
                    case .caffeine:
                        calcSection(
                            icon: "cup.and.heat.waves.fill", iconColor: Theme.segCaf,
                            title: "Koffein-Effekt",
                            rows: [
                                calcRow(label: "Stimulation", formula: "+15 kcal / 100 mg", value: String(format: "+%.0f kcal", tdeeResult.koffeinBonus)),
                                calcRow(label: "Limitierung", formula: "Gedeckelt bei 400 mg", value: "")
                            ]
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(language == "de" ? "Wissenschaftlicher Hintergrund" : "Scientific Background")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(accentBlue)
                        Text(infoText(for: type))
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(4)
                    }
                    .padding(20)
                    .glassCard(20)
                    
                    Spacer()
                }
                .padding(.horizontal, 18)
            }
        }
        .navigationTitle(typeTitle(for: type))
    }

    private func typeTitle(for type: EnergySegmentType) -> String {
        switch type {
        case .bmr: return "BMR Details"
        case .neat: return "NEAT Details"
        case .eat: return "EAT Details"
        case .tef: return "TEF Details"
        case .caffeine: return "Caffeine Details"
        }
    }

    private func infoText(for type: EnergySegmentType) -> String {
        switch type {
        case .bmr: return language == "de" ? "Der Grundumsatz (BMR) basiert auf der Katch-McArdle Formel, die besonders präzise ist, da sie deine fettfreie Körpermasse berücksichtigt." : "The Basal Metabolic Rate (BMR) is based on the Katch-McArdle formula, which is particularly precise as it accounts for your lean body mass."
        case .neat: return language == "de" ? "NEAT umfasst alle Alltagsbewegungen. Wir berechnen dies über ein 3-Stufen-Modell aus Schritten, Stehzeit und der Herzfrequenz-Varianz in Ruhephasen." : "NEAT includes all daily movements. We calculate this using a 3-component model of steps, standing time, and heart rate variance during rest periods."
        case .eat: return language == "de" ? "EAT misst die Energie während geplanter Workouts. Hier nutzen wir die Keytel-Formel, die Alter, Gewicht und Herzfrequenz kombiniert." : "EAT measures energy during planned workouts. We use the Keytel formula, which combines age, weight, and heart rate."
        case .tef: return language == "de" ? "TEF ist die Energie, die dein Körper für die Verdauung aufwendet. Proteine haben hierbei mit ca. 25% den höchsten Effekt." : "TEF is the energy your body spends on digestion. Protein has the highest effect at approximately 25%."
        case .caffeine: return language == "de" ? "Koffein steigert die Thermogenese und den Stoffwechsel kurzfristig. Wir berechnen einen moderaten Bonus von 15 kcal pro 100 mg." : "Caffeine increases thermogenesis and metabolism in the short term. We calculate a moderate bonus of 15 kcal per 100 mg."
