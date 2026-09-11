import SwiftUI

public struct AboutView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // App Icon & Header
                VStack(spacing: 10) {
                    if let iconImg = UIImage(named: "AppIcon") {
                        Image(uiImage: iconImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(color: LiquidGlassTheme.neonCyan.opacity(0.4), radius: 10)
                    } else {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(LiquidGlassTheme.neonCyan)
                            .frame(width: 88, height: 88)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    Text("ForeverFit")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white)

                    Text("Version 1.0.0 (SIH 2026)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .padding(.top, 16)

                // Mission Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("About the Project")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .textCase(.uppercase)

                    Text("A privacy-preserving, offline-first personal health companion. A wearable streams vitals and environment sensor data to your phone over Bluetooth, which does all the processing on-device — fall detection, disaster warnings, and emergency calling all work without a cloud dependency. Built for Smart India Hackathon 2026, Problem ID 26181.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineSpacing(3)
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))

                // Source Link
                VStack(alignment: .leading, spacing: 10) {
                    Text("Source & Repository")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .textCase(.uppercase)

                    Link(destination: URL(string: "https://gitlab.com/kaixenberg/foreverfit-foreverband")!) {
                        HStack {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .foregroundStyle(LiquidGlassTheme.neonCyan)
                            Text("GitLab Repository")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.white)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    }
                }

                // Credits
                VStack(alignment: .leading, spacing: 10) {
                    Text("Credits")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .textCase(.uppercase)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Team ABBOY")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.white)
                            Text("Smart India Hackathon 2026")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
                }
            }
            .padding(16)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .background(MeshGradientBackground())
    }
}
