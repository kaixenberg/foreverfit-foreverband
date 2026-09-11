import SwiftUI

public struct AppearanceSettingsView: View {
    @ObservedObject var dataStore: HealthDataStore

    public init(dataStore: HealthDataStore) {
        self.dataStore = dataStore
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .textCase(.uppercase)

                    VStack(spacing: 8) {
                        ForEach(AppThemeMode.allCases, id: \.self) { mode in
                            Button {
                                dataStore.setThemeMode(mode)
                            } label: {
                                HStack {
                                    Text(mode.displayName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                    Spacer()
                                    if dataStore.themeMode == mode {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(LiquidGlassTheme.neonCyan)
                                    }
                                }
                                .padding(16)
                                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                            }
                        }
                    }
                }

                Divider().overlay(Color.white.opacity(0.15))

                Toggle(isOn: Binding(
                    get: { dataStore.oledBlack },
                    set: { dataStore.setOledBlack($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OLED Black")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text("True black backgrounds — maximizes battery life on Super Retina OLED displays.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
            }
            .padding(16)
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .background(MeshGradientBackground())
    }
}
