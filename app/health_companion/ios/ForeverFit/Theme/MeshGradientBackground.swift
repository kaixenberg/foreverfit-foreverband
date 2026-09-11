import SwiftUI

/// Dynamic, breathing MeshGradient backdrop for iOS 18–27.
/// Dynamically shifts colors based on system health status (Normal, Caution, Emergency Alert).
public struct MeshGradientBackground: View {
    public enum Mood {
        case normal
        case caution
        case emergency
        case aiAssistant
    }

    var mood: Mood = .normal
    @State private var phase: CGFloat = 0

    public init(mood: Mood = .normal) {
        self.mood = mood
    }

    public var body: some View {
        ZStack {
            // Deep base background
            Color(red: 0.03, green: 0.05, blue: 0.09)
                .ignoresSafeArea()

            // iOS 18+ MeshGradient
            if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: meshPoints,
                    colors: meshColors
                )
                .opacity(0.65)
                .blur(radius: 40)
                .ignoresSafeArea()
            } else {
                // Smooth fallback for earlier revisions
                RadialGradient(
                    colors: [fallbackAccentColor.opacity(0.35), Color.clear],
                    center: .center,
                    startRadius: 50,
                    endRadius: 400
                )
                .blur(radius: 60)
                .ignoresSafeArea()
            }

            // Liquid noise overlay & subtle ambient vignette
            LinearGradient(
                colors: [Color.black.opacity(0.2), Color.clear, Color.black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                phase = .pi * 2
            }
        }
    }

    private var meshPoints: [SIMD2<Float>] {
        let p = Float(phase)
        return [
            SIMD2<Float>(0.0, 0.0),
            SIMD2<Float>(0.5 + 0.1 * sin(p), 0.0),
            SIMD2<Float>(1.0, 0.0),
            SIMD2<Float>(0.0, 0.5 + 0.08 * cos(p)),
            SIMD2<Float>(0.5 + 0.1 * cos(p), 0.5 + 0.1 * sin(p)),
            SIMD2<Float>(1.0, 0.5 - 0.08 * sin(p)),
            SIMD2<Float>(0.0, 1.0),
            SIMD2<Float>(0.5 - 0.1 * sin(p), 1.0),
            SIMD2<Float>(1.0, 1.0)
        ]
    }

    private var meshColors: [Color] {
        switch mood {
        case .normal:
            return [
                Color(red: 0.02, green: 0.15, blue: 0.12),
                Color(red: 0.03, green: 0.08, blue: 0.20),
                Color(red: 0.02, green: 0.18, blue: 0.14),
                Color(red: 0.01, green: 0.05, blue: 0.10),
                LiquidGlassTheme.emeraldGreen.opacity(0.25),
                Color(red: 0.00, green: 0.20, blue: 0.25),
                Color(red: 0.03, green: 0.06, blue: 0.12),
                LiquidGlassTheme.neonCyan.opacity(0.20),
                Color(red: 0.01, green: 0.03, blue: 0.08)
            ]
        case .caution:
            return [
                Color(red: 0.18, green: 0.10, blue: 0.02),
                Color(red: 0.03, green: 0.05, blue: 0.12),
                Color(red: 0.15, green: 0.08, blue: 0.01),
                Color(red: 0.02, green: 0.04, blue: 0.08),
                LiquidGlassTheme.amberWarning.opacity(0.30),
                Color(red: 0.10, green: 0.05, blue: 0.01),
                Color(red: 0.02, green: 0.03, blue: 0.06),
                LiquidGlassTheme.amberWarning.opacity(0.20),
                Color(red: 0.01, green: 0.02, blue: 0.05)
            ]
        case .emergency:
            return [
                Color(red: 0.28, green: 0.03, blue: 0.05),
                Color(red: 0.15, green: 0.01, blue: 0.02),
                Color(red: 0.30, green: 0.04, blue: 0.06),
                Color(red: 0.05, green: 0.01, blue: 0.02),
                LiquidGlassTheme.alertCrimson.opacity(0.40),
                Color(red: 0.20, green: 0.02, blue: 0.03),
                Color(red: 0.04, green: 0.01, blue: 0.02),
                LiquidGlassTheme.alertCrimson.opacity(0.25),
                Color(red: 0.02, green: 0.00, blue: 0.01)
            ]
        case .aiAssistant:
            return [
                Color(red: 0.12, green: 0.04, blue: 0.22),
                Color(red: 0.03, green: 0.06, blue: 0.18),
                Color(red: 0.15, green: 0.05, blue: 0.25),
                Color(red: 0.02, green: 0.04, blue: 0.12),
                LiquidGlassTheme.violetGlow.opacity(0.35),
                LiquidGlassTheme.neonCyan.opacity(0.20),
                Color(red: 0.03, green: 0.04, blue: 0.10),
                LiquidGlassTheme.violetGlow.opacity(0.25),
                Color(red: 0.01, green: 0.02, blue: 0.07)
            ]
        }
    }

    private var fallbackAccentColor: Color {
        switch mood {
        case .normal: return LiquidGlassTheme.emeraldGreen
        case .caution: return LiquidGlassTheme.amberWarning
        case .emergency: return LiquidGlassTheme.alertCrimson
        case .aiAssistant: return LiquidGlassTheme.violetGlow
        }
    }
}
