import Foundation

public struct HealthThresholds {
    public static let heartRateFloor: Float = 50.0
    public static let restingHeartRateCeiling: Float = 120.0
    public static let walkingHeartRateCeiling: Float = 140.0
    public static let runningHeartRateCeiling: Float = 180.0

    public static let spo2FloorPercent: Float = 92.0
    public static let spo2Floor: Float = 92.0

    public static let bodyTempLowC: Float = 35.5
    public static let bodyTempHighC: Float = 37.8
    public static let bodyTempEquilibrationWindow: TimeInterval = 60.0

    // Standard AHA hypertension thresholds (mmHg)
    public static let bpSystolicHighMmHg = 140
    public static let bpDiastolicHighMmHg = 90
    public static let bpSystolicCrisisMmHg = 180
    public static let bpDiastolicCrisisMmHg = 120

    public static let bpCrisisSystolic: Int = bpSystolicCrisisMmHg
    public static let bpCrisisDiastolic: Int = bpDiastolicCrisisMmHg
    public static let bpElevatedSystolic: Int = bpSystolicHighMmHg
    public static let bpElevatedDiastolic: Int = bpDiastolicHighMmHg

    // Standard ADA glucose range (mg/dL)
    public static let glucoseLowMgDl: Double = 70.0
    public static let glucoseHighMgDl: Double = 180.0

    // Reference sleep floor (hours)
    public static let sleepLowHours: Double = 6.0

    // Air Quality Index thresholds
    public static let aqiUnhealthy: Int = 150
    public static let aqiVeryUnhealthy: Int = 300

    public static func heartRateCeiling(for activity: ActivityState?) -> Float {
        switch activity {
        case .running: return runningHeartRateCeiling
        case .walking: return walkingHeartRateCeiling
        case .still, .none: return restingHeartRateCeiling
        }
    }

    /// Transparent, calibrated formula matching Flutter's _wellnessScore
    public static func computeWellnessScore(
        hasVitals: Bool,
        heartRateWarn: Bool,
        spo2Warn: Bool,
        bodyTempWarn: Bool,
        ambientWarn: Bool,
        heatStressWarn: Bool
    ) -> Int? {
        guard hasVitals else { return nil }
        var score = 100
        if heartRateWarn { score -= 25 }
        if spo2Warn { score -= 30 }
        if bodyTempWarn { score -= 20 }
        if ambientWarn { score -= 10 }
        if heatStressWarn { score -= 15 }
        return max(0, min(100, score))
    }

    public static func buildWellnessSnapshot(
        score: Int?,
        connected: Bool,
        hasFingerReading: Bool,
        hasHeartRate: Bool,
        hasSpo2: Bool,
        hasBodyTempReading: Bool,
        heartRate: Float,
        heartRateCeiling: Float,
        heartRateWarn: Bool,
        spo2: Float,
        spo2Warn: Bool,
        bodyTemp: Float,
        bodyTempWarn: Bool,
        ambientDataAvailable: Bool,
        ambientWarn: Bool,
        heatStressDataAvailable: Bool,
        heatStressWarn: Bool
    ) -> WellnessSnapshot {
        let factors: [WellnessFactor] = [
            WellnessFactor(
                label: "Heart rate",
                warn: heartRateWarn,
                detail: !hasFingerReading
                    ? "No finger detected — not scored right now."
                    : !hasHeartRate
                        ? "Still measuring — hold still for a few seconds."
                        : String(format: "%.0f bpm (normal range up to %.0f for current activity).", heartRate, heartRateCeiling),
                scored: hasHeartRate
            ),
            WellnessFactor(
                label: "SpO2",
                warn: spo2Warn,
                detail: !hasFingerReading
                    ? "No finger detected — not scored right now."
                    : !hasSpo2
                        ? "Still measuring — hold still for a few seconds."
                        : String(format: "%.0f%% (below 92%% is flagged).", spo2),
                scored: hasSpo2
            ),
            WellnessFactor(
                label: "Body temperature",
                warn: bodyTempWarn,
                detail: !hasBodyTempReading
                    ? "No body-temp reading right now."
                    : String(format: "%.1f°C (normal range 35.5–37.8°C).", bodyTemp),
                scored: hasBodyTempReading
            ),
            WellnessFactor(
                label: "Ambient heat index",
                warn: ambientWarn,
                detail: !ambientDataAvailable
                    ? "No ambient reading right now."
                    : ambientWarn
                        ? "Feels-like temperature has reached NOAA danger level."
                        : "Within a safe range.",
                scored: ambientDataAvailable
            ),
            WellnessFactor(
                label: "Heat-stress combination",
                warn: heatStressWarn,
                detail: !heatStressDataAvailable
                    ? "Not enough data to check right now."
                    : heatStressWarn
                        ? "High heat index together with an elevated body temperature."
                        : "No combined heat-stress signal right now.",
                scored: heatStressDataAvailable
            )
        ]
        return WellnessSnapshot(score: score, factors: factors, connected: connected)
    }
}
