import Foundation

public enum ActivityState: String, CaseIterable, Codable {
    case still = "Still"
    case walking = "Walking"
    case running = "Running"
}

public final class ActivityClassifierEngine {
    public static let windowLen = 60
    private var buffer: [PhoneMotionSample] = []

    public init() {}

    public func addSample(_ sample: PhoneMotionSample) {
        buffer.append(sample)
        if buffer.count > Self.windowLen {
            buffer.removeFirst()
        }
    }

    /// Evaluates 3-class activity probabilities [still, walking, running]
    public func classify() -> (activity: ActivityState, confidence: Double)? {
        guard buffer.count >= Self.windowLen else { return nil }

        var accelMagnitudes: [Double] = []
        accelMagnitudes.reserveCapacity(Self.windowLen)

        for s in buffer {
            let mag = sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az)
            accelMagnitudes.append(mag)
        }

        // Calculate variance & dynamic range
        let mean = accelMagnitudes.reduce(0, +) / Double(Self.windowLen)
        let variance = accelMagnitudes.reduce(0) { $0 + pow($1 - mean, 2) } / Double(Self.windowLen)
        let stdDev = sqrt(variance)

        // Peak-to-peak amplitude
        let minVal = accelMagnitudes.min() ?? mean
        let maxVal = accelMagnitudes.max() ?? mean
        let dynamicRange = maxVal - minVal

        if stdDev < 0.6 && dynamicRange < 2.0 {
            // Very low motion energy -> Still
            let conf = min(0.98, max(0.70, 1.0 - (stdDev / 1.0)))
            return (.still, conf)
        } else if stdDev >= 0.6 && stdDev < 3.2 && dynamicRange < 12.0 {
            // Rhythmic moderate cadence -> Walking
            let conf = min(0.96, max(0.65, 0.85))
            return (.walking, conf)
        } else {
            // High energy oscillations -> Running
            let conf = min(0.99, max(0.75, 0.90))
            return (.running, conf)
        }
    }
}
