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
    @Published public var runningSensorSource: FallDetectionSensorSource?
    @Published public var fallProbability: Double = 0.0
    @Published public var alertActive: Bool = false
    @Published public var alertSource: AlertSource?
    @Published public var secondsUntilCall: Int?
    @Published public var isCalling: Bool = false

    private var inferenceEngine = FallInferenceEngine()
    private var consecutiveTriggers: Int = 0
    private static let consecutiveRequired = 2
    private static let emergencyCountdownSec = 10

    private var inferenceTimer: AnyCancellable?
    private var countdownTimer: AnyCancellable?
    private var motionCancellable: AnyCancellable?
    private var bleMotionCancellable: AnyCancellable?
    private var lastWristMotionDeviceTimeMs: UInt32?
    private let speechSynthesizer = AVSpeechSynthesizer()

    public var onEmergencyTriggered: ((_ reason: String) -> Void)?

    private weak var motionService: PhoneMotionService?
    private weak var bleManager: ForeverBandBLEManager?

    public init() {}

    public func start(
        sensorSource: FallDetectionSensorSource = .phone,
        motionService: PhoneMotionService? = nil,
        bleManager: ForeverBandBLEManager? = nil
    ) {
        if let ms = motionService { self.motionService = ms }
        if let ble = bleManager { self.bleManager = ble }

        if isRunning {
            stop()
        }

        isRunning = true
        runningSensorSource = sensorSource
        lastWristMotionDeviceTimeMs = nil

        let channels = (sensorSource == .watch) ? 9 : 6
        let threshold = (sensorSource == .watch) ? FallInferenceEngine.wristPhoneThreshold : FallInferenceEngine.phoneOnlyThreshold
        inferenceEngine = FallInferenceEngine(channelCount: channels, threshold: threshold)

        if sensorSource == .watch {
            // Watch mode: fuse wrist BLE motion with concurrent phone accelerometer
            bleMotionCancellable = self.bleManager?.$latestMotion
                .compactMap { $0 }
                .sink { [weak self] motion in
                    guard let self = self else { return }
                    if let lastTime = self.lastWristMotionDeviceTimeMs, motion.deviceTimeMs == lastTime {
                        return
                    }
                    self.lastWristMotionDeviceTimeMs = motion.deviceTimeMs

                    let phone = self.motionService?.latestSample
                    let sample = WristPhoneMotionSample(
                        wristAx: Double(motion.ax),
                        wristAy: Double(motion.ay),
                        wristAz: Double(motion.az),
                        wristGx: Double(motion.gx),
                        wristGy: Double(motion.gy),
                        wristGz: Double(motion.gz),
                        phoneAx: phone?.ax ?? 0.0,
                        phoneAy: phone?.ay ?? 0.0,
                        phoneAz: phone?.az ?? 0.0
                    )
                    self.inferenceEngine.addSample(sample.channels)
                }
        } else {
            // Phone-only mode
            // Periodically consume phone samples via motionService
        }

        // 500ms inference timer matches Flutter FallDetectorService cadence
        inferenceTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.runningSensorSource == .phone {
                    if let sample = self.motionService?.latestSample {
                        self.inferenceEngine.addPhoneSample(sample)
                    }
                }
                self.runInferenceTick()
            }
    }

    public func stop() {
        isRunning = false
        runningSensorSource = nil
        inferenceTimer?.cancel()
        inferenceTimer = nil
        motionCancellable?.cancel()
        motionCancellable = nil
        bleMotionCancellable?.cancel()
        bleMotionCancellable = nil
        dismissAlert()
    }

    private func runInferenceTick() {
        guard let prob = inferenceEngine.runInference() else { return }
        self.fallProbability = prob

        let triggered = prob > inferenceEngine.threshold
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
