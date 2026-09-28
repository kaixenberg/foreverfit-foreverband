import Foundation

public enum ActivityState: String, CaseIterable, Codable {
    case still = "Still"
    case walking = "Walking"
    case running = "Running"
}

public final class ActivityClassifierEngine {
    public static let windowLen = 45 // ~2.2 seconds at 20Hz for fast real-time responsiveness
    private var buffer: [PhoneMotionSample] = []

    public init() {}

    public func addSample(_ sample: PhoneMotionSample) {
        buffer.append(sample)
        if buffer.count > Self.windowLen {
            buffer.removeFirst()
        }
    }

    /// Evaluates 3-class activity [still, walking, running] from phone accelerometer and gyroscope
    public func classify() -> (activity: ActivityState, confidence: Double)? {
        guard buffer.count >= Self.windowLen else { return nil }

        var accelMagnitudes: [Double] = []
        var gyroMagnitudes: [Double] = []
        accelMagnitudes.reserveCapacity(Self.windowLen)
        gyroMagnitudes.reserveCapacity(Self.windowLen)

        for s in buffer {
            let aMag = sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az)
            let gMag = sqrt(s.gx * s.gx + s.gy * s.gy + s.gz * s.gz)
            accelMagnitudes.append(aMag)
            gyroMagnitudes.append(gMag)
        }

        // Statistical distribution
        let mean = accelMagnitudes.reduce(0, +) / Double(Self.windowLen)
        let variance = accelMagnitudes.reduce(0) { $0 + pow($1 - mean, 2) } / Double(Self.windowLen)
        let stdDev = sqrt(variance)

        let minVal = accelMagnitudes.min() ?? mean
        let maxVal = accelMagnitudes.max() ?? mean
        let dynamicRange = maxVal - minVal

        let avgGyro = gyroMagnitudes.reduce(0, +) / Double(Self.windowLen)
        let maxGyro = gyroMagnitudes.max() ?? 0.0

        // Step peak detection: local maxima with refractory period of 5 samples (0.25s)
        var stepCount = 0
        var lastPeakIdx = -10
        let peakThreshold = mean + max(1.0, stdDev * 0.45)

        for i in 1..<(accelMagnitudes.count - 1) {
            let prev = accelMagnitudes[i - 1]
            let curr = accelMagnitudes[i]
            let next = accelMagnitudes[i + 1]

            if curr > peakThreshold && curr > prev && curr > next && (i - lastPeakIdx) >= 5 {
                stepCount += 1
                lastPeakIdx = i
            }
        }

        // Wrist/Hand shake detection:
        // Pure hand shaking generates rapid rotational angular rates without rhythmic locomotive translation
        let isHandShake = (maxGyro > 6.0 && stepCount < 2) || (avgGyro > 4.2 && dynamicRange < 7.0)
        if isHandShake {
            return (.still, 0.85)
        }

        // Locomotion Classification
        if stdDev >= 2.2 && dynamicRange >= 7.0 && maxVal >= 13.0 && stepCount >= 4 {
            // Running: High dynamic acceleration impact + rapid cadence (at least 4 steps in ~2.2s)
            return (.running, 0.90)
        } else if (stdDev >= 0.40 && dynamicRange >= 1.5) || stepCount >= 2 {
            // Walking: Rhythmic footfall displacement or cadence
            return (.walking, 0.85)
        } else {
            // Still: Hand holding, sitting, standing, resting
            return (.still, 0.95)
        }
    }
}
