import SwiftUI

@main
struct ForeverFitApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .bottom) {
                // Dynamic MeshGradient Background that shifts with wellness/emergency mood
                MeshGradientBackground(mood: backgroundMood)
                    .ignoresSafeArea()

                // Main Tab Content
                Group {
                    switch appState.selectedTab {
                    case .dashboard:
                        DashboardView(
                            bleManager: appState.bleManager,
                            fallDetector: appState.fallDetector,
                            motionService: appState.motionService,
                            pedometerService: appState.pedometerService,
                            baselineService: appState.baselineService,
                            disasterService: appState.disasterService,
                            dataStore: appState.dataStore,
                            selectedTab: $appState.selectedTab
                        )
                    case .aiAssistant:
                        AiChatView(
                            chatService: appState.aiChatService,
                            bleManager: appState.bleManager,
                            baselineService: appState.baselineService,
                            pedometerService: appState.pedometerService,
                            disasterService: appState.disasterService,
                            dataStore: appState.dataStore
                        )
                    case .disaster:
                        DisasterCenterView(disasterService: appState.disasterService)
                    case .healthLog:
                        HealthLogView(
                            dataStore: appState.dataStore,
                            bleManager: appState.bleManager,
                            pedometerService: appState.pedometerService
                        )
                    case .wearable:
                        WearableSettingsView(
                            bleManager: appState.bleManager,
                            dataStore: appState.dataStore
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Floating Liquid-Glass Tab Bar
                LiquidTabBar(selectedTab: $appState.selectedTab)
            }
            .preferredColorScheme(effectiveColorScheme)
            .fullScreenCover(isPresented: Binding(
                get: { !appState.dataStore.userProfile.onboardingCompleted },
                set: { _ in }
            )) {
                OnboardingView(
                    dataStore: appState.dataStore,
                    onboardingCompleted: Binding(
                        get: { appState.dataStore.userProfile.onboardingCompleted },
                        set: { appState.dataStore.userProfile.onboardingCompleted = $0 }
                    )
                )
            }
            .fullScreenCover(isPresented: Binding(
                get: { appState.emergencyWorkflow.isActive },
                set: { _ in }
            )) {
                EmergencyCallView(workflow: appState.emergencyWorkflow)
            }
        }
    }

    private var effectiveColorScheme: ColorScheme? {
        switch appState.dataStore.themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var backgroundMood: MeshGradientBackground.Mood {
        if appState.fallDetector.alertActive || appState.emergencyWorkflow.isActive {
            return .emergency
        }
        if appState.selectedTab == .aiAssistant {
            return .aiAssistant
        }
        if !appState.disasterService.activeWarnings.isEmpty {
            return .caution
        }
        return .normal
    }
}
