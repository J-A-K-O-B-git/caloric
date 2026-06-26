//
//  ConfettiView.swift
//  caloric
//
//  Fallende bunte Partikel als Overlay-Animation
//

import SwiftUI

struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var animate = false

    private let colors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink,
        Color(red: 0x66/255, green: 0xCC/255, blue: 0xFF/255)
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size * 1.4)
                        .rotationEffect(.degrees(animate ? particle.spinEnd : particle.spinStart))
                        .position(
                            x: particle.x * geo.size.width,
                            y: animate ? geo.size.height + 50 : -50
                        )
                        .opacity(animate ? 0 : 1)
                        .animation(
                            .easeIn(duration: particle.duration)
                            .delay(particle.delay),
                            value: animate
                        )
                }
            }
            .onAppear {
                particles = (0..<80).map { _ in
                    ConfettiParticle(
                        color: colors.randomElement()!,
                        x: Double.random(in: 0...1),
                        size: Double.random(in: 6...12),
                        spinStart: Double.random(in: 0...180),
                        spinEnd: Double.random(in: 360...720),
                        duration: Double.random(in: 2.5...5.0),
                        delay: Double.random(in: 0...1.5)
                    )
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    animate = true
                }
            }
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    let color: Color
    let x: Double
    let size: Double
    let spinStart: Double
    let spinEnd: Double
    let duration: Double
    let delay: Double
}
