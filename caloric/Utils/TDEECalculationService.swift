//
//  TDEECalculationService.swift
//  caloric
//

import Foundation

/// Turns a meal described in words into grams.
///
/// Logging every meal by weight is the one thing in this app nobody keeps up,
/// and an unlogged day currently contributes a TEF of exactly zero — which
/// understates it by 150 to 250 kcal. Picking a couple of words per meal gets
/// within single-digit kcal of a properly weighed day, because TEF is linear
/// in grams and therefore only cares about the day's totals.
///
/// The three axes are not a stylistic choice: TEF has exactly three inputs,
/// so protein, carbohydrate and fat are a complete basis. A fourth tag —
/// "fried", "sweet", "meat" — could not move the result in any way these
/// three cannot already express, and would smuggle in an assumption the user
/// cannot see.
enum MealEstimator {

    enum Level: String, Codable, CaseIterable {
        case low, normal, high
    }

    enum Portion: String, Codable, CaseIterable {
        case small, normal, large

        var factor: Double {
            switch self {
            case .small:  return 0.7
            case .normal: return 1.0
            case .large:  return 1.4
            }
        }
    }

    enum Meal: String, Codable, CaseIterable {
        case breakfast, lunch, dinner, snack

        /// Conventional split of a day's energy. Only a starting point — the
        /// portion control moves it, and the tags move it again.
        var energyShare: Double {
            switch self {
            case .breakfast: return 0.25
            case .lunch:     return 0.35
            case .dinner:    return 0.30
            case .snack:     return 0.10
            }
        }
    }

    struct Description: Codable, Equatable {
        var portion: Portion = .normal
        var protein: Level = .normal
        var carbs: Level = .normal
        var fat: Level = .normal

        /// True while the meal says nothing beyond "normal" — nothing to
        /// estimate from, and the caller should treat it as unanswered.
        var isUntouched: Bool {
            portion == .normal && protein == .normal && carbs == .normal && fat == .normal
        }
    }

    struct Macros: Equatable {
        let proteinG: Double
        let carbsG: Double
        let fatG: Double

        var kcal: Double { proteinG * 4 + carbsG * 4 + fatG * 9 }
    }

    /// Baseline protein for an ordinary day, before any tag moves it.
    private static let baseProteinPerKg = 1.3
    /// Below this the diet stops covering essential fatty acids, so "low fat"
    /// is not allowed to push past it however the arithmetic falls.
    private static let fatFloorPerKg = 0.6

    private static func proteinFactor(_ level: Level) -> Double {
        switch level {
        case .low:    return 0.65
        case .normal: return 1.0
        case .high:   return 1.55
        }
    }

    private static func fatShare(_ level: Level) -> Double {
        switch level {
        case .low:    return 0.20
        case .normal: return 0.30
        case .high:   return 0.45
        }
    }

    /// Grams for one meal.
    ///
    /// Protein is anchored to body weight rather than to a percentage — which
    /// is the whole point of asking in words. "High protein" has to mean
    /// something different for 60 kg than for 95 kg, and a percentage of
    /// intake would give both the same answer.
    ///
    /// Carbohydrate is the remainder, so the three tags can never contradict
    /// each other: "low carb" simply raises fat, "high carb" lowers it, and no
    /// combination can produce a split that fails to add up.
    static func macros(
        for description: Description,
        meal: Meal,
        dailyEnergyKcal: Double,
        weightKg: Double
    ) -> Macros {
        guard dailyEnergyKcal > 0, weightKg > 0 else {
            return Macros(proteinG: 0, carbsG: 0, fatG: 0)
        }

        var fat = description.fat
        if fat == .normal {
            if description.carbs == .low  { fat = .high }
            if description.carbs == .high { fat = .low }
        }

        let scale = meal.energyShare * description.portion.factor
        let kcal  = dailyEnergyKcal * scale

        let proteinG = baseProteinPerKg * weightKg * scale * proteinFactor(description.protein)
        let fatG     = max(kcal * fatShare(fat) / 9, fatFloorPerKg * weightKg * scale)
        let carbsG   = max(0, (kcal - proteinG * 4 - fatG * 9) / 4)

        return Macros(proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }
}

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
        let pDaily = inputs.proteinGramsByMeal["daily"] ?? 0
        let cDaily = inputs.carbsGramsByMeal["daily"]   ?? 0
        let fDaily = inputs.fatGramsByMeal["daily"]     ?? 0
        
        let proteinG: Double
        let carbsG:   Double
        let fatG:     Double
        
        if pDaily > 0 || cDaily > 0 || fDaily > 0 {
            proteinG = pDaily
            carbsG   = cDaily
            fatG     = fDaily
        } else {
            proteinG = ["breakfast", "lunch", "dinner"].compactMap { inputs.proteinGramsByMeal[$0] }.reduce(0, +)
            carbsG   = ["breakfast", "lunch", "dinner"].compactMap { inputs.carbsGramsByMeal[$0]   }.reduce(0, +)
            fatG     = ["breakfast", "lunch", "dinner"].compactMap { inputs.fatGramsByMeal[$0]     }.reduce(0, +)
        }
        
        return proteinG * 1.0 + carbsG * 0.3 + fatG * 0.135
    }

}
