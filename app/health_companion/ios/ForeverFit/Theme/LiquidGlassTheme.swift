import SwiftUI

/// iOS 27 Liquid-Glass Design System for ForeverFit
/// Featuring refractive glass materials, chromatic specular highlights,
/// dynamic iridescent mesh gradients, and glowing neon accents.
public struct LiquidGlassTheme {
    // Primary Vibrant Accents
    public static let emeraldGreen = Color(red: 0.05, green: 0.88, blue: 0.48) // Normal vitals
    public static let neonCyan     = Color(red: 0.00, green: 0.86, blue: 1.00) // Tech & BLE
    public static let amberWarning = Color(red: 1.00, green: 0.69, blue: 0.12) // Cautions
    public static let alertCrimson = Color(red: 1.00, green: 0.23, blue: 0.26) // Fall & Hazard
    public static let violetGlow   = Color(red: 0.65, green: 0.35, blue: 1.00) // AI Assistant
    public static let electricViolet = violetGlow
    public static let statusNormal = emeraldGreen
    public static let deepIndigo   = Color(red: 0.04, green: 0.07, blue: 0.15) // Glass backdrop

    // Glass Shimmer & Border Gradients
    public static let glassRimGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.45),
            Color.white.opacity(0.10),
            Color.white.opacity(0.02),
            Color.white.opacity(0.25)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let emeraldGlowGradient = LinearGradient(
        colors: [emeraldGreen.opacity(0.8), neonCyan.opacity(0.6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let crimsonGlowGradient = LinearGradient(
        colors: [alertCrimson.opacity(0.9), amberWarning.opacity(0.7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let aiGlowGradient = LinearGradient(
        colors: [violetGlow.opacity(0.8), neonCyan.opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

public struct LiquidGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 24
    var highlightColor: Color = .white.opacity(0.15)
    var isInteractive: Bool = false

    @State private var isHovered = false

    public func body(content: Content) -> some View {
        content
            .padding()
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        highlightColor,
                                        Color.white.opacity(0.05),
                                        Color.white.opacity(0.02),
                                        highlightColor.opacity(0.6)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    }
                    .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 8)
                    .shadow(color: highlightColor.opacity(0.12), radius: 8, x: 0, y: 0)
            }
    }
}

public extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 24,
        highlightColor: Color = .white.opacity(0.15),
        isInteractive: Bool = false
    ) -> some View {
        self.modifier(LiquidGlassCardModifier(
            cornerRadius: cornerRadius,
            highlightColor: highlightColor,
            isInteractive: isInteractive
        ))
    }

    func liquidGlassCard(glowColor: Color = LiquidGlassTheme.neonCyan.opacity(0.2)) -> some View {
        self.liquidGlass(cornerRadius: 22, highlightColor: glowColor)
    }
}
