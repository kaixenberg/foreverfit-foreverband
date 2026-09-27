import SwiftUI
import UserNotifications

public struct DeveloperDemoView: View {
    @ObservedObject var dataStore: HealthDataStore
    @ObservedObject var fallDetector: FallDetectorService
    private weak var bleManager: ForeverBandBLEManager?

    @State private var showingEmergencyPreview: Bool = false
    @State private var showingHazardWarning: HazardType? = nil
    @State private var lockScreenDemoCountdown: Int = 0
    @State private var timer: Timer? = nil

    public init(dataStore: HealthDataStore, fallDetector: FallDetectorService, bleManager: ForeverBandBLEManager? = nil) {
        self.dataStore = dataStore
        self.fallDetector = fallDetector
        self.bleManager = bleManager
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Body-temp contact check section (matches upstream 2a6cb61)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Body-Temp Contact Check")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .textCase(.uppercase)

                    Text(dataStore.watchSettings.ignoreBodyTempContactCheck
                         ? "OFF — body temp is reported without confirming finger/wrist contact first, e.g. when the SpO2 sensor is unavailable. The low/high body-temp warning is disabled while this is on, since an unverified reading could just be the watch lying on a table — you'll still see the raw number, just no warning from it."
                         : "ON (default) — body temp only counts as a real reading once the MAX30102 also detects finger/wrist contact, same signal HR/SpO2 already use, plus a 1-minute settle time after connecting for the DS18B20 to reach the wrist's temperature. Prevents a false low/high body-temp warning from a watch that isn't being worn.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.75))

                    Toggle("Ignore body-temp contact check", isOn: Binding(
                        get: { dataStore.watchSettings.ignoreBodyTempContactCheck },
                        set: { val in
                            var updated = dataStore.watchSettings
                            updated.ignoreBodyTempContactCheck = val
                            dataStore.saveWatchSettings(updated)
                            bleManager?.updateWatchSettings(updated)
                        }
                    ))
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))

                    Button {
                        sendTestMedicationReminder()
                    } label: {
                        HStack {
                            Image(systemName: "bell.badge.fill")
                            Text("Send test medication reminder now")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LiquidGlassTheme.neonCyan)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                    }

                    Text("Fires immediately on the same channel a real dose-time reminder uses — a quick sanity check that notifications actually post on this device/OS build.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                // Test Mode Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Test Mode")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .textCase(.uppercase)

                    Text(dataStore.mockMode
                         ? "ON — a triggered emergency simulates calls/SMS with spoken TTS instead of placing real phone calls. Safe for hackathon demonstrations."
                         : "OFF — a triggered emergency will place REAL phone calls to 112 and your contact.")
                        .font(.system(size: 12))
                        .foregroundStyle(dataStore.mockMode ? Color.white.opacity(0.7) : LiquidGlassTheme.alertCrimson)

                    Toggle("Test Mode (Simulate Calls/SMS)", isOn: Binding(
                        get: { dataStore.mockMode },
                        set: { dataStore.setMockMode($0) }
                    ))
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))

                    if dataStore.mockMode {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Simulated contact answers on attempt:")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.8))

                            HStack(spacing: 8) {
                                ForEach([1, 2, 3, 4, 5], id: \.self) { n in
                                    Button {
                                        dataStore.setMockAnswerOnAttempt(n)
                                    } label: {
                                        Text("\(n)")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(dataStore.mockAnswerOnAttempt == n ? Color.black : Color.white)
                                            .frame(width: 38, height: 34)
                                            .background(dataStore.mockAnswerOnAttempt == n ? LiquidGlassTheme.neonCyan : Color.white.opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }

                                Button {
                                    dataStore.setMockAnswerOnAttempt(nil)
                                } label: {
                                    Text("Never (SMS)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(dataStore.mockAnswerOnAttempt == nil ? Color.black : Color.white)
                                        .padding(.horizontal, 10)
                                        .frame(height: 34)
                                        .background(dataStore.mockAnswerOnAttempt == nil ? LiquidGlassTheme.amberWarning : Color.white.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    }
                }

                // Previews Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Previews & Escalations")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .textCase(.uppercase)

                    Button {
                        showingEmergencyPreview = true
                    } label: {
                        HStack {
                            Image(systemName: "cross.case.fill")
                            Text("Preview Emergency Workflow Screen")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                    }

                    Button {
                        triggerLockScreenDemo()
                    } label: {
                        HStack {
                            Image(systemName: "timer")
                            Text(lockScreenDemoCountdown > 0 ? "Triggering in \(lockScreenDemoCountdown)s (Lock your phone now!)" : "Trigger Lock-Screen SOS Escalation")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(lockScreenDemoCountdown > 0 ? LiquidGlassTheme.amberWarning : LiquidGlassTheme.neonCyan)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                    }
                }

                // Full Screen Hazard Previews
                VStack(alignment: .leading, spacing: 10) {
                    Text("Full-Screen Hazard Previews")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .textCase(.uppercase)

                    ForEach(HazardType.allCases) { hazard in
                        Button {
                            showingHazardWarning = hazard
                        } label: {
                            HStack {
                                Image(systemName: hazard.iconName)
                                    .foregroundStyle(LiquidGlassTheme.alertCrimson)
                                    .frame(width: 24)
                                Text("Preview \(hazard.title) Warning")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.white.opacity(0.4))
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Developer / Demo")
        .navigationBarTitleDisplayMode(.inline)
        .background(MeshGradientBackground())
        .fullScreenCover(item: $showingHazardWarning) { hazard in
            ImminentWarningView(hazards: [hazard], reason: "Demonstration preview — no real disaster detected")
        }
        .sheet(isPresented: $showingEmergencyPreview) {
            EmergencyCallView(workflow: EmergencyWorkflowService.shared)
        }
    }

    private func sendTestMedicationReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Test medication reminder"
        content.body = "If you see this, medication reminders can post successfully on this iOS device."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "test_medication_reminder", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func triggerLockScreenDemo() {
        guard lockScreenDemoCountdown == 0 else { return }
        lockScreenDemoCountdown = 10
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if lockScreenDemoCountdown > 1 {
                lockScreenDemoCountdown -= 1
            } else {
                timer?.invalidate()
                timer = nil
                lockScreenDemoCountdown = 0
                fallDetector.simulateFallDetection()
            }
        }
    }
}
