import SwiftUI

public struct UnitsSettingsView: View {
    @ObservedObject var dataStore: HealthDataStore

    public init(dataStore: HealthDataStore) {
        self.dataStore = dataStore
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your data is always stored in metric — this only changes how values are shown and how you type new entries. Applies to weight, height, hydration, temperature, and wind speed.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.horizontal, 4)

                VStack(spacing: 8) {
                    ForEach(UnitSystem.allCases, id: \.self) { system in
                        Button {
                            dataStore.setUnitSystem(system)
                        } label: {
                            HStack {
                                Text(system.displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.white)
                                Spacer()
                                if dataStore.unitSystem == system {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(LiquidGlassTheme.neonCyan)
                                }
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(dataStore.unitSystem == system ? LiquidGlassTheme.neonCyan : Color.clear, lineWidth: 1.5)
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Units")
        .navigationBarTitleDisplayMode(.inline)
        .background(MeshGradientBackground())
    }
}
