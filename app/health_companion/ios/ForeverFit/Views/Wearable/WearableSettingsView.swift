import SwiftUI

public struct WearableSettingsView: View {
    @ObservedObject var bleManager: ForeverBandBLEManager
    @ObservedObject var dataStore: HealthDataStore
    @State private var showingSyncConfirmation = false

    public init(bleManager: ForeverBandBLEManager, dataStore: HealthDataStore) {
        self.bleManager = bleManager
        self.dataStore = dataStore
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Header
                headerSection

                // Live OLED Simulation Screen
                OLEDWatchFacePreview(
                    settings: dataStore.watchSettings,
                    vitals: bleManager.latestVitals,
                    env: bleManager.latestEnv
                )
                .padding(.vertical, 8)

                // Time Sync Action Pill
                timeSyncActionPill

                // Watch Face Selection
                watchFaceSelectionCard

                // Time & Date Format Settings
                formatSettingsCard

                // Auto-Cycle Settings
                autoCycleCard
            }
            .padding()
            .padding(.bottom, 100)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ESP32-S3 WEARABLE FIRMWARE")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(LiquidGlassTheme.neonCyan)

            Text("ForeverBand Watch")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(Color.white)

            Text("Configure OLED layouts, display clocks, and push 7-byte settings packets.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeSyncActionPill: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            bleManager.syncTimeToWatch()
            withAnimation {
                showingSyncConfirmation = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation {
                    showingSyncConfirmation = false
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .bold))
                Text(showingSyncConfirmation ? "Time Synchronized!" : "Sync iPhone Clock to Watch")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(showingSyncConfirmation ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                Capsule()
                    .fill(showingSyncConfirmation ? LiquidGlassTheme.emeraldGreen : LiquidGlassTheme.neonCyan)
                    .shadow(color: (showingSyncConfirmation ? LiquidGlassTheme.emeraldGreen : LiquidGlassTheme.neonCyan).opacity(0.4), radius: 10, x: 0, y: 4)
            }
        }
        .buttonStyle(.plain)
    }

    private var watchFaceSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTIVE OLED WATCH FACE")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.5))

            HStack(spacing: 12) {
                faceOptionButton(face: .primary, title: "Face 1: Vitals Clock")
                faceOptionButton(face: .secondary, title: "Face 2: Sensor Radar")
            }
        }
        .padding()
        .liquidGlass()
    }

    private func faceOptionButton(face: WatchFace, title: String) -> some View {
        let isSelected = dataStore.watchSettings.selectedFace == face
        return Button {
            dataStore.watchSettings.selectedFace = face
            pushSettings()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.black : Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    Capsule()
                        .fill(isSelected ? Color.white : Color.white.opacity(0.08))
                }
        }
        .buttonStyle(.plain)
    }

    private var formatSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DISPLAY FORMAT PREFERENCES")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.5))

            Toggle("24-Hour Military Time", isOn: Binding(
                get: { dataStore.watchSettings.use24HourFormat },
                set: { dataStore.watchSettings.use24HourFormat = $0; pushSettings() }
            ))
            .tint(LiquidGlassTheme.neonCyan)

            Toggle("Show Seconds on OLED", isOn: Binding(
                get: { dataStore.watchSettings.showSeconds },
                set: { dataStore.watchSettings.showSeconds = $0; pushSettings() }
            ))
            .tint(LiquidGlassTheme.neonCyan)

            VStack(alignment: .leading, spacing: 6) {
                Text("Date Format")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))

                Picker("Date Format", selection: Binding(
                    get: { dataStore.watchSettings.dateFormat },
                    set: { dataStore.watchSettings.dateFormat = $0; pushSettings() }
                )) {
                    ForEach(WatchDateFormat.allCases) { df in
                        Text(df.label).tag(df)
                    }
                }
                .pickerStyle(.menu)
                .tint(LiquidGlassTheme.neonCyan)
            }
        }
        .padding()
        .liquidGlass()
    }

    private var autoCycleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AUTOMATIC FACE CYCLING")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.5))

            Toggle("Auto-Cycle Faces on Watch", isOn: Binding(
                get: { dataStore.watchSettings.autoCycleEnabled },
                set: { dataStore.watchSettings.autoCycleEnabled = $0; pushSettings() }
            ))
            .tint(LiquidGlassTheme.neonCyan)

            if dataStore.watchSettings.autoCycleEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cycle Interval: \(dataStore.watchSettings.autoCycleIntervalSeconds) seconds")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))

                    Slider(
                        value: Binding(
                            get: { Double(dataStore.watchSettings.autoCycleIntervalSeconds) },
                            set: { dataStore.watchSettings.autoCycleIntervalSeconds = UInt16($0); pushSettings() }
                        ),
                        in: 5...60,
                        step: 5
                    )
                    .tint(LiquidGlassTheme.neonCyan)
                }
            }
        }
        .padding()
        .liquidGlass()
    }

    private func pushSettings() {
        dataStore.saveWatchSettings(dataStore.watchSettings)
        bleManager.updateWatchSettings(dataStore.watchSettings)
    }
}
