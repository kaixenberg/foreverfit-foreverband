import SwiftUI

public struct SettingsCategoryItem: Identifiable {
    public let id = UUID()
    public let icon: String
    public let title: String
    public let subtitle: String
    public let destination: AnyView

    public init<V: View>(icon: String, title: String, subtitle: String, destination: V) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.destination = AnyView(destination)
    }
}

public struct SettingsView: View {
    @ObservedObject var dataStore: HealthDataStore
    @ObservedObject var bleManager: ForeverBandBLEManager
    @ObservedObject var fallDetector: FallDetectorService
    @Environment(\.dismiss) private var dismiss

    public init(dataStore: HealthDataStore, bleManager: ForeverBandBLEManager, fallDetector: FallDetectorService) {
        self.dataStore = dataStore
        self.bleManager = bleManager
        self.fallDetector = fallDetector
    }

    private var categories: [SettingsCategoryItem] {
        [
            SettingsCategoryItem(
                icon: "person.fill",
                title: "Profile & Medical",
                subtitle: "Your info, blood type, allergies, conditions, weight, height",
                destination: ProfileMedicalView(dataStore: dataStore)
            ),
            SettingsCategoryItem(
                icon: "ruler.fill",
                title: "Units",
                subtitle: "Metric, Imperial, or match device locale",
                destination: UnitsSettingsView(dataStore: dataStore)
            ),
            SettingsCategoryItem(
                icon: "paintbrush.fill",
                title: "Appearance",
                subtitle: "Theme, OLED black, dynamic styling",
                destination: AppearanceSettingsView(dataStore: dataStore)
            ),
            SettingsCategoryItem(
                icon: "arrow.up.arrow.down.square.fill",
                title: "Data Export & Import",
                subtitle: "Back up or restore all your health data",
                destination: DataBackupView(dataStore: dataStore)
            ),
            SettingsCategoryItem(
                icon: "applewatch",
                title: "Wearable",
                subtitle: "Connect and manage ForeverBand devices",
                destination: WearableSettingsView(bleManager: bleManager, dataStore: dataStore)
            ),
            SettingsCategoryItem(
                icon: "sparkles",
                title: "AI Assistant",
                subtitle: "Optional, fully offline on-device Gemma 4 E2B chatbot",
                destination: AiAssistantSettingsView(modelManager: GemmaModelManager.shared)
            ),
            SettingsCategoryItem(
                icon: "slider.horizontal.3",
                title: "Sensor Precedence",
                subtitle: "Which source wins when more than one is available",
                destination: SensorPrecedenceView(dataStore: dataStore)
            ),
            SettingsCategoryItem(
                icon: "bell.badge.fill",
                title: "Warning Choices",
                subtitle: "Which notification categories to receive",
                destination: WarningChoicesView(dataStore: dataStore)
            ),
            SettingsCategoryItem(
                icon: "cross.fill",
                title: "Medical Emergency",
                subtitle: "Emergency contact and local hotline number",
                destination: MedicalEmergencyView(dataStore: dataStore)
            ),
            SettingsCategoryItem(
                icon: "figure.fall",
                title: "Fall Detection",
                subtitle: "Turn detection on/off, try the demo",
                destination: FallDetectionSettingsView(fallDetector: fallDetector, dataStore: dataStore)
            ),
            SettingsCategoryItem(
                icon: "checkmark.shield.fill",
                title: "Permissions",
                subtitle: "What this app can currently access",
                destination: PermissionsView()
            ),
            SettingsCategoryItem(
                icon: "battery.100.bolt",
                title: "Background Execution",
                subtitle: "Keep monitoring running when the screen is locked",
                destination: BackgroundPermissionView()
            ),
            SettingsCategoryItem(
                icon: "hammer.fill",
                title: "Developer / Demo",
                subtitle: "Test mode and full-screen warning previews",
                destination: DeveloperDemoView(dataStore: dataStore, fallDetector: fallDetector)
            ),
            SettingsCategoryItem(
                icon: "info.circle.fill",
                title: "About",
                subtitle: "App name, version, credits, and GitLab link",
                destination: AboutView()
            )
        ]
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(categories) { item in
                        NavigationLink(destination: item.destination) {
                            HStack(spacing: 14) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(LiquidGlassTheme.neonCyan)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Color.white)
                                    Text(item.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.white.opacity(0.65))
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(LiquidGlassTheme.neonCyan)
                }
            }
            .background(MeshGradientBackground())
        }
    }
}
