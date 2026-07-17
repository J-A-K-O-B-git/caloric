//
//  Theme.swift
//  caloric
//
//  Zentrale Farb- und Stil-Definitionen
//
//  Designsystem "Caloric Ice" — adaptives UI mit zwei Erscheinungsbildern:
//  · Hell:  kühler Eis-Hintergrund, weiße Karten, weiche blaue Schatten
//  · Dunkel: tiefe, kühle Fläche ("Caloric Night"), angehobene Karten
//  Beide teilen Poppins und die Caloric-Blau-Familie (Sky → Azure).
//  Der Modus ist über AppearanceMode /  umschaltbar
//  (System / Hell / Dunkel, gespeichert in AppStorage).
//

import SwiftUI

// MARK: - Adaptive Farb-Hilfe
private extension Color {
    /// Dynamische Farbe, die automatisch zwischen Hell- und Dunkelmodus wechselt.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

enum Theme {

    // MARK: - Caloric-Blau Familie (identisch in beiden Modi)
    /// Primärer, interaktiver Caloric-Blauton (lesbar auf Weiß & Dunkel).
    static let accentBlue = Color(red: 0x11/255, green: 0x9B/255, blue: 0xE8/255)   // #119BE8
    /// Original-Markenton — für Verläufe, Halos und Highlights.
    static let accentSky  = Color(red: 0x66/255, green: 0xCC/255, blue: 0xFF/255)   // #66CCFF
    /// Dunkler Verlauf-Endpunkt / Pressed-States.
    static let accentDeep = Color(red: 0x0B/255, green: 0x7B/255, blue: 0xC4/255)   // #0B7BC4

    /// Signatur-Verlauf der App (Ringe, CTAs, aktive Flächen).
    static let accentGradient = LinearGradient(
        colors: [accentSky, accentBlue],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: - Adaptive Oberfläche ("Ice" ↔ "Night")
    static let canvas = Color(
        light: Color(red: 0.937, green: 0.965, blue: 0.984),   // #EFF6FB
        dark:  Color(red: 0.043, green: 0.055, blue: 0.071)    // #0B0E12
    )
    static let canvasLift = Color(
        light: Color(red: 0.984, green: 0.992, blue: 1.000),   // #FBFDFF
        dark:  Color(red: 0.075, green: 0.098, blue: 0.133)    // #131922
    )
    static let card = Color(
        light: .white,
        dark:  Color(red: 0.086, green: 0.118, blue: 0.157)    // #161E28
    )
    /// "Tinte": dunkel im Hellmodus, hell im Dunkelmodus — Basis für
    /// Text, Hairlines, Tracks und eingelassene Flächen.
    static let ink = Color(
        light: Color(red: 0.055, green: 0.129, blue: 0.180),   // #0E212E
        dark:  Color(red: 0.929, green: 0.957, blue: 0.980)    // #EDF4FA
    )
    static let slate = Color(
        light: Color(red: 0.365, green: 0.443, blue: 0.514),   // #5D7183
        dark:  Color(red: 0.565, green: 0.635, blue: 0.702)    // #90A2B3
    )

    static let textPrimary   = ink
    static let textSecondary = slate

    /// Hairline-Kontur für Karten & Kapseln.
    static let cardStroke = Color(
        light: Color(red: 0.055, green: 0.129, blue: 0.180).opacity(0.06),
        dark:  Color.white.opacity(0.09)
    )
    /// Fläche für Eingabefelder / eingelassene Flächen.
    static let fieldFill = ink.opacity(0.05)
    /// Trennlinien.
    static let divider   = ink.opacity(0.09)
    /// Fortschritts-Tracks.
    static let trackFill = ink.opacity(0.07)
    /// Kartenschatten: hell = weich blau getönt, dunkel = tiefer Schwarz-Schatten.
    static let cardShadow = Color(
        light: Color(red: 0x0B/255, green: 0x7B/255, blue: 0xC4/255).opacity(0.10),
        dark:  Color.black.opacity(0.45)
    )

    // Kompatibilitäts-Aliasse (ehem. Dark-Shell) — zeigen auf die adaptive Fläche.
    static let obsidian     = canvas
    static let obsidianLift = canvasLift
    static let glassFill    = ink.opacity(0.03)
    static let glassStroke  = ink.opacity(0.07)

    /// Energie-Komponenten — funktionieren auf heller und dunkler Fläche.
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

// MARK: - Erscheinungsbild (System / Hell / Dunkel)

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "caloricAppearanceMode"

    var id: String { rawValue }

    /// nil = dem System folgen.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    func label(_ language: String) -> String {
        switch self {
        case .system: return language == "de" ? "System" : "System"
        case .light:  return language == "de" ? "Hell"   : "Light"
        case .dark:   return language == "de" ? "Dunkel" : "Dark"
        }
    }
}

/// Liest den gespeicherten Modus und wendet ihn als preferredColorScheme an.
/// Auf Root-Views und Sheets verwenden: ``.
struct CaloricAppearanceWrapper<Content: View>: View {
    @AppStorage(AppearanceMode.storageKey)
    private var modeRaw: String = AppearanceMode.system.rawValue
    let content: Content

