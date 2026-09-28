import Foundation
import Combine

@MainActor
public final class AppState: ObservableObject {
    @Published public var selectedTab: AppTab = .dashboard
    @Published public var bleManager = ForeverBandBLEManager()
    @Published public var motionService = PhoneMotionService()
    @Published public var pedometerService = PedometerService()
    @Published public var fallDetector = FallDetectorService()
    @Published public var disasterService = DisasterService()
    @Published public var baselineService = BaselineService()
    @Published public var emergencyWorkflow = EmergencyWorkflowService()
    @Published public var dataStore = HealthDataStore()
    @Published public var aiChatService = AiChatService()
    @Published public var medicationReminders = MedicationReminderService()

    private var cancellables = Set<AnyCancellable>()

    public init() {
        setupSubscriptions()
        startAllServices()
    }

    private func setupSubscriptions() {
        // Feed fall detection to emergency workflow upon countdown expiry
        fallDetector.onEmergencyTriggered = { [weak self] reason in
            guard let self = self else { return }
            let primary = self.dataStore.userProfile.emergencyContacts.first(where: { $0.isPrimary })
                ?? self.dataStore.userProfile.emergencyContacts.first
            self.emergencyWorkflow.startEmergencyWorkflow(
                triggerReason: reason,
                vitals: self.bleManager.latestVitals,
                connectedAt: self.bleManager.connectedAt,
                watchSettings: self.dataStore.watchSettings,
                baseline: self.baselineService,
                primaryContact: primary
            )
        }

        // Record incoming BLE vitals to historical data store
        bleManager.$latestVitals
            .compactMap { $0 }
            .sink { [weak self] vitals in
                guard let self = self else { return }
                self.dataStore.recordVitalsSample(vitals)
                if vitals.hasHeartRate {
                    self.baselineService.addRestingReading(Double(vitals.heartRate))
                }
            }
            .store(in: &cancellables)

        // Reschedule medication reminders whenever medications list updates
        dataStore.$medications
            .sink { [weak self] _ in
                self?.medicationReminders.rescheduleSystemNotifications()
            }
            .store(in: &cancellables)
    }

    private func startAllServices() {
        medicationReminders.start(dataStore: dataStore)
        motionService.start()
        pedometerService.start()
        if dataStore.fallDetectionEnabled {
            fallDetector.start(
                sensorSource: dataStore.fallDetectionSensorSource,
                motionService: motionService,
                bleManager: bleManager
            )
        }
        disasterService.startLocationUpdates()
        bleManager.startScanning()
    }
}
