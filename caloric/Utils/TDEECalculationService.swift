//
//  TDEECalculationService.swift
//  caloric
//

import Foundation

struct TDEECalculationService {

    // MARK: - Input

    struct JournalInputs {
        enum SickEnergyLevel: String, Equatable, Codable { case mild, bedridden }
        enum FeverLevel: String, Equatable, Codable      { case none, low, high }

        var sickActive:          Bool                    = false
        var sickEnergyLevel:     SickEnergyLevel?        = nil
        var feverLevel:          FeverLevel              = .none
        var menstruationActive:  Bool?                   = nil
        var caffeineMg:          Double                  = 0
        var palFactor:           Double                  = 1.0
        var proteinGramsByMeal:  [String: Double]        = [:]
        var carbsGramsByMeal:    [String: Double]        = [:]
        var fatGramsByMeal:      [String: Double]        = [:]
    }

    // MARK: - Output

    struct TDEEResult {
        let krankheitsFaktor:   Double
        let zyklusFaktor:       Double
        let koffeinBonus:       Double
        /// Thermic Effect of Food: energy spent on digestion.
        let tefKcal:            Double
        let bmrDynamisch:       Double
        let tdeeTotal:          Double
    }

    // MARK: - Main Calculation

    /// Computes the full TDEE pipeline for one calendar day.
    /// - Parameters:
    ///   - bmrStandard: Katch-McArdle BMR already adjusted for age and chronic metabolism factor.
    ///   - inputs: Daily journal entries for the target date.
    ///   - isFemale: Whether to apply the luteal/menstruation cycle factor.
    static func calculate(
        bmrStandard: Double,
        inputs: JournalInputs,
        isFemale: Bool
    ) -> TDEEResult {
        let kf  = illnessBMRFactor(inputs: inputs)
        let zf  = cycleBMRFactor(inputs: inputs, isFemale: isFemale)
        let kb  = caffeineBonus(mg: inputs.caffeineMg)
        let tef = thermicEffectOfFood(inputs: inputs)

        let bmrDyn = bmrStandard * kf * zf
        let pal    = adjustedPAL(inputs: inputs)
        let tdee   = (bmrDyn * pal) + kb + tef

        return TDEEResult(
            krankheitsFaktor:  kf,
            zyklusFaktor:      zf,
            koffeinBonus:      kb,
            tefKcal:           tef,
            bmrDynamisch:      bmrDyn,
            tdeeTotal:         tdee
        )
    }

    // MARK: - Illness BMR Factor

    // +10 % for low fever, +18 % for high fever; no BMR boost for energy level alone.
    private static func illnessBMRFactor(inputs: JournalInputs) -> Double {
        guard inputs.sickActive else { return 1.0 }
        switch inputs.feverLevel {
        case .low:  return 1.10
        case .high: return 1.18
        case .none: return 1.0
        }
    }

    // MARK: - PAL Adjustment for Illness Energy State

    /// Mild sickness caps extra activity at 70 % of normal; bedridden fixes PAL at minimum 1.1.
    static func adjustedPAL(inputs: JournalInputs) -> Double {
        guard inputs.sickActive else { return inputs.palFactor }
        switch inputs.sickEnergyLevel {
        case .mild:
            return 1.0 + max(0, inputs.palFactor - 1.0) * 0.70
        case .bedridden:
            return 1.1
        case .none:
            return inputs.palFactor
        }
    }

    // MARK: - Cycle BMR Factor

    // +5 % for menstruation or luteal phase.
    private static func cycleBMRFactor(inputs: JournalInputs, isFemale: Bool) -> Double {
        guard isFemale, inputs.menstruationActive == true else { return 1.0 }
        return 1.05
    }

    // MARK: - Caffeine Thermogenesis

    // +15 kcal per 100 mg caffeine, capped at +60 kcal (≥ 400 mg).
    private static func caffeineBonus(mg: Double) -> Double {
        guard mg > 0 else { return 0 }
        return min((mg / 100.0) * 15.0, 60.0)
    }

    // MARK: - Thermic Effect of Food (TEF / DIT)

    /// Energy cost of digesting macronutrients (Dietary Induced Thermogenesis).
    ///   Protein  × 1.000 kcal/g  (25 % of 4 kcal/g)
    ///   Carbs    × 0.300 kcal/g  ( 7.5 % of 4 kcal/g)
    ///   Fat      × 0.135 kcal/g  ( 1.5 % of 9 kcal/g)
    private static func thermicEffectOfFood(inputs: JournalInputs) -> Double {
        let proteinG = inputs.proteinGramsByMeal.values.reduce(0, +)
        let carbsG   = inputs.carbsGramsByMeal.values.reduce(0, +)
        let fatG     = inputs.fatGramsByMeal.values.reduce(0, +)
        return proteinG * 1.0 + carbsG * 0.3 + fatG * 0.135
    }

}
