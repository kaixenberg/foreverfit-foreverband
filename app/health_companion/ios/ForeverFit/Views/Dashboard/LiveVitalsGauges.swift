import SwiftUI

/// Animated pulsating ECG wave line
public struct ECGWaveView: View {
    public let isActive: Bool
    @State private var phase: CGFloat = 0.0

    public init(isActive: Bool = true) {
        self.isActive = isActive
    }

    public var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                let midY = h / 2.0

                path.move(to: CGPoint(x: 0, y: midY))

                if isActive {
                    for x in stride(from: 0, through: w, by: 4) {
                        let progress = (x / w) + phase
                        let normalized = progress.truncatingRemainder(dividingBy: 1.0)
                        var yOffset: CGFloat = 0.0

                        if normalized > 0.40 && normalized < 0.44 {
                            yOffset = -h * 0.20 // P wave
                        } else if normalized > 0.48 && normalized < 0.50 {
                            yOffset = h * 0.15 // Q dip
                        } else if normalized >= 0.50 && normalized <= 0.54 {
                            yOffset = -h * 0.45 // R spike
                        } else if normalized > 0.54 && normalized < 0.57 {
                            yOffset = h * 0.25 // S dip
                        } else if normalized > 0.62 && normalized < 0.70 {
                            yOffset = -h * 0.18 // T wave
                        }

                        path.addLine(to: CGPoint(x: x, y: midY + yOffset))
                    }
                } else {
                    // Flat line when inactive/disconnected
                    path.addLine(to: CGPoint(x: w, y: midY))
                }
            }
            .stroke(
                isActive ? LinearGradient(
                    colors: [
                        LiquidGlassTheme.alertCrimson.opacity(0.1),
                        LiquidGlassTheme.alertCrimson,
                        Color.white
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ) : LinearGradient(
                    colors: [Color.white.opacity(0.2), Color.white.opacity(0.3)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: isActive ? LiquidGlassTheme.alertCrimson.opacity(0.8) : .clear, radius: 6, x: 0, y: 0)
        }
        .onAppear {
            if isActive {
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
        }
    }
}

/// Circular Wellness Score Indicator (0–100)
public struct WellnessScoreRing: View {
    public let score: Int?

    public init(score: Int?) {
        self.score = score
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 8)

            Circle()
                .trim(from: 0, to: CGFloat(score ?? 0) / 100.0)
                .stroke(
                    AngularGradient(
                        colors: [
                            scoreColor.opacity(0.4),
                            scoreColor,
                            scoreColor.opacity(0.9)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: score != nil ? scoreColor.opacity(0.5) : .clear, radius: 8, x: 0, y: 0)

            VStack(spacing: 0) {
                if let s = score {
                    Text("\(s)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                    Text("SCORE")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.0)
                        .foregroundStyle(scoreColor)
                } else {
                    Text("--")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
        }
        .frame(width: 76, height: 76)
    }

    private var scoreColor: Color {
        guard let s = score else { return Color.white.opacity(0.2) }
        if s >= 85 { return LiquidGlassTheme.emeraldGreen }
        if s >= 65 { return LiquidGlassTheme.amberWarning }
        return LiquidGlassTheme.alertCrimson
    }
}
