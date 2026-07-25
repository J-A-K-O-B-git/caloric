//
//  UserProfile.swift
//  caloric
//
//  SwiftData model — single source of truth for all onboarding data.
//  Derived values go through BMRCalculationService so this model, the
//  onboarding form and the dashboard cannot drift apart again.
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

    // MARK: - Computed helpers (not persisted)
    //
    // Typed access to the model's own unit-aware text fields. The derived
    // energy values that used to live here (leanBodyMass, finalBMR) are gone —
    // nothing read them, and their duplicate age factor was what made the
    // dashboard and the onboarding disagree. BMRCalculationService owns that
    // math now.

    var weightInKg: Double {
        MeasurementParsing.weightKg(text: weightText, unit: weightUnit)
    }

    var heightInCm: Double {
        MeasurementParsing.heightCm(text: heightText, unit: heightUnit)
    }

    var bodyFatPercent: Double {
        MeasurementParsing.percent(bodyFatText)
    }

    var userAge: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
    }
}
