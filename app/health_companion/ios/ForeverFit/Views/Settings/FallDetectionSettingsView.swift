import SwiftUI

public struct FallDetectionSettingsView: View {
    @ObservedObject var fallDetector: FallDetectorService
    @ObservedObject var dataStore: HealthDataStore

    public init(fallDetector: FallDetectorService, dataStore: HealthDataStore) {
        self.fallDetector = fallDetector
        self.dataStore = dataStore
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Watches your phone's motion for a fall while the app is active, using an on-device lightweight 1D-CNN model — zero data leaves your iPhone. If a possible fall is detected, you get a 10-second countdown to tap 'I'm OK' before help is summoned.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))

                Toggle(isOn: Binding(
                    get: { fallDetector.isRunning },
                    set: { val in
                        dataStore.setFallDetectionEnabled(val)
                        if val {
                            fallDetector.start()
                        } else {
                            fallDetector.stop()
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Detect Falls")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text(fallDetector.isRunning ? "Active & Monitoring at 20Hz" : "Paused")
                            .font(.system(size: 12))
                            .foregroundStyle(fallDetector.isRunning ? LiquidGlassTheme.emeraldGreen : Color.white.opacity(0.5))
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Try the Demo")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .textCase(.uppercase)

                    Text("Previews exactly what a real detected fall looks like — the audio alert, screen wake, and 10-second 'I'm OK' countdown — without needing to drop your phone. Safe to test: always forced into test mode.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.75))

                    Button {
                        fallDetector.simulateFallDetection()
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Trigger Fall Detection Demo")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(LiquidGlassTheme.alertCrimson)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 16).stroke(LiquidGlassTheme.alertCrimson, lineWidth: 1.5))
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
            }
            .padding(16)
        }
        .navigationTitle("Fall Detection")
        .navigationBarTitleDisplayMode(.inline)
        .background(MeshGradientBackground())
    }
}
