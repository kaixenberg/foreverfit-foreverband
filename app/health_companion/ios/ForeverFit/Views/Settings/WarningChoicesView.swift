import SwiftUI

public struct WarningChoicesView: View {
    @ObservedObject var dataStore: HealthDataStore

    public init(dataStore: HealthDataStore) {
        self.dataStore = dataStore
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose which categories of in-app suggestions and notifications to receive. Note: full-screen imminent disaster warnings and 10s fall alerts always fire for user safety.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))

                VStack(spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { dataStore.notifyVitals },
                        set: { dataStore.setNotifyVitals($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Vitals & Wellness")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.white)
                            Text("Heart rate, SpO2, body temperature, blood pressure, glucose, and sleep anomalies.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))

                    Toggle(isOn: Binding(
                        get: { dataStore.notifyHazards },
                        set: { dataStore.setNotifyHazards($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Map & Disaster Hazards")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.white)
                            Text("Air quality alerts, flood and cyclone risks, and nearby earthquakes.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))

                    Toggle(isOn: Binding(
                        get: { dataStore.notifyReminders },
                        set: { dataStore.setNotifyReminders($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tracking Reminders")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.white)
                            Text("Hydration and scheduled medication doses.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                }
            }
            .padding(16)
        }
        .navigationTitle("Warning Choices")
        .navigationBarTitleDisplayMode(.inline)
        .background(MeshGradientBackground())
    }
}
