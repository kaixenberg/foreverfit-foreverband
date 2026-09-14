import Foundation

public struct InsightEngine {
    public static func computeInsights(
        vitals: VitalsReading?,
        env: EnvReading?,
        weather: WeatherReport?,
        activity: ActivityState?,
        baselineHeartRateMean: Double?,
        latestBP: (Int, Int)?,
        latestGlucose: Double?,
        latestSleep: Double?,
        pressureTrendHPa: Double?,
        earthquakesCount: Int,
        aqi: Int?
    ) -> [Insight] {
        var results: [Insight] = []

        // 1. Vital Signs
        if let v = vitals, v.fingerPresent {
            let hr = v.heartRate
            let ceiling = HealthThresholds.heartRateCeiling(for: activity)

            if hr < HealthThresholds.heartRateFloor || hr > ceiling {
                results.append(Insight(
                    id: "vitals.hr.range",
                    title: hr < HealthThresholds.heartRateFloor ? "Low heart rate" : "High heart rate",
                    message: String(format: "%.0f bpm is outside normal bounds (%.0f–%.0f bpm for current activity).", hr, HealthThresholds.heartRateFloor, ceiling),
                    severity: .warning,
                    category: .vitals,
                    iconName: "heart.fill"
                ))
            }

            if v.spo2 < HealthThresholds.spo2Floor {
                results.append(Insight(
                    id: "vitals.spo2.low",
                    title: "Low blood oxygen",
                    message: String(format: "SpO2 is %.0f%% (below normal %.0f%% minimum). Rest and breathe deeply.", v.spo2, HealthThresholds.spo2Floor),
                    severity: .critical,
                    category: .vitals,
                    iconName: "lungs.fill"
                ))
            }

            if v.bodyTempC < HealthThresholds.bodyTempLowC || v.bodyTempC > HealthThresholds.bodyTempHighC {
                results.append(Insight(
                    id: "vitals.temp.range",
                    title: v.bodyTempC < HealthThresholds.bodyTempLowC ? "Low body temperature" : "Elevated temperature",
                    message: String(format: "Body temp is %.1f°C (normal: %.1f–%.1f°C).", v.bodyTempC, HealthThresholds.bodyTempLowC, HealthThresholds.bodyTempHighC),
                    severity: .warning,
                    category: .vitals,
                    iconName: "thermometer.medium"
                ))
            }

            if let base = baselineHeartRateMean {
                let diff = Double(hr) - base
                if abs(diff) > 20.0 {
                    results.append(Insight(
                        id: "vitals.hr.baseline",
                        title: diff > 0 ? "Elevated from baseline" : "Below resting baseline",
                        message: String(format: "Heart rate is %.0f bpm higher than your baseline average (%.0f bpm).", abs(diff), base),
                        severity: .info,
                        category: .vitals,
                        iconName: "chart.line.uptrend.xyaxis"
                    ))
                }
            }
        }

        // 2. Blood Pressure
        if let bp = latestBP {
            if bp.0 >= HealthThresholds.bpCrisisSystolic || bp.1 >= HealthThresholds.bpCrisisDiastolic {
                results.append(Insight(
                    id: "vitals.bp.crisis",
                    title: "Hypertensive crisis range",
                    message: "Blood pressure \(bp.0)/\(bp.1) mmHg is in the crisis range. Consult medical help immediately if symptomatic.",
                    severity: .critical,
                    category: .vitals,
                    iconName: "cross.fill"
                ))
            } else if bp.0 >= HealthThresholds.bpElevatedSystolic || bp.1 >= HealthThresholds.bpElevatedDiastolic {
                results.append(Insight(
                    id: "vitals.bp.elevated",
                    title: "Elevated blood pressure",
                    message: "Recent blood pressure is \(bp.0)/\(bp.1) mmHg (target < 120/80 mmHg).",
                    severity: .warning,
                    category: .vitals,
                    iconName: "heart.text.square.fill"
                ))
            }
        }

        // 3. Glucose & Sleep
        if let g = latestGlucose, g < HealthThresholds.glucoseLowMgDl || g > HealthThresholds.glucoseHighMgDl {
            results.append(Insight(
                id: "vitals.glucose.range",
                title: g < HealthThresholds.glucoseLowMgDl ? "Low blood glucose" : "High blood glucose",
                message: String(format: "%.0f mg/dL is outside normal non-fasting target (70–180 mg/dL).", g),
                severity: .warning,
                category: .vitals,
                iconName: "drop.fill"
            ))
        }

        if let s = latestSleep, s < HealthThresholds.sleepLowHours {
            results.append(Insight(
                id: "vitals.sleep.low",
                title: "Short sleep logged",
                message: String(format: "%.1f hours is below recommended 6.0 hour minimum.", s),
                severity: .info,
                category: .vitals,
                iconName: "bed.double.fill"
            ))
        }

        // 4. Disaster & Weather
        let ambientTemp = env?.ambientTempC ?? Float(weather?.temperatureC ?? 26.0)
        let humidity = env?.humidity ?? Float(weather?.relativeHumidity ?? 50.0)
        let heatIdx = HeatIndex.compute(tempC: Double(ambientTemp), relativeHumidity: Double(humidity))
        let risk = HeatIndex.stressLevel(heatIndexC: heatIdx)

        if risk == .danger || risk == .extremeDanger {
            results.append(Insight(
                id: "env.heat.danger",
                title: "Extreme heat index",
                message: String(format: "Feels-like temperature is %.1f°C. Stay hydrated and avoid outdoor exposure.", heatIdx),
                severity: .critical,
                category: .hazards,
                iconName: "sun.max.trianglebadge.exclamationmark.fill"
            ))
        }

        if let v = vitals, v.fingerPresent, v.bodyTempC > HealthThresholds.bodyTempHighC && (risk == .caution || risk == .extremeCaution || risk == .danger) {
            results.append(Insight(
                id: "env.heatstress.combined",
                title: "Heat stress combination",
                message: "High ambient heat combined with elevated body temperature. Move to a cool area immediately.",
                severity: .critical,
                category: .hazards,
                iconName: "flame.fill"
            ))
        }

        if let q = aqi, q >= HealthThresholds.aqiUnhealthy {
            results.append(Insight(
                id: "env.aqi.unhealthy",
                title: q >= HealthThresholds.aqiVeryUnhealthy ? "Hazardous air quality" : "Unhealthy air quality",
                message: "AQI \(q) poses health risks. Wear a mask or stay indoors.",
                severity: q >= HealthThresholds.aqiVeryUnhealthy ? .critical : .warning,
                category: .hazards,
                iconName: "aqi.high"
            ))
        }

        if let drop = pressureTrendHPa, drop <= -3.0 {
            results.append(Insight(
                id: "env.baro.drop",
                title: "Sudden barometric drop",
                message: String(format: "Atmospheric pressure fell %.1f hPa in past 3 hours. Storm approaching.", abs(drop)),
                severity: .warning,
                category: .hazards,
                iconName: "cloud.bolt.rain.fill"
            ))
        }

        if earthquakesCount > 0 {
            results.append(Insight(
                id: "env.quake.recent",
                title: "Recent seismic activity",
                message: "\(earthquakesCount) earthquake(s) recorded in your region recently.",
                severity: .info,
                category: .hazards,
                iconName: "waveform.path.ecg"
            ))
        }

        return results
    }
}
