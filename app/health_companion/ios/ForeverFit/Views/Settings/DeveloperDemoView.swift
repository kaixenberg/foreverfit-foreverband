import SwiftUI

public struct DeveloperDemoView: View {
    @ObservedObject var dataStore: HealthDataStore
    @ObservedObject var fallDetector: FallDetectorService

    @State private var showingEmergencyPreview: Bool = false
    @State private var showingHazardWarning: HazardType? = nil
    @State private var lockScreenDemoCountdown: Int = 0
    @State private var timer: Timer? = nil

    public init(dataStore: HealthDataStore, fallDetector: FallDetectorService) {
        self.dataStore = dataStore
        self.fallDetector = fallDetector
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
