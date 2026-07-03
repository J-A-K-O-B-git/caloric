//
//  AppRootView.swift
//  caloric
//
//  Entry point after caloricApp. Routes to Onboarding or Dashboard
//  depending on whether a completed UserProfile exists in SwiftData.
//

import SwiftUI
import SwiftData

// MARK: - Router

struct AppRootView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        if let profile = profiles.first(where: { $0.isOnboardingCompleted }) {
            ProfileDashboardView(profile: profile)
        } else {
            ContentView()
        }
    }
}

// MARK: - Returning-user adapter

/// Bridges the persisted UserProfile back into MainTabView's @Binding interface.
/// Changes to name / birthDate are written back to SwiftData automatically.
private struct ProfileDashboardView: View {

    @Bindable var profile: UserProfile

    // Local @State mirrors for the @Binding interface MainTabView expects.
    @State private var accountUsername:     String
    @State private var birthDate:           Date
    @State private var weightText:          String
    @State private var weightUnit:          String
    @State private var heightText:          String
    @State private var heightUnit:          String
    @State private var bodyFatText:         String
    @State private var knowsBodyFat:        Bool?
    @State private var sleepHours:          Double
    @State private var selectedConditions:  Set<String>
    @State private var metabolismFactor:    Double

    private let accentBlue = Theme.accentBlue

    init(profile: UserProfile) {
        self.profile = profile
        _accountUsername    = State(initialValue: profile.name)
        _birthDate          = State(initialValue: profile.birthDate)
        _weightText         = State(initialValue: profile.weightText)
        _weightUnit         = State(initialValue: profile.weightUnit)
        _heightText         = State(initialValue: profile.heightText)
        _heightUnit         = State(initialValue: profile.heightUnit)
        _bodyFatText        = State(initialValue: profile.bodyFatText)
        _knowsBodyFat       = State(initialValue: profile.weissKfa ? true : false)
        _sleepHours         = State(initialValue: profile.schlafStunden)
        _selectedConditions = State(initialValue: Set(profile.selectedConditions))
        _metabolismFactor   = State(initialValue: profile.stoffwechselFaktor)
    }

    var body: some View {
        let t = Translations(language: profile.sprache)
        MainTabView(
            accentBlue:         accentBlue,
            language:           profile.sprache,
            finalBMR:           profile.finalBMR,
            sleepHoursValue:    profile.schlafStunden,
            leanBodyMass:       profile.leanBodyMass,
            userAge:            profile.userAge,
            selectedGender:     profile.geschlecht.isEmpty ? nil : profile.geschlecht,
            noConditionText:    t.noCondition,
            femaleText:         t.female,
            accountUsername:    $accountUsername,
            birthDate:          $birthDate,
            weightText:         $weightText,
            weightUnit:         $weightUnit,
            heightText:         $heightText,
            heightUnit:         $heightUnit,
            bodyFatText:        $bodyFatText,
            knowsBodyFat:       $knowsBodyFat,
            sleepHours:         $sleepHours,
            selectedConditions: $selectedConditions,
            metabolismFactor:   $metabolismFactor
        )
        // Sync editable fields back to SwiftData on every change.
        .onChange(of: accountUsername)    { _, v in profile.name               = v }
        .onChange(of: birthDate)          { _, v in profile.birthDate           = v }
        .onChange(of: weightText)         { _, v in profile.weightText          = v }
        .onChange(of: weightUnit)         { _, v in profile.weightUnit          = v }
        .onChange(of: heightText)         { _, v in profile.heightText          = v }
        .onChange(of: heightUnit)         { _, v in profile.heightUnit          = v }
        .onChange(of: bodyFatText)        { _, v in profile.bodyFatText         = v }
        .onChange(of: sleepHours)         { _, v in profile.schlafStunden       = v }
        .onChange(of: metabolismFactor)   { _, v in profile.stoffwechselFaktor  = v }
        .onChange(of: selectedConditions) { _, v in profile.selectedConditions  = Array(v) }
    }
}
