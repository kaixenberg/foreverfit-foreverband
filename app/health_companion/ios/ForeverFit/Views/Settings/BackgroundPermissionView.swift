import SwiftUI

public struct BackgroundPermissionView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Keep vital telemetry and fall detection active even while your iPhone screen is locked.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "battery.100.bolt")
                            .font(.system(size: 26))
                            .foregroundStyle(LiquidGlassTheme.neonCyan)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Background App Refresh")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.white)
                            Text("Enabled for continuous Bluetooth & Motion")
                                .font(.system(size: 12))
                                .foregroundStyle(LiquidGlassTheme.emeraldGreen)
                        }
                    }

                    Text("ForeverFit utilizes iOS Background Modes (Bluetooth central communication and CoreLocation significant monitoring) to process vital anomalies and latch emergency alerts when the app is minimized.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineSpacing(2)

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open iOS System Settings")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(LiquidGlassTheme.neonCyan)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
            }
            .padding(16)
        }
        .navigationTitle("Background Execution")
        .navigationBarTitleDisplayMode(.inline)
        .background(MeshGradientBackground())
    }
}
