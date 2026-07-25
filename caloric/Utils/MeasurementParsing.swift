//
//  MeasurementParsing.swift
//  caloric
//
//  Turns the unit-aware text the user typed into numbers.
//
//  These conversions used to be written out in ContentView, UserProfile and
//  DashboardView. Same concern as BMRCalculationService: one implementation so
//  the onboarding form and the dashboard cannot read the same input differently.
//

import Foundation

enum MeasurementParsing {

    /// Accepts both decimal separators — the app's text fields are locale-free.
    static func decimal(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    static func weightKg(text: String, unit: String) -> Double {
        let value = decimal(text) ?? 0
        return unit == "kg" ? value : value * 0.453592
    }

    static func heightCm(text: String, unit: String) -> Double {
        if unit == "cm" { return decimal(text) ?? 0 }
        return (feet(from: text) ?? 0) * 30.48
    }

    static func percent(_ text: String) -> Double {
        decimal(text) ?? 0
    }

    /// Parses `5'10"`, `5'10`, `5'` or a plain decimal into feet.
    static func feet(from input: String) -> Double? {
        let cleaned = input.replacingOccurrences(of: "\"", with: "")
        guard cleaned.contains("'") else { return decimal(cleaned) }

        let parts = cleaned.split(separator: "'")
        guard let feet = Double(parts.first ?? "") else { return nil }
        if parts.count > 1, let inches = Double(parts[1]) {
            return feet + inches / 12.0
        }
        return feet
    }
}
