//
//  Theme.swift
//  caloric
//
//  Zentrale Farb- und Stil-Definitionen
//

import SwiftUI

enum Theme {
    static let accentBlue = Color(red: 0x66/255, green: 0xCC/255, blue: 0xFF/255)

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
