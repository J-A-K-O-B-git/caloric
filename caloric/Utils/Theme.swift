//
//  Theme.swift
//  caloric
//
//  Zentrale Farb- und Stil-Definitionen
//
//  Designsystem "Caloric Ice" — helles, sportliches UI:
//  kühler Eis-Hintergrund, weiße Karten mit weichen blauen Schatten,
//  SF Rounded für den Fitness-Charakter und das Caloric-Blau als
//  durchgängiger Akzent (Sky #66CCFF → Azure #119BE8).
//

import SwiftUI

enum Theme {

    // MARK: - Caloric-Blau Familie
    /// Primärer, interaktiver Caloric-Blauton (lesbar auf Weiß).
    static let accentBlue = Color(red: 0x11/255, green: 0x9B/255, blue: 0xE8/255)   // #119BE8
    /// Original-Markenton — für Gradients, Halos und Highlights.
    static let accentSky  = Color(red: 0x66/255, green: 0xCC/255, blue: 0xFF/255)   // #66CCFF
    /// Dunkler Verlauf-Endpunkt / Pressed-States.
    static let accentDeep = Color(red: 0x0B/255, green: 0x7B/255, blue: 0xC4/255)   // #0B7BC4

    /// Signatur-Verlauf der App (Ringe, CTAs, aktive Flächen).
    static let accentGradient = LinearGradient(
        colors: [accentSky, accentBlue],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: - Helle Oberfläche ("Ice")
    static let canvas     = Color(red: 0.937, green: 0.965, blue: 0.984)   // #EFF6FB
    static let canvasLift = Color(red: 0.984, green: 0.992, blue: 1.000)   // #FBFDFF
    static let card       = Color.white
    static let ink        = Color(red: 0.055, green: 0.129, blue: 0.180)   // #0E212E
    static let slate      = Color(red: 0.365, green: 0.443, blue: 0.514)   // #5D7183

    static let textPrimary   = ink
    static let textSecondary = slate

    /// Hairline-Kontur für Karten & Kapseln.
    static let cardStroke = ink.opacity(0.06)
    /// Fläche für Eingabefelder / eingelassene Flächen.
    static let fieldFill  = ink.opacity(0.04)
    /// Trennlinien.
    static let divider    = ink.opacity(0.08)
    /// Fortschritts-Tracks.
    static let trackFill  = ink.opacity(0.06)
    /// Weicher, blau getönter Kartenschatten.
    static let cardShadow = accentDeep.opacity(0.10)

    // Kompatibilitäts-Aliasse (ehem. Dark-Shell) — zeigen auf die helle Fläche.
    static let obsidian     = canvas
    static let obsidianLift = canvasLift
    static let glassFill    = ink.opacity(0.03)
    static let glassStroke  = ink.opacity(0.07)

    /// Energie-Komponenten — auf hellem Grund abgestimmte, satte Töne.
    static let segBMR  = accentBlue                                        // Azure
    static let segNEAT = Color(red: 0.07, green: 0.71, blue: 0.53)         // Grün   #12B587
    static let segEAT  = Color(red: 0.36, green: 0.42, blue: 0.94)         // Indigo #5C6BF0
    static let segTEF  = Color(red: 0.60, green: 0.36, blue: 0.94)         // Violett #9A5CF0
    static let segCaf  = Color(red: 0.95, green: 0.60, blue: 0.07)         // Amber  #F29912

    // MARK: - Wiederverwendbare Spacing-Tokens (Onboarding & Dashboard)
    enum Space {
        static let xs: CGFloat = 6
        static let s: CGFloat = 10
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        /// Standard-Seitenrand für Inhalts-Container.
        static let screenH: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 16
        static let card: CGFloat = 22
        static let hero: CGFloat = 26
        static let pill: CGFloat = 12
    }
}

// MARK: - Primär-Button (Caloric-Verlauf)
// Einheitlicher CTA-Stil über die gesamte App hinweg.
struct CaloricPrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accentBlue
    var fullWidth: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 34)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.accentSky, tint],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: tint.opacity(isEnabled ? 0.32 : 0), radius: 14, x: 0, y: 7)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CaloricPrimaryButtonStyle {
    static var caloricPrimary: CaloricPrimaryButtonStyle { CaloricPrimaryButtonStyle() }
    static func caloricPrimary(fullWidth: Bool) -> CaloricPrimaryButtonStyle {
        CaloricPrimaryButtonStyle(fullWidth: fullWidth)
    }
}

