import Foundation
import CoreMotion
import Combine

public struct PhoneMotionSample {
    public let ax: Double
    public let ay: Double
    public let az: Double
    public let gx: Double
    public let gy: Double
    public let gz: Double
    public let timestamp: Date

    public init(ax: Double, ay: Double, az: Double, gx: Double, gy: Double, gz: Double, timestamp: Date = Date()) {
        self.ax = ax
        self.ay = ay
        self.az = az
        self.gx = gx
        self.gy = gy
        self.gz = gz
        self.timestamp = timestamp
    }
}

@MainActor
public final class PhoneMotionService: ObservableObject {
    @Published public var latestSample: PhoneMotionSample?
    @Published public var isRunning: Bool = false
    @Published public var currentActivity: ActivityState = .still

    private let activityEngine = ActivityClassifierEngine()
    private let motionManager = CMMotionManager()
    private var simulationTimer: AnyCancellable?
    private var simTick: Double = 0.0

    // Calibrated to 20Hz (50ms interval) to match UMAFall model training
    private let sampleInterval: TimeInterval = 0.05

    public init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = sampleInterval
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self = self, let m = motion else { return }
                // Convert G to m/s^2 (1G = 9.80665 m/s^2) to match standard training units
                let gravityMs2 = 9.80665
                let ax = (m.userAcceleration.x + m.gravity.x) * gravityMs2
                let ay = (m.userAcceleration.y + m.gravity.y) * gravityMs2
                let az = (m.userAcceleration.z + m.gravity.z) * gravityMs2

                // Rotation rate in rad/s
                let gx = m.rotationRate.x
                let gy = m.rotationRate.y
                let gz = m.rotationRate.z

                let sample = PhoneMotionSample(ax: ax, ay: ay, az: az, gx: gx, gy: gy, gz: gz)
                self.latestSample = sample
                self.activityEngine.addSample(sample)
                if let result = self.activityEngine.classify() {
                    self.currentActivity = result.activity
                }
            }
        } else {
            // Simulator or unsupported hardware -> run realistic motion generator
            startSimulatedMotion()
        }
    }

    public func stop() {
        isRunning = false
        if motionManager.isDeviceMotionAvailable {
            motionManager.stopDeviceMotionUpdates()
        }
        simulationTimer?.cancel()
        simulationTimer = nil
    }

    private func startSimulatedMotion() {
        simulationTimer?.cancel()
        simulationTimer = Timer.publish(every: sampleInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.simTick += 0.05
                // Slight normal breathing/handling vibration at 1G gravity
                let noiseX = sin(self.simTick * 2.0) * 0.2
                let noiseY = 9.80665 + cos(self.simTick * 2.5) * 0.15
                let noiseZ = sin(self.simTick * 1.5) * 0.1
                let gyroX = sin(self.simTick * 3.0) * 0.02
                let gyroY = cos(self.simTick * 2.0) * 0.02
                let gyroZ = sin(self.simTick * 1.0) * 0.01

                self.latestSample = PhoneMotionSample(
                    ax: noiseX, ay: noiseY, az: noiseZ,
                    gx: gyroX, gy: gyroY, gz: gyroZ
                )
            }
    }

    /// Injects a deliberate synthetic fall motion waveform for testing & hackathon judging:
    /// High gravity acceleration -> Free-fall weightlessness dip (<0.5g) -> Hard impact deceleration spike (>3.5g)
    public func simulateFallMotion() {
        Task {
            // Free-fall phase: phone dropped, near-zero gravity for ~300ms
            for _ in 0..<6 {
                self.latestSample = PhoneMotionSample(
                    ax: 0.2, ay: 0.5, az: 0.1,
                    gx: 0.8, gy: -1.2, gz: 0.4
                )
                try? await Task.sleep(nanoseconds: 50_000_000)
            }

            // Impact phase: violent deceleration spike (> 3.5g = ~35 m/s^2)
            for _ in 0..<4 {
                self.latestSample = PhoneMotionSample(
                    ax: 15.0, ay: 38.0, az: -12.0,
                    gx: 4.5, gy: -3.8, gz: 6.2
                )
                try? await Task.sleep(nanoseconds: 50_000_000)
            }

            // Rest on floor
            for _ in 0..<10 {
                self.latestSample = PhoneMotionSample(
                    ax: 0.1, ay: 9.81, az: 0.2,
                    gx: 0.01, gy: 0.0, gz: 0.01
                )
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
}