    var body: some View {
        content.preferredColorScheme(
            (AppearanceMode(rawValue: modeRaw) ?? .system).colorScheme
        )
    }
}

extension View {
    /// Wendet das vom Nutzer gewählte Erscheinungsbild an (System/Hell/Dunkel).
    func caloricAppearance() -> some View {
        CaloricAppearanceWrapper(content: self)
    }
}

/// Segmentierter Umschalter für das Erscheinungsbild — überall einsetzbar,
/// wo Einstellungen angezeigt werden (Profil-Panel, Settings).
struct AppearancePicker: View {
    let language: String
    var accent: Color = Theme.accentBlue

    @AppStorage(AppearanceMode.storageKey)
    private var modeRaw: String = AppearanceMode.system.rawValue

    private var mode: AppearanceMode { AppearanceMode(rawValue: modeRaw) ?? .system }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppearanceMode.allCases) { m in
                let isSelected = m == mode
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        modeRaw = m.rawValue
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: m.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(m.label(language))
                            .font(.poppins(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isSelected ? .white : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        Group {
                            if isSelected {
                                Capsule().fill(
                                    LinearGradient(colors: [Theme.accentSky, accent],
                                                   startPoint: .topLeading,
                                                   endPoint: .bottomTrailing)
                                )
                                .shadow(color: accent.opacity(0.30), radius: 6, x: 0, y: 3)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Theme.fieldFill)
                .overlay(Capsule().strokeBorder(Theme.divider, lineWidth: 1))
        )
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
            .font(.poppins(size: 17, weight: .semibold))
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

// MARK: - Adaptiver App-Hintergrund
// Hell:   Eis-Verlauf mit weichem Caloric-Blau-Halo oben.
// Dunkel: tiefe, kühle Fläche mit dezentem Sky-Halo.
struct CaloricBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.canvasLift, Theme.canvas],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Theme.accentSky.opacity(colorScheme == .dark ? 0.10 : 0.18), .clear],
                center: .top, startRadius: 0, endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

/// Kompatibilitäts-Alias: alte Call-Sites rendern über die adaptive Fläche.
typealias ObsidianBackground = CaloricBackground

// MARK: - Karten-Oberfläche
// Hell:   weiße Karte, Hairline, weicher blauer Schatten.
// Dunkel: angehobene Night-Karte, helle Hairline, tiefer Schatten.
// API unverändert — Drop-in für alle `.glassCard()`-Call-Sites.
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
// Eingelassener Track mit Verlaufsfüllung und Indikator-Punkt (adaptiv).
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

// MARK: - SF Pro Font Helper
extension Font {
    static func poppins(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}
