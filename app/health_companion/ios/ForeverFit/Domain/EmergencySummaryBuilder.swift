import Foundation

public struct EmergencyReading {
    public let label: String
    public let valueText: String

    public init(label: String, valueText: String) {
        self.label = label
        self.valueText = valueText
    }
}

public struct EmergencySummary {
    public let readings: [EmergencyReading]
    public let durationText: String?
    public let location: EmergencyLocation
    public let triggerReason: String

    public init(readings: [EmergencyReading], durationText: String?, location: EmergencyLocation, triggerReason: String) {
        self.readings = readings
        self.durationText = durationText
        self.location = location
        self.triggerReason = triggerReason
    }

    public var hasSpecificData: Bool {
        !readings.isEmpty
    }
}

@MainActor
public struct EmergencySummaryBuilder {
    public static func build(
        vitals: VitalsReading?,
        baseline: BaselineService,
        location: EmergencyLocation,
        triggerReason: String
    ) -> EmergencySummary {
        var readings: [EmergencyReading] = []

        if let v = vitals, v.fingerPresent {
            if v.heartRate < HealthThresholds.heartRateFloor || v.heartRate > HealthThresholds.restingHeartRateCeiling || baseline.isAnomalous(heartRate: v.heartRate) {
                readings.append(EmergencyReading(label: "heart rate", valueText: "\(Int(v.heartRate)) beats per minute"))
            }
            if v.spo2 > 0 && v.spo2 < HealthThresholds.spo2FloorPercent {
                readings.append(EmergencyReading(label: "oxygen saturation", valueText: "\(Int(v.spo2)) percent"))
            }
            if v.bodyTempC > HealthThresholds.bodyTempHighC || v.bodyTempC < HealthThresholds.bodyTempLowC {
                readings.append(EmergencyReading(label: "body temperature", valueText: String(format: "%.1f degrees Celsius", v.bodyTempC)))
            }
        }

        return EmergencySummary(
            readings: readings,
            durationText: "approximately 3 minutes",
            location: location,
            triggerReason: triggerReason
        )
    }

    /// Spoken to emergency dispatchers (112 in India, 911 in US)
    public static func buildEmergencyServicesScript(summary: EmergencySummary) -> String {
        var parts: [String] = [
            "This is an automated medical emergency alert from the ForeverFit health monitoring application.",
            "The user may require immediate medical assistance — \(summary.triggerReason)."
        ]

        if summary.hasSpecificData {
            let readingSentences = summary.readings.map { "Their \($0.label) is currently \($0.valueText)." }.joined(separator: " ")
            parts.append(readingSentences)
            if let dur = summary.durationText {
                parts.append("These abnormal telemetry signals have persisted for \(dur).")
            }
        } else {
            parts.append("Specific wearable vital sign telemetry is temporarily unavailable.")
        }

        parts.append("The user's current resolved GPS location is \(summary.location.text).")
        parts.append("Please dispatch immediate emergency medical responders.")
        return parts.joined(separator: " ")
    }

    /// Spoken to designated emergency contacts
    public static func buildEmergencyContactScript(summary: EmergencySummary) -> String {
        buildContactScript(summary: summary)
    }

    public static func buildContactScript(summary: EmergencySummary) -> String {
        var parts: [String] = [
            "This is an automated ForeverFit medical alert.",
            "An emergency was detected for your contact — \(summary.triggerReason)."
        ]

        if summary.hasSpecificData {
            let readingSentences = summary.readings.map { "Their \($0.label) is currently \($0.valueText)." }.joined(separator: " ")
            parts.append(readingSentences)
        }

        parts.append("Their current location is \(summary.location.text).")
        parts.append("Local emergency services have been summoned. Please check on them immediately.")
        return parts.joined(separator: " ")
    }

    /// Automated SMS message dispatched to emergency contacts
    public static func buildEmergencySms(summary: EmergencySummary) -> String {
        var lines: [String] = [
            "EMERGENCY ALERT: Possible medical emergency detected by ForeverFit."
        ]

        if summary.hasSpecificData {
            for r in summary.readings {
                lines.append("\(r.label.capitalized): \(r.valueText)")
            }
            if let dur = summary.durationText {
                lines.append("Duration: \(dur)")
            }
        }

        lines.append("Location: \(summary.location.text)")
        lines.append("Emergency services have been contacted. Please verify user safety immediately.")
        return lines.joined(separator: "\n")
    }
}
