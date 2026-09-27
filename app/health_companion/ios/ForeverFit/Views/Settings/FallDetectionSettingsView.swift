import SwiftUI

public struct FallDetectionSettingsView: View {
    @ObservedObject var fallDetector: FallDetectorService
    @ObservedObject var dataStore: HealthDataStore
    private weak var bleManager: ForeverBandBLEManager?

    public init(fallDetector: FallDetectorService, dataStore: HealthDataStore, bleManager: ForeverBandBLEManager? = nil) {
        self.fallDetector = fallDetector
        self.dataStore = dataStore
        self.bleManager = bleManager
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Watches motion for a fall while the app is active, using an on-device lightweight 1D-CNN model — zero data leaves your iPhone. If a possible fall is detected, you get a 10-second countdown to tap 'I'm OK' before help is summoned.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))

                Toggle(isOn: Binding(
                    get: { fallDetector.isRunning },
                    set: { val in
                        dataStore.setFallDetectionEnabled(val)
                        if val {
                            fallDetector.start(
                                sensorSource: dataStore.fallDetectionSensorSource,
                                bleManager: bleManager
                            )
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

                // Sensor Source Section (matches Flutter upstream)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sensor Source")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)

                    Text("Phone uses only your phone's own motion sensors. Watch fuses the wearable's wrist motion with your phone's accelerometer — needs a connected wearable to produce any readings, and only runs while the app is open in the foreground; the background monitor always stays phone-only regardless of this setting.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.75))

                    VStack(spacing: 8) {
                        Button {
                            updateSensorSource(.phone)
                        } label: {
                            HStack {
                                Image(systemName: dataStore.fallDetectionSensorSource == .phone ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(dataStore.fallDetectionSensorSource == .phone ? LiquidGlassTheme.neonCyan : Color.white.opacity(0.5))
                                Text("Phone")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.white)
                                Spacer()
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(dataStore.fallDetectionSensorSource == .phone ? Color.white.opacity(0.12) : Color.white.opacity(0.05)))
                        }

                        Button {
                            updateSensorSource(.watch)
                        } label: {
                            HStack {
                                Image(systemName: dataStore.fallDetectionSensorSource == .watch ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(dataStore.fallDetectionSensorSource == .watch ? LiquidGlassTheme.neonCyan : Color.white.opacity(0.5))
                                Text("Watch (wrist + phone)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.white)
                                Spacer()
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(dataStore.fallDetectionSensorSource == .watch ? Color.white.opacity(0.12) : Color.white.opacity(0.05)))
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))

                // Try the Demo
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

    private func updateSensorSource(_ source: FallDetectionSensorSource) {
        dataStore.setFallDetectionSensorSource(source)
        if fallDetector.isRunning {
            fallDetector.stop()
            fallDetector.start(sensorSource: source, bleManager: bleManager)
        }
    }
}
