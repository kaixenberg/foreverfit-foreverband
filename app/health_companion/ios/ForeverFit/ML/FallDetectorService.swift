import Foundation
import AVFoundation
import Combine

public enum AlertSource {
    case fall
    case manual
}

@MainActor
public final class FallDetectorService: ObservableObject {
    @Published public var isRunning: Bool = false
    @Published public var fallProbability: Double = 0.0
    @Published public var alertActive: Bool = false
    @Published public var alertSource: AlertSource?
    @Published public var secondsUntilCall: Int?
    @Published public var isCalling: Bool = false

    private let inferenceEngine = FallInferenceEngine()
    private var consecutiveTriggers: Int = 0
    private static let consecutiveRequired = 2
    private static let emergencyCountdownSec = 10

    private var inferenceTimer: AnyCancellable?
    private var countdownTimer: AnyCancellable?
    private let speechSynthesizer = AVSpeechSynthesizer()

    public var onEmergencyTriggered: ((_ reason: String) -> Void)?

    private weak var motionService: PhoneMotionService?

    public init() {}

    public func start(with motionService: PhoneMotionService? = nil) {
        if let ms = motionService {
            self.motionService = ms
        }
        guard !isRunning else { return }
        isRunning = true
        inferenceEngine.clear()

        // 500ms inference timer matches Flutter FallDetectorService cadence
        inferenceTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if let sample = self.motionService?.latestSample {
                    self.inferenceEngine.addSample(sample)
                }
                self.runInferenceTick()
            }
    }

    public func stop() {
        isRunning = false
        inferenceTimer?.cancel()
        inferenceTimer = nil
        dismissAlert()
    }

    private func runInferenceTick() {
        guard let prob = inferenceEngine.runInference() else { return }
        self.fallProbability = prob

        let triggered = prob > FallInferenceEngine.threshold
        consecutiveTriggers = triggered ? consecutiveTriggers + 1 : 0

        if !alertActive && consecutiveTriggers >= Self.consecutiveRequired {
            startAlert(source: .fall)
        }
    }

    // MARK: - Alert Lifecycles

    public func triggerManualSOS() {
        guard !alertActive else { return }
        startAlert(source: .manual)
    }

    public func triggerFallDemo() {
        guard !alertActive else { return }
        startAlert(source: .fall)
    }

    public func simulateFallDetection() {
        triggerFallDemo()
    }

    private func startAlert(source: AlertSource) {
        alertActive = true
        alertSource = source
        isCalling = false
        secondsUntilCall = Self.emergencyCountdownSec

        speakAlertPrompt(for: source)

        countdownTimer?.cancel()
        countdownTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if let sec = self.secondsUntilCall, sec > 1 {
                    self.secondsUntilCall = sec - 1
                } else {
                    self.countdownTimer?.cancel()
                    self.triggerEmergencyDispatch()
                }
            }
    }

    public func dismissAlert() {
        countdownTimer?.cancel()
        countdownTimer = nil
        alertActive = false
        alertSource = nil
        secondsUntilCall = nil
        isCalling = false
        consecutiveTriggers = 0
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    private func triggerEmergencyDispatch() {
        isCalling = true
        secondsUntilCall = 0
        let reason = alertSource == .manual
            ? "the user manually triggered an emergency SOS"
            : "a high-impact fall was detected"
        onEmergencyTriggered?(reason)
    }

    private func speakAlertPrompt(for source: AlertSource) {
        let text = source == .manual
            ? "Emergency SOS triggered. Escalating to emergency responders in ten seconds."
            : "A possible fall was detected. Tap I'm OK to cancel, or assistance will be summoned."
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speechSynthesizer.speak(utterance)
    }
}
