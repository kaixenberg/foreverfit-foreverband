import Foundation

/// Builds a compact, natural-language snapshot of the user's live data —
/// wearable vitals, environment, body metrics, activity, and health log —
/// so the on-device AI assistant answers grounded in real telemetry.
/// Matches lib/ai_chat/health_context_builder.dart
@MainActor
public struct HealthContextBuilder {
    public static func build(
        userProfile: UserProfile,
        medicalId: MedicalId,
        vitals: VitalsReading?,
        env: EnvReading?,
        baseline: BaselineService,
        todaySteps: Int,
        currentActivity: ActivityState?,
        latestBP: BloodPressureEntry?,
        latestGlucose: BloodGlucoseEntry?,
        weather: WeatherReport?,
        airQuality: AirQualityReport?
    ) -> String {
        var lines: [String] = []

        // User Demographics
        let age = userProfile.calculatedAge
        lines.append("User: \(userProfile.name), age \(age), \(userProfile.sex).")

        // Wearable Live Vitals
        if let v = vitals, v.fingerPresent {
            let baseText = baseline.heartRateMean != nil
                ? " (personal baseline resting avg \(Int(baseline.heartRateMean!)) bpm)"
                : ""
            lines.append("Live vitals right now: heart rate \(Int(v.heartRate)) bpm\(baseText), SpO2 \(Int(v.spo2))%, body temperature \(String(format: "%.1f", v.bodyTempC))°C.")
        } else if vitals != nil {
            lines.append("Wearable connected but no skin contact detected — no live PPG vitals right now.")
        } else {
            lines.append("No wearable connected right now.")
        }

        // Environment
        if let e = env {
            lines.append("Environment: ambient \(String(format: "%.1f", e.ambientTempC))°C, humidity \(Int(e.humidity))%, pressure \(Int(e.pressureHPa)) hPa.")
        } else if let w = weather {
            lines.append("Local Weather: \(String(format: "%.1f", w.temperatureC))°C, humidity \(Int(w.relativeHumidity))%, wind \(Int(w.windSpeedKmh)) km/h.")
        }

        // Body & Activity
        let bmi = HealthCalculations.computeBMI(weightKg: userProfile.defaultWeightKg, heightCm: userProfile.defaultHeightCm)
        var bodyParts: [String] = []
        if let w = userProfile.defaultWeightKg { bodyParts.append("weight \(String(format: "%.1f", w)) kg") }
        if let h = userProfile.defaultHeightCm { bodyParts.append("height \(Int(h)) cm") }
        if let b = bmi { bodyParts.append("BMI \(String(format: "%.1f", b))") }
        if !bodyParts.isEmpty { lines.append("Body: \(bodyParts.joined(separator: ", ")).") }

        let actStr = currentActivity?.rawValue ?? "Still"
        lines.append("Activity: \(todaySteps) steps today, currently \(actStr).")

        // Health Log
        var logParts: [String] = []
        if let bp = latestBP { logParts.append("blood pressure \(bp.systolic)/\(bp.diastolic) mmHg") }
        if let g = latestGlucose { logParts.append("blood glucose \(Int(g.glucoseMgDl)) mg/dL") }
        if !medicalId.allergies.isEmpty { logParts.append("allergies: \(medicalId.allergies)") }
        if !medicalId.notes.isEmpty { logParts.append("notes: \(medicalId.notes)") }

        if !logParts.isEmpty {
            lines.append("Health log: \(logParts.joined(separator: "; ")).")
        }

        if let aq = airQuality {
            lines.append("Air Quality: US AQI \(Int(aq.usAqi)) (\(aq.aqiCategory)).")
        }

        return lines.joined(separator: "\n")
    }
}
