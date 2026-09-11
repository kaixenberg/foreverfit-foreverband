import SwiftUI

public struct PermissionsView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("What ForeverFit can currently access. All sensor data is processed directly on your iPhone without cloud transfer.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))

                VStack(spacing: 10) {
                    permRow(icon: "antenna.radiowaves.left.and.right", name: "Bluetooth LE", status: "Active", desc: "For scanning and streaming ForeverBand vitals.")
                    permRow(icon: "location.fill", name: "Location", status: "While Using", desc: "For real-time disaster hazard map and emergency GPS.")
                    permRow(icon: "figure.walk", name: "Motion & Fitness", status: "Active", desc: "For 20Hz phone fall detector CNN and step counter.")
                    permRow(icon: "bell.badge.fill", name: "Notifications", status: "Active", desc: "For vital alerts, hazard alarms, and emergency countdowns.")
                    permRow(icon: "mic.fill", name: "Microphone", status: "Optional", desc: "For voice input to the on-device Gemma 4 E2B AI assistant.")
                    permRow(icon: "camera.fill", name: "Camera & Photos", status: "Optional", desc: "For attaching medical documents and photos to AI chat.")
                }
            }
            .padding(16)
        }
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
        .background(MeshGradientBackground())
    }

    private func permRow(icon: String, name: String, status: String, desc: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(LiquidGlassTheme.neonCyan)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                    Spacer()
                    Text(status)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LiquidGlassTheme.emeraldGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(LiquidGlassTheme.emeraldGreen.opacity(0.15)))
                }
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }
}
