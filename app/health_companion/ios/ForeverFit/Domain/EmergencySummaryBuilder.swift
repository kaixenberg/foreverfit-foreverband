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
        connectedAt: Date? = nil,
        watchSettings: WatchSettings = WatchSettings.defaults,
        baseline: BaselineService,
        location: EmergencyLocation,
        triggerReason: String
    ) -> EmergencySummary {
        var readings: [EmergencyReading] = []

        // Body temp comes from the DS18B20 on its own 1-Wire GPIO, independent of
        // the MAX30102's finger contact — its own "no reading" gate is 0°C
        // rather than finger contact.
        let hasBodyTempReading = vitals != nil && vitals!.bodyTempC != 0
        let bodyTempPastEquilibrium: Bool
        if let conn = connectedAt {
            bodyTempPastEquilibrium = Date().timeIntervalSince(conn) >= HealthThresholds.bodyTempEquilibrationWindow
        } else {
            bodyTempPastEquilibrium = true
        }
        let bodyTempWarnEligible = hasBodyTempReading &&
            !watchSettings.ignoreBodyTempContactCheck &&
            bodyTempPastEquilibrium

        // Only READY values — contact alone isn't a reading (the PPG pipeline
        // settles and counts beats first), and a spoken emergency summary is the
        // worst place to read out a half-measured number.
        if let v = vitals, v.hasHeartRate {
            let hr = v.heartRate
            if hr < HealthThresholds.heartRateFloor || hr > HealthThresholds.restingHeartRateCeiling || baseline.isAnomalous(heartRate: hr) {
                readings.append(EmergencyReading(label: "heart rate", valueText: "\(Int(hr)) beats per minute"))
            }
        }

        if let v = vitals, v.hasSpo2 {
            if v.spo2 < HealthThresholds.spo2FloorPercent {
                readings.append(EmergencyReading(label: "oxygen saturation", valueText: "\(Int(v.spo2)) percent"))
            }
        }

        if let v = vitals, bodyTempWarnEligible {
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
