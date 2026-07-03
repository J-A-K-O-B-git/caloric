//
//  Theme.swift
//  caloric
//
//  Zentrale Farb- und Stil-Definitionen
//

import SwiftUI

enum Theme {
    static let accentBlue = Color(red: 0x66/255, green: 0xCC/255, blue: 0xFF/255)

    // MARK: - Premium Dark Shell ("obsidian")
    // Deep, slightly-cool near-black base with a subtle top lift, plus a
    // harmonious cool accent set for the energy-expenditure breakdown.
    static let obsidian      = Color(red: 0.043, green: 0.047, blue: 0.055)   // ~#0B0C0E
    static let obsidianLift  = Color(red: 0.082, green: 0.090, blue: 0.106)   // ~#15171B
    static let glassFill     = Color.white.opacity(0.045)
    static let glassStroke   = Color.white.opacity(0.10)
    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.58)

    /// Energy-expenditure segment hues — shared chroma / high lightness.
    static let segBMR  = accentBlue                                            // #66CCFF
    static let segNEAT = Color(red: 0.36, green: 0.82, blue: 0.69)             // mint  #5CD1B0
    static let segEAT  = Color(red: 0.49, green: 0.55, blue: 1.00)             // peri  #7E8CFF
    static let segTEF  = Color(red: 0.76, green: 0.55, blue: 1.00)             // lilac #C28CFF
    static let segCaf  = Color(red: 1.00, green: 0.72, blue: 0.38)             // amber #FFB861

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
        static let card: CGFloat = 20
        static let hero: CGFloat = 24
        static let pill: CGFloat = 12
    }
}

// MARK: - Premium Primär-Button
// Einheitlicher CTA-Stil über das gesamte Onboarding hinweg.
// Inhaltsgrößen-basiert (kein erzwungenes Full-Width), damit bestehende
// Layouts nicht verschoben werden. Reiner optischer Feinschliff.
struct CaloricPrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accentBlue
    var fullWidth: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("PingFangSC-Medium", size: 18, relativeTo: .headline))
            .foregroundStyle(.white)
            .padding(.horizontal, 34)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(tint)
                    .shadow(color: tint.opacity(isEnabled ? 0.28 : 0), radius: 14, x: 0, y: 6)
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

// MARK: - Obsidian Background
// Full-bleed premium dark backdrop with a soft radial accent halo.
struct ObsidianBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.obsidianLift, Theme.obsidian],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Theme.accentBlue.opacity(0.10), .clear],
                center: .top, startRadius: 0, endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glassmorphic Card Surface
// Frosted translucent panel with a hairline light-to-dark edge stroke.
// Drop-in replacement for the old blue-tinted card fills.
struct GlassCardBackground: View {
    var cornerRadius: CGFloat = Theme.Radius.card
    /// Optional accent wash — used for the hero/active surfaces.
    var tint: Color = .clear
    var tintStrength: Double = 0.0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.glassFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(tintStrength))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Premium Instrument Progress Bar
// A more sophisticated, "technical instrument" style progress bar.
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
                    // Track (Recessed look)
                    Capsule()
                        .fill(Color.black.opacity(0.25))
                        .frame(height: height)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                    
                    // Fill (Glowing liquid look)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.5), color],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth, height: height)
                        .shadow(color: color.opacity(0.6), radius: 4, x: 0, y: 0)
                    
                    // Glow Bead (Indicator)
                    Circle()
                        .fill(Color.white)
                        .frame(width: height + 3, height: height + 3)
                        .shadow(color: color, radius: 5)
                        .shadow(color: color, radius: 2)
                        .offset(x: max(0, fillWidth - (height + 3) / 2))
                }
            }
            .frame(height: height + 3)
            
            if showScale {
                // Technical Scale Markings
                HStack(spacing: 0) {
                    ForEach(0...10, id: \.self) { i in
                        Rectangle()
                            .fill(Color.white.opacity(i % 5 == 0 ? 0.2 : 0.1))
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
    /// Wraps a view in the premium glass card surface.
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
