//
//  UserProfile.swift
//  caloric
//
//  SwiftData model — single source of truth for all onboarding data.
//  Computed properties mirror the same derivation logic as ContentView.
//

import Foundation
import SwiftData

@Model
final class UserProfile {

    // MARK: - Stored attributes

    var name:                 String = ""
    var birthDate:            Date   = Date()
    var geschlecht:           String = ""    // raw translation string, "" = not set

    // Form strings kept exactly as the user typed them (unit-aware display values)
    var weightText:           String = "70"
    var weightUnit:           String = "kg"  // "kg" | "lb"
    var heightText:           String = "170"
    var heightUnit:           String = "cm"  // "cm" | "ft"
    var bodyFatText:          String = ""
    var weissKfa:             Bool   = false // true = user entered a body-fat value

    var sprache:              String   = "de"
    var stoffwechselFaktor:   Double   = 1.0
    var schlafStunden:        Double   = 7.0
    var selectedConditions:   [String] = []
    var isOnboardingCompleted: Bool    = false

    init(
        name:               String,
        birthDate:          Date,
        geschlecht:         String,
        weightText:         String,
        weightUnit:         String,
        heightText:         String,
        heightUnit:         String,
        bodyFatText:        String,
        weissKfa:           Bool,
        sprache:            String,
        stoffwechselFaktor: Double,
        schlafStunden:      Double,
        selectedConditions: [String]
    ) {
        self.name               = name
        self.birthDate          = birthDate
        self.geschlecht         = geschlecht
        self.weightText         = weightText
        self.weightUnit         = weightUnit
        self.heightText         = heightText
        self.heightUnit         = heightUnit
        self.bodyFatText        = bodyFatText
        self.weissKfa           = weissKfa
        self.sprache            = sprache
        self.stoffwechselFaktor = stoffwechselFaktor
        self.schlafStunden      = schlafStunden
        self.selectedConditions = selectedConditions
        self.isOnboardingCompleted = false
    }

    // MARK: - Computed helpers (not persisted, mirror ContentView logic)

    var weightInKg: Double {
        let v = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return weightUnit == "kg" ? v : v * 0.453592
    }

    var heightInCm: Double {
        if heightUnit == "cm" {
            return Double(heightText.replacingOccurrences(of: ",", with: ".")) ?? 0
        }
        let cleaned = heightText.replacingOccurrences(of: "\"", with: "")
        if cleaned.contains("'") {
            let parts = cleaned.split(separator: "'")
            guard let feet = Double(parts[0]) else { return 0 }
            if parts.count > 1, let inches = Double(parts[1]) { return (feet + inches / 12) * 30.48 }
            return feet * 30.48
        }
        return (Double(cleaned.replacingOccurrences(of: ",", with: ".")) ?? 0) * 30.48
    }

    var bodyFatPercent: Double {
        Double(bodyFatText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var userAge: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
    }

    var leanBodyMass: Double {
        weightInKg * (1.0 - bodyFatPercent / 100.0)
    }

    var finalBMR: Double {
        let base   = 370 + 21.6 * leanBodyMass
        let age    = userAge > 30 ? 1.0 - Double(userAge - 30) * 0.0015 : 1.0
        let adj    = base * age * stoffwechselFaktor
        let hourly = adj / 24.0
        let wake   = 24.0 - schlafStunden
        return (schlafStunden * hourly * 0.9) + (wake * hourly)
    }
}
