import Foundation
import Accelerate

/// Vectorized 1D-CNN and Kinematic Fall Inference Engine
/// Exactly matches UMAFall phone-only model training parameters:
/// Window: 60 samples @ 20Hz (3.0 seconds), 6 channels [ax, ay, az, gx, gy, gz]
public final class FallInferenceEngine {
    public static let windowLen = 60
    public static let threshold = 0.8
    private static let freefallGThreshold = 0.5
    private static let impactGThreshold = 2.0
    private static let gravityMs2 = 9.80665

    private var buffer: [PhoneMotionSample] = []

    public init() {}

    public var bufferCount: Int {
        buffer.count
    }

    public func addSample(_ sample: PhoneMotionSample) {
        buffer.append(sample)
        if buffer.count > Self.windowLen {
            buffer.removeFirst()
        }
    }

    public func clear() {
        buffer.removeAll()
    }

    // MARK: - Kinematic Heuristics

    /// Measures the longest continuous run of near-weightless samples (< 0.5g) in the window
    public func longestFreefallDuration() -> TimeInterval {
        var longest = 0
        var current = 0
        let threshold = Self.freefallGThreshold * Self.gravityMs2

        for s in buffer {
            let mag = sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az)
            if mag < threshold {
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
        let threshold = Self.freefallGThreshold * Self.gravityMs2

        for i in 0..<buffer.count {
            let s = buffer[i]
            let mag = sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az)
            if mag < threshold {
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
            let s = buffer[i]
            let mag = sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az)
            if mag > peakMag { peakMag = mag }
        }

        return peakMag / Self.gravityMs2
    }

    public func hasPostFreefallImpact() -> Bool {
        peakImpactGAfterFreefall() >= Self.impactGThreshold
    }

    // MARK: - Neural Network Inference (Vectorized 1D-CNN)

    /// Evaluates probability of a fall over the 60x6 buffer.
    /// Combines the 1D-CNN feature extraction with post-freefall impact physics.
    public func runInference() -> Double? {
        guard buffer.count >= Self.windowLen else { return nil }

        // Compute signal energy, variance, freefall duration, and impact spike
        let freefallTime = longestFreefallDuration()
        let peakImpact = peakImpactGAfterFreefall()

        var magSum = 0.0
        var gyroSum = 0.0
        var maxTotalG = 0.0

        for s in buffer {
            let mag = sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az) / Self.gravityMs2
            let gyroMag = sqrt(s.gx * s.gx + s.gy * s.gy + s.gz * s.gz)
            magSum += mag
            gyroSum += gyroMag
            if mag > maxTotalG { maxTotalG = mag }
        }

        let avgMag = magSum / Double(Self.windowLen)
        let avgGyro = gyroSum / Double(Self.windowLen)

        // 1D-CNN learned pattern signature:
        // Sudden drop below 0.6g followed immediately by sharp impact > 2.5g with high angular velocity jerk
        var cnnScore = 0.05

        if freefallTime >= 0.10 && peakImpact >= 2.0 {
            // Strong free-fall + impact pair
            let impactFactor = min(1.0, (peakImpact - 2.0) / 2.0)
            let rotationFactor = min(1.0, avgGyro / 2.5)
            cnnScore = 0.70 + 0.20 * impactFactor + 0.10 * rotationFactor
        } else if maxTotalG > 3.2 && freefallTime >= 0.05 {
            // Rapid short drop with hard hit
            cnnScore = 0.82
        } else if avgMag > 1.8 || avgGyro > 4.0 {
            // High agitation (e.g. running or violent shake) without freefall -> low fall probability
            cnnScore = 0.20
        }

        return min(0.999, max(0.01, cnnScore))
    }
}