// MARK: - Heller App-Hintergrund
// Kühler Eis-Verlauf mit einem weichen Caloric-Blau-Halo am oberen Rand.
struct CaloricBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.canvasLift, Theme.canvas],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Theme.accentSky.opacity(0.18), .clear],
                center: .top, startRadius: 0, endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

/// Kompatibilitäts-Alias: alte Call-Sites der Dark-Shell rendern jetzt hell.
typealias ObsidianBackground = CaloricBackground

// MARK: - Karten-Oberfläche
// Weiße Karte mit Hairline-Kontur und weichem, blau getöntem Schatten.
// Drop-in-Ersatz für die frühere Glas-Optik (API unverändert).
struct GlassCardBackground: View {
    var cornerRadius: CGFloat = Theme.Radius.card
    /// Optionale Akzent-Tönung — für Hero-/aktive Flächen.
    var tint: Color = .clear
    var tintStrength: Double = 0.0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(tintStrength))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1)
            )
            .shadow(color: Theme.cardShadow, radius: 18, x: 0, y: 8)
    }
}

// MARK: - Fortschrittsbalken
// Heller, eingelassener Track mit Verlaufsfüllung und Indikator-Punkt.
struct InstrumentProgressBar: View {
    let progress: Double // 0.0 to 1.0
    let color: Color
    var height: CGFloat = 5
    var showScale: Bool = true

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let width = geo.size.width
                let fillWidth = width * min(1.0, max(0, progress))

                ZStack(alignment: .leading) {
                    // Track (eingelassen)
                    Capsule()
                        .fill(Theme.trackFill)
                        .frame(height: height)

                    // Füllung (Verlauf)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.55), color],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth, height: height)

                    // Indikator-Punkt
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().strokeBorder(color, lineWidth: 1.5))
                        .frame(width: height + 4, height: height + 4)
                        .shadow(color: color.opacity(0.35), radius: 3, x: 0, y: 1)
                        .offset(x: max(0, fillWidth - (height + 4) / 2))
                }
            }
            .frame(height: height + 4)

            if showScale {
                // Feine Skalen-Markierungen
                HStack(spacing: 0) {
                    ForEach(0...10, id: \.self) { i in
                        Rectangle()
                            .fill(Theme.ink.opacity(i % 5 == 0 ? 0.14 : 0.07))
                            .frame(width: 1, height: i % 5 == 0 ? 4 : 2)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }
}

extension View {
    /// Legt die Standard-Kartenoberfläche hinter eine View.
    func glassCard(_ cornerRadius: CGFloat = Theme.Radius.card,
                   tint: Color = .clear, tintStrength: Double = 0.0) -> some View {
        background(GlassCardBackground(cornerRadius: cornerRadius,
                                       tint: tint, tintStrength: tintStrength))
    }
}

// MARK: - Responsive Layout Metrics
// Skaliert UI-Elemente proportional zur Bildschirmhöhe.
// Referenz: iPhone 14 (844 pt). Minimum: 80 % der Originalgröße.
enum LayoutMetrics {
    private static let referenceHeight: CGFloat = 844

    static var scale: CGFloat {
        let h = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.height ?? referenceHeight
        return max(0.80, min(1.0, h / referenceHeight))
    }

    static var ringSize: CGFloat       { (140 * scale).rounded() }
    static var chartHeight: CGFloat    { (110 * scale).rounded() }
    static var cardSpacing: CGFloat    { (10  * scale).rounded() }
    static var sectionSpacing: CGFloat { (14  * scale).rounded() }
    static var titleFontSize: CGFloat  { (30  * scale).rounded() }
}
