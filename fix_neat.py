import sys

with open("caloric/Onboarding/DashboardView.swift", "r") as f:
    content = f.read()

# 1. Update calculationDetailView for NEAT to include Unrecorded Cardio math and row
# Also fixing base BMR to use the same dynamic one as the service.

old_neat_block = """                    case .neat:
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
                        }"""

new_neat_block = """                    case .neat:
                        let nCardioKcal = max(0, activityResult.neatKcal - nStepsKcal - nStandKcal - nMicroKcal)
                        
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
                                .init(value: nStandKcal, color: Theme.segNEAT.opacity(0.8), label: language == "de" ? "Stehen" : "Stand"),
                                .init(value: nMicroKcal, color: Theme.segNEAT.opacity(0.6), label: "Mikro"),
                                .init(value: nCardioKcal, color: Theme.segNEAT.opacity(0.3), label: "Cardio")
                            ],
                            total: max(1, activityResult.neatKcal)
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
                            }
                            if nCardioKcal > 0 {
                                InfographicMathCard(
                                    title: language == "de" ? "④ Ungemeldete Belastung" : "④ Unrecorded Intensity",
                                    formula: language == "de" ? "Aktive Phasen außerhalb Workouts" : "Active phases outside workouts",
                                    value: String(format: "%.0f kcal", nCardioKcal),
                                    color: Theme.segNEAT
                                )
                            }
                        }"""

if old_neat_block in content:
    content = content.replace(old_neat_block, new_neat_block)
    with open("caloric/Onboarding/DashboardView.swift", "w") as f:
        f.write(content)
    print("Success")
else:
    print("Block not found")
