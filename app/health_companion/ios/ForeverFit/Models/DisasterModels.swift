import Foundation

public enum HazardType: String, CaseIterable, Identifiable, Codable {
    case earthquake = "Earthquake"
    case flood = "Flood"
    case cyclone = "Cyclone / Storm"
    case extremeHeat = "Heat Wave"
    case airQuality = "Hazardous Air Quality"
    case stormApproaching = "Sudden Weather Change"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .earthquake: return "Earthquake"
        case .flood: return "Flood"
        case .cyclone: return "Cyclone / storm"
        case .extremeHeat: return "Heat wave"
        case .airQuality: return "Hazardous Air Quality"
        case .stormApproaching: return "Sudden weather change approaching"
        }
    }

    public var iconName: String {
        switch self {
        case .earthquake: return "waveform.path.ecg"
        case .flood: return "water.waves"
        case .cyclone: return "tornado"
        case .extremeHeat: return "sun.max.trianglebadge.exclamationmark.fill"
        case .airQuality: return "aqi.high"
        case .stormApproaching: return "cloud.bolt.rain.fill"
        }
    }

    public var icon: String { iconName }

    public var actions: [String] {
        switch self {
        case .earthquake:
            return [
                "Drop, Cover, and Hold On — get under a sturdy table or desk",
                "Stay away from windows, mirrors, and furniture that could fall",
                "If outdoors, move to open ground away from buildings and power lines",
                "Do not use elevators"
            ]
        case .flood:
            return [
                "Move to higher ground immediately",
                "Avoid walking or driving through flood water",
                "Turn off electrical appliances if water is rising indoors",
                "Keep emergency supplies (water, medicines, documents) ready to grab"
            ]
        case .cyclone:
            return [
                "Stay indoors, away from windows and glass doors",
                "Secure loose outdoor objects only if you can do so safely",
                "Keep a battery-powered light and a charged phone ready",
                "Avoid travel until the storm passes"
            ]
        case .extremeHeat:
            return [
                "Stay hydrated — drink water even if not thirsty",
                "Avoid outdoor activity during peak heat hours (12pm-4pm)",
                "Wear light-colored, loose-fitting clothing",
                "Watch for dizziness, nausea, or cramps — signs of heat exhaustion"
            ]
        case .airQuality:
            return [
                "Wear a fitted N95 mask if outdoor transit is unavoidable",
                "Keep indoor windows tightly closed and run HEPA air filtration",
                "Avoid heavy outdoor cardio or exertion",
                "Keep bronchodilator or asthma inhalers within arm's reach"
            ]
        case .stormApproaching:
            return [
                "A rapid drop in barometric pressure usually means a storm is moving in within a few hours",
                "Move indoors and stay away from windows and glass doors",
                "Secure or bring in loose outdoor objects only if you can do so safely",
                "Postpone travel until conditions stabilize",
                "Keep a charged phone and a light source ready"
            ]
        }
    }
}

public enum SeismicZone: String, CaseIterable, Codable {
    case ii = "Zone II (Low)"
    case iii = "Zone III (Moderate)"
    case iv = "Zone IV (High)"
    case v = "Zone V (Very Severe)"
}

public struct StateHazardProfile: Codable {
    public let seismicZone: SeismicZone
    public let cycloneProne: Bool
    public let floodProne: Bool

    public init(seismicZone: SeismicZone, cycloneProne: Bool, floodProne: Bool) {
        self.seismicZone = seismicZone
        self.cycloneProne = cycloneProne
        self.floodProne = floodProne
    }
}

public struct WeatherReport: Codable {
    public let temperatureC: Double
    public let relativeHumidity: Double
    public let windSpeedKmh: Double
    public let pressureHPa: Double
    public let precipitationProbability: Double
    public let asOf: Date
    public let isLive: Bool

    public init(
        temperatureC: Double = 28.5,
        relativeHumidity: Double = 62.0,
        windSpeedKmh: Double = 14.0,
        pressureHPa: Double = 1012.0,
        precipitationProbability: Double = 15.0,
        asOf: Date = Date(),
        isLive: Bool = true
    ) {
        self.temperatureC = temperatureC
        self.relativeHumidity = relativeHumidity
        self.windSpeedKmh = windSpeedKmh
        self.pressureHPa = pressureHPa
        self.precipitationProbability = precipitationProbability
        self.asOf = asOf
        self.isLive = isLive
    }
}

public struct AirQualityReport: Codable {
    public let usAqi: Double
    public let pm25: Double?
    public let pm10: Double?
    public let asOf: Date
    public let isLive: Bool

    public init(usAqi: Double = 54.0, pm25: Double? = 14.2, pm10: Double? = 28.0, asOf: Date = Date(), isLive: Bool = true) {
        self.usAqi = usAqi
        self.pm25 = pm25
        self.pm10 = pm10
        self.asOf = asOf
        self.isLive = isLive
    }

    public var aqiCategory: String {
        switch usAqi {
        case 0...50: return "Good"
        case 51...100: return "Moderate"
        case 101...150: return "Unhealthy for Sensitive Groups"
        case 151...200: return "Unhealthy"
        case 201...300: return "Very Unhealthy"
        default: return "Hazardous"
        }
    }
}

public struct EarthquakeReport: Identifiable, Codable {
    public var id: String
    public let magnitude: Double
    public let place: String
    public let distanceKm: Double
    public let timestamp: Date

    public init(id: String = UUID().uuidString, magnitude: Double, place: String, distanceKm: Double, timestamp: Date = Date()) {
        self.id = id
        self.magnitude = magnitude
        self.place = place
        self.distanceKm = distanceKm
        self.timestamp = timestamp
    }
}

public struct ImminentWarning: Identifiable {
    public var id: UUID = UUID()
    public let hazardType: HazardType
    public let headline: String
    public let actionPrompt: String
    public let severity: Severity

    public enum Severity {
        case warning
        case critical
    }

    public init(hazardType: HazardType, headline: String, actionPrompt: String, severity: Severity) {
        self.hazardType = hazardType
        self.headline = headline
        self.actionPrompt = actionPrompt
        self.severity = severity
    }
}
