//
//  HealthKitPermissionView.swift
//  caloric
//
//  Onboarding Step 9 — Apple Health permission screen.
//  Shown after account creation, before the dashboard loads.
//

import SwiftUI
import HealthKit

struct HealthKitPermissionView: View {

    let accentBlue:  Color
    let language:    String
    let topPadding:  CGFloat
    var onComplete:  () -> Void

    @Environment(\.colorScheme)               private var colorScheme
    @Environment(HealthKitImportService.self) private var healthKit

    @State private var heroVisible  = false
    @State private var cardsVisible = false
    @State private var isConnecting = false

    private let hkStore = HKHealthStore()

    private var isDark: Bool { colorScheme == .dark }

    private let healthGreen = Color(red: 0.20, green: 0.78, blue: 0.35)

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            ScrollView(showsIndicators: false) {
                VStack(spacing: 34) {
                    Spacer().frame(height: 18)
                    heroSection
                    cardsSection
                    Spacer().frame(height: 110)
                }
            }

            ctaSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.75)) {
                heroVisible = true
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.20)) {
                cardsVisible = true
            }
        }
    }
    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 22) {

            // Glow icon
            ZStack {
                // Ambient radial glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.red.opacity(isDark ? 0.32 : 0.18),
                                Color.red.opacity(0)
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 110
                        )
                    )
                    .frame(width: 220, height: 220)
                    .blur(radius: 12)
                    .scaleEffect(heroVisible ? 1 : 0.5)
                    .animation(.easeOut(duration: 1.1).delay(0.1), value: heroVisible)

                // Icon ring
                Circle()
                    .fill(Color.red.opacity(isDark ? 0.16 : 0.08))
                    .frame(width: 88, height: 88)
                Circle()
                    .strokeBorder(Color.red.opacity(isDark ? 0.34 : 0.20), lineWidth: 1.5)
                    .frame(width: 88, height: 88)

                Image(systemName: "heart.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.red, Color(red: 1.0, green: 0.22, blue: 0.28)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(heroVisible ? 1 : 0.65)
            .opacity(heroVisible ? 1 : 0)
            .animation(.spring(response: 0.65, dampingFraction: 0.72).delay(0.05), value: heroVisible)

            // Headline
            VStack(spacing: 6) {
                Text(language == "de" ? "Wir brauchen deine Hilfe." : "We need your help.")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(language == "de" ? "Um deinen persönlichen Kalorienbedarf so genau wie möglich zu berechnen, braucht Caloric Zugriff auf deine Aktivitätsdaten. Deine Bewegungskalorien machen hier nämlich den entscheidenden Unterschied!" : "To calculate your personal calorie needs as accurately as possible, Caloric needs access to your activity data. Your calories burned through movement make all the difference here!")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .opacity(heroVisible ? 1 : 0)
            .offset(y: heroVisible ? 0 : 10)
            .animation(.easeOut(duration: 0.46).delay(0.24), value: heroVisible)
        }
    }

    // MARK: - Feature Cards

    private var cardsSection: some View {
        VStack(spacing: 12) {
            featureCard(
                icon:      "figure.walk",
                iconColor: .orange,
                title:     language == "de" ? "Aktivitäts-Sync"   : "Activity Sync",
                subtitle:  language == "de"
                    ? "Schritte & Distanzen fließen live in deinen NEAT-Umsatz ein."
                    : "Steps & distances flow live into your NEAT expenditure.",
                index: 0
            )
            featureCard(
                icon:      "moon.zzz.fill",
                iconColor: Color(red: 0.42, green: 0.35, blue: 0.95),
                title:     language == "de" ? "Schlaf-Analyse"     : "Sleep Analysis",
                subtitle:  language == "de"
                    ? "Automatischer BMR-Abzug während deiner verschiedenen Schlafphasen."
                    : "Automatic BMR deduction during your various sleep phases.",
                index: 1
            )
            featureCard(
                icon:      "dumbbell.fill",
                iconColor: accentBlue,
                title:     language == "de" ? "Workout-Kopplung"   : "Workout Sync",
                subtitle:  language == "de"
                    ? "Importiert deine Trainingseinheiten und wir interpretieren sie neu."
                    : "Import your workouts, and we'll reinterpret them.",
                index: 2
            )
        }
        .padding(.horizontal, 24)
    }

    private func featureCard(
        icon:      String,
        iconColor: Color,
        title:     String,
        subtitle:  String,
        index:     Int
    ) -> some View {
        HStack(spacing: 14) {

            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(iconColor.opacity(isDark ? 0.20 : 0.10))
                    .frame(width: 46, height: 46)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isDark ? 0.14 : 0.65),
                                    Color.white.opacity(isDark ? 0.04 : 0.22)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .opacity(cardsVisible ? 1 : 0)
        .offset(y: cardsVisible ? 0 : 20)
        .animation(
            .spring(response: 0.52, dampingFraction: 0.82)
                .delay(0.08 + Double(index) * 0.13),
            value: cardsVisible
        )
    }

    // MARK: - CTA Section

    private var ctaSection: some View {
        VStack(spacing: 0) {
            // Gradient fade into button area
            LinearGradient(
                colors: [Theme.canvas.opacity(0), Theme.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)
            .allowsHitTesting(false)

            VStack(spacing: 12) {
                // Primary button — Connect
                Button {
                    guard !isConnecting else { return }
                    isConnecting = true
                    Task {
                        // Always present the native HealthKit permission sheet directly,
                        // then sync the result back into the shared service.
                        try? await hkStore.requestAuthorization(
                            toShare: [],
                            read: [
                                .workoutType(),
                                HKObjectType.quantityType(forIdentifier: .stepCount)!,
                                HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
                                HKObjectType.quantityType(forIdentifier: .heartRate)!,
                                HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
                            ]
                        )
                        try? await healthKit.requestAuthorization()
                        isConnecting = false
                        onComplete()
                    }
                } label: {
                    ZStack {
                        HStack(spacing: 10) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text(language == "de" ? "Apple Health verbinden" : "Connect Apple Health")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                        .opacity(isConnecting ? 0 : 1)

                        if isConnecting {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(accentBlue)
                            .shadow(color: accentBlue.opacity(0.32), radius: 18, x: 0, y: 7)
                    )
                    .scaleEffect(isConnecting ? 0.97 : 1)
                    .animation(.easeOut(duration: 0.14), value: isConnecting)
                }
                .disabled(isConnecting)
                .padding(.horizontal, 24)

                // Secondary button — Skip
                Button(language == "de" ? "Später in den Einstellungen" : "Later in Settings") {
                    onComplete()
                }
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            }
            .padding(.top, 4)
            .padding(.bottom, 16)
            .background(Theme.canvas)
        }
    }
}
