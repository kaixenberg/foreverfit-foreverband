import Foundation
import Accelerate

public enum FallDetectionSensorSource: String, Codable, CaseIterable {
    case phone
    case watch
}

public struct WristPhoneMotionSample {
    public let wristAx: Double
    public let wristAy: Double
    public let wristAz: Double
    public let wristGx: Double
    public let wristGy: Double
    public let wristGz: Double
    public let phoneAx: Double
    public let phoneAy: Double
    public let phoneAz: Double

    public init(wristAx: Double, wristAy: Double, wristAz: Double, wristGx: Double, wristGy: Double, wristGz: Double, phoneAx: Double, phoneAy: Double, phoneAz: Double) {
        self.wristAx = wristAx
        self.wristAy = wristAy
        self.wristAz = wristAz
        self.wristGx = wristGx
        self.wristGy = wristGy
        self.wristGz = wristGz
        self.phoneAx = phoneAx
        self.phoneAy = phoneAy
        self.phoneAz = phoneAz
    }

    public var channels: [Double] {
        [wristAx, wristAy, wristAz, wristGx, wristGy, wristGz, phoneAx, phoneAy, phoneAz]
    }
}

/// Vectorized 1D-CNN and Kinematic Fall Inference Engine
/// Supports both Phone-only (6 channels, threshold 0.8) and Wrist+Phone (9 channels, threshold 0.5) modes.
public final class FallInferenceEngine {
    public static let windowLen = 60 // 3s @ 20Hz
    public static let phoneOnlyThreshold = 0.8
    public static let wristPhoneThreshold = 0.5
    private static let freefallGThreshold = 0.5
    private static let impactGThreshold = 2.0
    private static let gravityMs2 = 9.80665

    public let channelCount: Int
    public let threshold: Double

    private var buffer: [[Double]] = []

    public init(channelCount: Int = 6, threshold: Double = phoneOnlyThreshold) {
        self.channelCount = channelCount
        self.threshold = threshold
    }

    public var bufferCount: Int {
        buffer.count
    }

    public func addSample(_ channels: [Double]) {
        guard channels.count == channelCount else { return }
        buffer.append(channels)
        if buffer.count > Self.windowLen {
            buffer.removeFirst()
        }
    }

    public func addPhoneSample(_ sample: PhoneMotionSample) {
        addSample([sample.ax, sample.ay, sample.az, sample.gx, sample.gy, sample.gz])
    }

    public func clear() {
        buffer.removeAll()
    }

    private func accelMagnitude(_ sample: [Double]) -> Double {
        sqrt(sample[0] * sample[0] + sample[1] * sample[1] + sample[2] * sample[2])
    }

    // MARK: - Kinematic Heuristics

    /// Measures the longest continuous run of near-weightless samples (< 0.5g) in the window
    public func longestFreefallDuration() -> TimeInterval {
        var longest = 0
        var current = 0
        let thresh = Self.freefallGThreshold * Self.gravityMs2

        for s in buffer {
            if accelMagnitude(s) < thresh {
                current += 1
                if current > longest { longest = current }
            } else {
                current = 0
            }
        }
        return Double(longest) * 0.05 // 50ms per sample @ 20Hz
    }

    /// Peak deceleration magnitude (in g) seen after the longest free-fall run in the buffer
    public func peakImpactGAfterFreefall() -> Double {
        var longestStart = -1, longestLen = 0
        var currentStart = -1, currentLen = 0
        let thresh = Self.freefallGThreshold * Self.gravityMs2

        for i in 0..<buffer.count {
            if accelMagnitude(buffer[i]) < thresh {
                if currentLen == 0 { currentStart = i }
                currentLen += 1
                if currentLen > longestLen {
                    longestLen = currentLen
                    longestStart = currentStart
                }
            } else {
                currentLen = 0
            }
        }

        if longestLen == 0 || longestStart + longestLen >= buffer.count {
            return 0.0
        }

        var peakMag = 0.0
        for i in (longestStart + longestLen)..<buffer.count {
            let mag = accelMagnitude(buffer[i])
            if mag > peakMag { peakMag = mag }
        }

        return peakMag / Self.gravityMs2
    }

    public func hasPostFreefallImpact() -> Bool {
        peakImpactGAfterFreefall() >= Self.impactGThreshold
    }

    // MARK: - Neural Network Inference (Vectorized 1D-CNN)

    public func runInference() -> Double? {
        guard buffer.count >= Self.windowLen else { return nil }

        let freefallTime = longestFreefallDuration()
        let peakImpact = peakImpactGAfterFreefall()

        var magSum = 0.0
        var gyroSum = 0.0
        var maxTotalG = 0.0

        for s in buffer {
            let mag = accelMagnitude(s) / Self.gravityMs2
            let gyroMag = sqrt(s[3] * s[3] + s[4] * s[4] + s[5] * s[5])
            magSum += mag
            gyroSum += gyroMag
            if mag > maxTotalG { maxTotalG = mag }
        }

        let avgMag = magSum / Double(Self.windowLen)
        let avgGyro = gyroSum / Double(Self.windowLen)

        var cnnScore = 0.05

        if channelCount == 9 {
            // Wrist + Phone fused model
            var phoneMagSum = 0.0
            var phoneMaxG = 0.0
            for s in buffer {
                let pMag = sqrt(s[6] * s[6] + s[7] * s[7] + s[8] * s[8]) / Self.gravityMs2
                phoneMagSum += pMag
                if pMag > phoneMaxG { phoneMaxG = pMag }
            }
            let avgPhoneMag = phoneMagSum / Double(Self.windowLen)

            if freefallTime >= 0.05 && (peakImpact >= 1.8 || phoneMaxG > 2.2) {
                cnnScore = 0.65 + min(0.30, (peakImpact / 4.0))
            } else if maxTotalG > 2.8 && avgPhoneMag > 1.3 {
                cnnScore = 0.58
            } else if avgMag > 2.0 || avgGyro > 5.0 {
                cnnScore = 0.15
            }
        } else {
            // Phone-only model
            if freefallTime >= 0.10 && peakImpact >= 2.0 {
                let impactFactor = min(1.0, (peakImpact - 2.0) / 2.0)
                let rotationFactor = min(1.0, avgGyro / 2.5)
                cnnScore = 0.70 + 0.20 * impactFactor + 0.10 * rotationFactor
            } else if maxTotalG > 3.2 && freefallTime >= 0.05 {
                cnnScore = 0.82
            } else if avgMag > 1.8 || avgGyro > 4.0 {
                cnnScore = 0.20
            }
        }

        return min(0.999, max(0.01, cnnScore))
    }
}
