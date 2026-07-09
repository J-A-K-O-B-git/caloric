import sys

with open("caloric/Onboarding/DashboardView.swift", "r") as f:
    content = f.read()

old_block = """                    switch type {
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
                    }"""

new_block = """                    switch type {
                    case .bmr:
                        InfographicHeroCard(
                            title: language == "de" ? "Grundumsatz (BMR)" : "Basal Metabolic Rate",
                            subtitle: language == "de" ? "Katch-McArdle Formel" : "Katch-McArdle Formula",
                            value: String(format: "%.0f", activeFinalBMR),
                            unit: "kcal",
                            icon: "moon.zzz.fill",
                            color: Theme.segBMR
                        )
                        
                        VStack(spacing: 8) {
                            InfographicMathCard(
                                title: language == "de" ? "Magermasse (LBM)" : "Lean Body Mass",
                                formula: language == "de" ? "Gewicht × (1 - Fett%)" : "Weight × (1 - Fat%)",
                                value: String(format: "%.1f kg", lbm),
                                color: Theme.segBMR
                            )
                            InfographicMathCard(
                                title: language == "de" ? "Basis-Umsatz" : "Base BMR",
                                formula: "370 + 21.6 × LBM",
                                value: String(format: "%.0f kcal", baseBMR),
                                color: Theme.segBMR
                            )
                            InfographicMathCard(
                                title: language == "de" ? "Faktoren" : "Multipliers",
                                formula: language == "de" ? "Schlaf, Alter & Stoffwechsel" : "Sleep, Age & Metabolism",
                                value: String(format: "×%.2f", activeFinalBMR / baseBMR),
                                color: Theme.segBMR
                            )
                        }
                        
                    case .neat:
                        InfographicHeroCard(
                            title: language == "de" ? "Alltagsbewegung (NEAT)" : "Daily Activity (NEAT)",
                            subtitle: language == "de" ? "3-Komponenten Modell" : "3-Component Model",
                            value: String(format: "%.0f", activityResult.neatKcal),
                            unit: "kcal",
                            icon: "figure.walk",
                            color: Theme.segNEAT
                        )
                        
                        InfographicSegmentBar(
                            segments: [
                                .init(value: nStepsKcal, color: Theme.segNEAT, label: language == "de" ? "Gehen" : "Walk"),
                                .init(value: nStandKcal, color: Theme.segNEAT.opacity(0.7), label: language == "de" ? "Stehen" : "Stand"),
                                .init(value: nMicroKcal, color: Theme.segNEAT.opacity(0.4), label: "Mikro")
                            ],
                            total: activityResult.neatKcal
                        )
                        
                        VStack(spacing: 8) {
                            InfographicMathCard(
                                title: language == "de" ? "① Geh-Kalorien" : "① Walk Calories",
                                formula: String(format: "%d Schr · ×2.0 MET", healthKit.activity.steps),
                                value: String(format: "%.0f kcal", nStepsKcal),
                                color: Theme.segNEAT
                            )
                            InfographicMathCard(
                                title: language == "de" ? "② Steh-Kalorien" : "② Stand Calories",
                                formula: String(format: "%.0f min reines Stehen", nPureStandMin),
                                value: String(format: "%.0f kcal", nStandKcal),
                                color: Theme.segNEAT
                            )
                            if let avg = nHrAvg, let rest = nHrRest, avg > rest {
                                let hrr = (min(avg, rest + 25) - rest) / max(1, nHrMax - rest)
                                InfographicMathCard(
                                    title: language == "de" ? "③ Mikro-NEAT (HR)" : "③ Micro-NEAT (HR)",
                                    formula: String(format: "HRR %.2f · %.0f min", hrr, nGapMin),
                                    value: String(format: "%.0f kcal", nMicroKcal),
                                    color: Theme.segNEAT
                                )
                            } else {
                                InfographicMathCard(
                                    title: "③ Mikro-NEAT",
                                    formula: language == "de" ? "Keine HR-Daten" : "No HR data",
                                    value: "0 kcal",
                                    color: Theme.segNEAT
                                )
                            }
                        }
                        
                    case .eat:
                        InfographicHeroCard(
                            title: language == "de" ? "Workouts (EAT)" : "Workouts (EAT)",
                            subtitle: language == "de" ? "Keytel Formel + EPOC" : "Keytel Formula + EPOC",
                            value: String(format: "%.0f", activityResult.eatKcal),
                            unit: "kcal",
                            icon: "dumbbell.fill",
                            color: Theme.segEAT
                        )
                        
                        if healthKit.workouts.isEmpty {
                            InfographicMathCard(
                                title: language == "de" ? "Keine Workouts" : "No workouts",
                                formula: language == "de" ? "Heute noch nicht trainiert" : "No training today",
                                value: "0 kcal",
                                color: Theme.segEAT
                            )
                        } else {
                            VStack(spacing: 8) {
                                ForEach(healthKit.workouts) { w in
                                    let kcal = ActivityCalculationService.eat(workout: w, weightKg: weightInKg, vo2Max: healthKit.vo2Max, hrRest: healthKit.activity.restingHeartRate, age: userAge, isMale: isMale)
                                    InfographicMathCard(
                                        title: workoutActivityName(w.activityType),
                                        formula: String(format: "%.0f min · Ø %.0f bpm", w.duration/60, w.averageHeartRate ?? 0),
                                        value: String(format: "%.0f kcal", kcal),
                                        color: Theme.segEAT
                                    )
                                }
                            }
                        }
                        
                    case .tef:
                        InfographicHeroCard(
                            title: language == "de" ? "Verdauung (TEF)" : "Digestion (TEF)",
                            subtitle: language == "de" ? "Thermischer Effekt der Nahrung" : "Thermic Effect of Food",
                            value: String(format: "%.0f", tdeeResult.tefKcal),
                            unit: "kcal",
                            icon: "fork.knife.circle.fill",
                            color: Theme.segTEF
                        )
                        
                        InfographicSegmentBar(
                            segments: [
                                .init(value: tdeeResult.tefKcal * 0.7, color: Theme.segTEF, label: "Protein"),
                                .init(value: tdeeResult.tefKcal * 0.2, color: Theme.segTEF.opacity(0.6), label: "Carbs"),
                                .init(value: tdeeResult.tefKcal * 0.1, color: Theme.segTEF.opacity(0.3), label: "Fat")
                            ],
                            total: max(1, tdeeResult.tefKcal)
                        )
                        
                    case .caffeine:
                        InfographicHeroCard(
                            title: language == "de" ? "Koffein-Effekt" : "Caffeine Effect",
                            subtitle: language == "de" ? "Metabolische Stimulation" : "Metabolic Stimulation",
                            value: String(format: "+%.0f", tdeeResult.koffeinBonus),
                            unit: "kcal",
                            icon: "cup.and.heat.waves.fill",
                            color: Theme.segCaf
                        )
                        
                        InfographicMathCard(
                            title: language == "de" ? "Stimulation" : "Stimulation",
                            formula: "+15 kcal / 100 mg",
                            value: String(format: "+%.0f kcal", tdeeResult.koffeinBonus),
                            color: Theme.segCaf
                        )
                    }"""

if old_block in content:
    content = content.replace(old_block, new_block)
    with open("caloric/Onboarding/DashboardView.swift", "w") as f:
        f.write(content)
    print("Success")
else:
    print("String not found. Check formatting.")
