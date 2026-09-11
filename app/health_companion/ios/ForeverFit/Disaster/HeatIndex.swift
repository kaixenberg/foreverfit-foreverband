import Foundation

public enum HeatStressLevel: String, CaseIterable, Codable {
    case normal = "Normal"
    case caution = "Caution"
    case extremeCaution = "Extreme Caution"
    case danger = "Danger"
    case extremeDanger = "Extreme Danger"

    public var isConcerning: Bool {
        self == .danger || self == .extremeDanger
    }
}

public struct HeatIndex {
    /// Computes Rothfusz NOAA Heat Index (°C) given temperature in Celsius and relative humidity (%)
    public static func compute(tempC: Double, relativeHumidity: Double) -> Double {
        let tempF = (tempC * 9.0 / 5.0) + 32.0
        let rh = relativeHumidity

        // Simple formula when cool/dry
        var hiF = 0.5 * (tempF + 61.0 + ((tempF - 68.0) * 1.2) + (rh * 0.094))

        if hiF >= 80.0 {
            // Full Rothfusz polynomial regression
            hiF = -42.379
                + (2.04901523 * tempF)
                + (10.14333127 * rh)
                - (0.22475541 * tempF * rh)
                - (0.00683783 * tempF * tempF)
                - (0.05481717 * rh * rh)
                + (0.00122874 * tempF * tempF * rh)
                + (0.00085282 * tempF * rh * rh)
                - (0.00000199 * tempF * tempF * rh * rh)

            if rh < 13.0 && tempF >= 80.0 && tempF <= 112.0 {
                let adj = ((13.0 - rh) / 4.0) * sqrt((17.0 - abs(tempF - 95.0)) / 17.0)
                hiF -= adj
            } else if rh > 85.0 && tempF >= 80.0 && tempF <= 87.0 {
                let adj = ((rh - 85.0) / 10.0) * ((87.0 - tempF) / 5.0)
                hiF += adj
            }
        }

        let hiC = (hiF - 32.0) * 5.0 / 9.0
        return max(tempC, hiC)
    }

    public static func stressLevel(heatIndexC: Double) -> HeatStressLevel {
        switch heatIndexC {
        case ..<27.0: return .normal
        case 27.0..<32.0: return .caution
        case 32.0..<41.0: return .extremeCaution
        case 41.0..<54.0: return .danger
        default: return .extremeDanger
        }
    }
}
