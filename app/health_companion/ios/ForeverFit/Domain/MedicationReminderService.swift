import Foundation
import UserNotifications
import Combine

/// Fires a notification when a medication's dose time is reached.
/// Matches lib/services/medication_reminder_service.dart
/// Combines immediate 20s active clock polling with native iOS UNCalendarNotificationTrigger
/// recurring local notifications.
@MainActor
public final class MedicationReminderService: ObservableObject {
    private weak var dataStore: HealthDataStore?
    private var pollTimer: AnyCancellable?
    private var firedToday: Set<String> = []
    private var firedTodayDate: Date?

    public init(dataStore: HealthDataStore? = nil) {
        self.dataStore = dataStore
    }

    public func start(dataStore: HealthDataStore) {
        self.dataStore = dataStore
        requestNotificationPermission()
        checkReminders()

        pollTimer?.cancel()
        pollTimer = Timer.publish(every: 20.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkReminders()
            }

        rescheduleSystemNotifications()
    }

    public func stop() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    public func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    public func checkReminders() {
        guard let store = dataStore, store.notifyReminders else { return }

        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)

        if firedTodayDate != todayStart {
            firedToday.removeAll()
            firedTodayDate = todayStart
        }

        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)

        for med in store.medications where med.isActive {
            for (idx, schedule) in med.schedules.enumerated() {
                if schedule.hour == currentHour && schedule.minute == currentMinute {
                    let key = "\(med.id.uuidString)#\(idx)"
                    if !firedToday.contains(key) {
                        firedToday.insert(key)
                        postMedicationNotification(for: med)
                    }
                }
            }
        }
    }

    public func rescheduleSystemNotifications() {
        guard let store = dataStore else { return }
        let center = UNUserNotificationCenter.current()

        // Clear existing medication reminders
        center.getPendingNotificationRequests { requests in
            let medIds = requests.map(\.identifier).filter { $0.hasPrefix("med_remind_") }
            center.removePendingNotificationRequests(withIdentifiers: medIds)

            guard store.notifyReminders else { return }

            for med in store.medications where med.isActive {
                for (idx, schedule) in med.schedules.enumerated() {
                    let content = UNMutableNotificationContent()
                    content.title = "Time for \(med.name)"
                    content.body = med.dosage.isEmpty ? "Take your scheduled dose." : med.dosage
                    content.sound = .default

                    var dateComponents = DateComponents()
                    dateComponents.hour = schedule.hour
                    dateComponents.minute = schedule.minute

                    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                    let identifier = "med_remind_\(med.id.uuidString)_\(idx)"
                    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                    center.add(request)
                }
            }
        }
    }

    private func postMedicationNotification(for medication: Medication) {
        let content = UNMutableNotificationContent()
        content.title = "Time for \(medication.name)"
        content.body = medication.dosage.isEmpty ? "Take your scheduled dose." : medication.dosage
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "immediate_med_\(medication.id.uuidString)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
