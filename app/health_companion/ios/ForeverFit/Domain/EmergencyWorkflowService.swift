import Foundation
import UIKit
import AVFoundation

public enum EmergencyWorkflowState: String, Codable {
    case idle
    case emergencyDetected
    case collectingData
    case gettingLocation
    case generatingMessage
    case callingEmergencyServices
    case announcingToEmergencyServices
    case waitingForEmergencyCallEnd
    case callingEmergencyContact
    case retryingContact
    case announcingToContact
    case contactNoAnswer
    case smsFallback
    case completed
    case failed
    case cancelled
}

@MainActor
public final class EmergencyWorkflowService: ObservableObject {
    public static let shared = EmergencyWorkflowService()

    @Published public var state: EmergencyWorkflowState = .idle
    @Published public var isActive: Bool = false
    @Published public var isSpeaking: Bool = false
    @Published public var attempt: Int = 1
    @Published public var isUsingMockTelephony: Bool = false
    @Published public var currentSummary: EmergencySummary?
    @Published public var spokenScript: String = ""
    @Published public var servicesScript: String?
    @Published public var contactScript: String?
    @Published public var smsText: String?
    @Published public var log: [String] = []

    private let speechSynthesizer = AVSpeechSynthesizer()
    private let locationService = EmergencyLocationService()

    public init() {}

    public func startEmergencyWorkflow(
        triggerReason: String,
        vitals: VitalsReading?,
        connectedAt: Date? = nil,
        watchSettings: WatchSettings = WatchSettings.defaults,
        baseline: BaselineService,
        primaryContact: EmergencyContact?,
        isDemo: Bool = false
    ) {
        self.isActive = true
        self.isUsingMockTelephony = isDemo
        self.state = .emergencyDetected
        self.attempt = 1
        self.log = ["[\(Date().formatted(date: .omitted, time: .standard))] Emergency triggered: \(triggerReason)"]

        Task {
            self.state = .collectingData
            self.log.append("[\(Date().formatted(date: .omitted, time: .standard))] Collecting telemetry & baseline vitals")
            try? await Task.sleep(nanoseconds: 500_000_000)

            self.state = .gettingLocation
            self.log.append("[\(Date().formatted(date: .omitted, time: .standard))] Resolving GPS coordinates")
            let location = await locationService.resolveLocation()

            self.state = .generatingMessage
            let summary = EmergencySummaryBuilder.build(
                vitals: vitals,
                connectedAt: connectedAt,
                watchSettings: watchSettings,
                baseline: baseline,
                location: location,
                triggerReason: triggerReason
            )
            self.currentSummary = summary

            let sScript = EmergencySummaryBuilder.buildEmergencyServicesScript(summary: summary)
            let cScript = EmergencySummaryBuilder.buildEmergencyContactScript(summary: summary)
            let sms = EmergencySummaryBuilder.buildEmergencySms(summary: summary)

            self.servicesScript = sScript
            self.contactScript = cScript
            self.smsText = sms
            self.spokenScript = sScript

            if isDemo {
                self.log.append("[\(Date().formatted(date: .omitted, time: .standard))] DEMO: Simulating voice announcement to emergency services")
                self.state = .announcingToEmergencyServices
                self.speak(text: sScript)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.state = .callingEmergencyContact
                self.log.append("[\(Date().formatted(date: .omitted, time: .standard))] DEMO: Simulating emergency contact dispatch")
                return
            }

            self.state = .callingEmergencyServices
            self.log.append("[\(Date().formatted(date: .omitted, time: .standard))] Dialing 112 emergency services")
            self.callEmergencyServices()

            self.state = .announcingToEmergencyServices
            self.speak(text: sScript)

            // Auto-compose SMS or trigger phone call
            if let contact = primaryContact {
                self.state = .callingEmergencyContact
                self.log.append("[\(Date().formatted(date: .omitted, time: .standard))] Dispatching emergency SMS to \(contact.name)")
                self.dispatchEmergencySms(to: contact.phone, body: sms)
            }
        }
    }

    public func cancel() {
        cancelWorkflow()
    }

    public func cancelWorkflow() {
        isActive = false
        isSpeaking = false
        state = .cancelled
        log.append("[\(Date().formatted(date: .omitted, time: .standard))] Emergency workflow cancelled by user")
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    private func speak(text: String) {
        isSpeaking = true
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechSynthesizer.speak(utterance)
    }

    public func callEmergencyServices() {
        if let url = URL(string: "tel://112"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    public func dispatchEmergencySms(to phone: String, body: String) {
        let cleanPhone = phone.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? phone
        let cleanBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "sms:\(cleanPhone)&body=\(cleanBody)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
