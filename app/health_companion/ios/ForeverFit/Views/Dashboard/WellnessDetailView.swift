import SwiftUI

public struct WellnessDetailView: View {
    public let snapshot: WellnessSnapshot
    @Environment(\.dismiss) private var dismiss

    public init(snapshot: WellnessSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Score Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snapshot.headline)
                                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                                    .foregroundStyle(LiquidGlassTheme.neonCyan)
                            }
                            Spacer()
                            if let score = snapshot.score {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Wellness")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.white.opacity(0.6))
                                    Text("\(score)/100")
                                        .font(.system(size: 24, weight: .black, design: .rounded))
                                        .foregroundStyle(scoreColor(score))
                                }
                            } else {
                                Text("--")
                                    .font(.system(size: 24, weight: .black, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.4))
                            }
                        }

                        Text(snapshot.summary)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineSpacing(3)
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial))

                    // Signals & Factors Breakdown
                    if !snapshot.factors.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Signals Breakdown")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.6))
                                .textCase(.uppercase)

                                ForEach(snapshot.factors) { factor in
                                    let icon: String = !factor.scored ? "minus.circle.fill" : (factor.warn ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                    let iconColor: Color = !factor.scored ? Color.white.opacity(0.4) : (factor.warn ? LiquidGlassTheme.alertCrimson : LiquidGlassTheme.emeraldGreen)

                                    HStack(alignment: .top, spacing: 14) {
                                        Image(systemName: icon)
                                            .font(.system(size: 20))
                                            .foregroundStyle(iconColor)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(factor.label)
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundStyle(Color.white)
                                            Text(factor.detail)
                                                .font(.system(size: 13))
                                                .foregroundStyle(Color.white.opacity(0.75))
                                                .lineSpacing(2)
                                        }
                                        Spacer()
                                    }
                                    .padding(16)
                                    .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
                                }
                            }
                        }

                    // Disclaimer Footer
                    Text("A transparent, explainable formula rather than a black-box model — starts at 100 and deducts points per signal currently outside healthy clinical parameters.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                .padding(16)
            }
            .navigationTitle("Wellness Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(LiquidGlassTheme.neonCyan)
                }
            }
            .background(MeshGradientBackground())
        }
    }

    private func scoreColor(_ s: Int) -> Color {
        if s >= 85 { return LiquidGlassTheme.emeraldGreen }
        if s >= 65 { return LiquidGlassTheme.amberWarning }
        return LiquidGlassTheme.alertCrimson
    }
}
