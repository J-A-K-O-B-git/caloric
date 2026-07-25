//
//  BMRCalculationService.swift
//  caloric
//
//  Single source of truth for the resting metabolic rate.
//
//  The Katch-McArdle base and the sleep weighting used to be written out in
//  three places (ContentView, UserProfile, DashboardView). The age factor had
//  already drifted apart between them, so onboarding and dashboard showed
//  different numbers for the same person. Everything now goes through here.
//

import Foundation

enum BMRCalculationService {

    // MARK: - Components

    static func leanBodyMass(weightKg: Double, bodyFatPercent: Double) -> Double {
        weightKg * (1.0 - bodyFatPercent / 100.0)
    }

    /// Katch-McArdle: 370 + 21.6 × fat-free mass.
    static func baseBMR(leanBodyMass: Double) -> Double {
        370 + 21.6 * leanBodyMass
    }

    /// Piecewise decline — flat until 30, gentle to 60, steeper after.
    static func ageFactor(age: Int) -> Double {
        if age <= 30 { return 1.0 }
        if age <= 60 { return 1.0 - Double(age - 30) * 0.001 }
        return 0.970 - Double(age - 60) * 0.005
    }

    /// Sleep runs ~10 % below waking rest, so the 24 h total is weighted rather
    /// than taken flat.
    static func sleepWeighted(dailyBMR: Double, sleepHours: Double) -> Double {
        let hourly = dailyBMR / 24.0
        let wake   = 24.0 - sleepHours
        return (sleepHours * hourly * 0.9) + (wake * hourly)
    }

    /// Inverse of `sleepWeighted` — the plain hourly rate behind a weighted total.
    static func hourlyRate(finalBMR: Double, sleepHours: Double) -> Double {
        let divisor = 24.0 - sleepHours * 0.1
        guard divisor > 0 else { return 0 }
        return finalBMR / divisor
    }

    // MARK: - Full pipeline

    static func finalBMR(
        weightKg: Double,
        bodyFatPercent: Double,
        age: Int,
        metabolismFactor: Double,
        sleepHours: Double
    ) -> Double {
        let lbm      = leanBodyMass(weightKg: weightKg, bodyFatPercent: bodyFatPercent)
        let adjusted = baseBMR(leanBodyMass: lbm) * ageFactor(age: age) * metabolismFactor
        return sleepWeighted(dailyBMR: adjusted, sleepHours: sleepHours)
    }
}
