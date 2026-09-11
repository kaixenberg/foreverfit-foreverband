import SwiftUI

public struct SensorPrecedenceView: View {
    @ObservedObject var dataStore: HealthDataStore

    public init(dataStore: HealthDataStore) {
        self.dataStore = dataStore
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("When both sources are available, which one should the Ambient temp, Humidity, and Pressure cards prioritize?")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))

                VStack(spacing: 10) {
                    ForEach(AmbientSourcePreference.allCases, id: \.self) { pref in
                        Button {
                            dataStore.setAmbientSourcePreference(pref)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: pref == .preferWearable ? "applewatch" : "cloud.sun.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(LiquidGlassTheme.neonCyan)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(pref.title)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Color.white)
                                    Text(pref.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.white.opacity(0.7))
                                }

                                Spacer()

                                if dataStore.ambientSourcePreference == pref {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(LiquidGlassTheme.neonCyan)
                                }
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(dataStore.ambientSourcePreference == pref ? LiquidGlassTheme.neonCyan : Color.clear, lineWidth: 1.5)
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Sensor Precedence")
        .navigationBarTitleDisplayMode(.inline)
        .background(MeshGradientBackground())
    }
}
