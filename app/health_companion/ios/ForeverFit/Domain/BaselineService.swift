import Foundation

@MainActor
public final class BaselineService: ObservableObject {
    @Published public var heartRateMean: Double? = 72.0
    @Published public var heartRateStdDev: Double? = 6.5

    private var recentReadings: [Double] = [68, 70, 72, 74, 71, 73, 75, 69, 72, 74]

    public init() {}

    public func addRestingReading(_ hr: Double) {
        recentReadings.append(hr)
        if recentReadings.count > 200 {
            recentReadings.removeFirst()
        }
        recompute()
    }

    private func recompute() {
        guard !recentReadings.isEmpty else { return }
        let mean = recentReadings.reduce(0, +) / Double(recentReadings.count)
        let variance = recentReadings.reduce(0) { $0 + pow($1 - mean, 2) } / Double(recentReadings.count)
        self.heartRateMean = mean
        self.heartRateStdDev = sqrt(variance)
    }

    /// Flags an anomalous heart rate if it deviates by more than 2.8 standard deviations from resting baseline
    public func isAnomalous(heartRate: Float) -> Bool {
        guard let mean = heartRateMean, let std = heartRateStdDev, std > 2.0 else { return false }
        let zScore = abs(Double(heartRate) - mean) / std
        return zScore > 2.8
    }

    public func isAnomalous(_ hr: Float) -> Bool {
        isAnomalous(heartRate: hr)
    }
}
