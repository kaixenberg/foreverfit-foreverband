import Foundation
import CoreLocation
import Combine

@MainActor
public final class DisasterService: ObservableObject {
    @Published public var currentLocationName: String = "New Delhi, Delhi"
    @Published public var currentState: String = "Delhi"
    @Published public var weather: WeatherReport = WeatherReport()
    @Published public var airQuality: AirQualityReport = AirQualityReport()
    @Published public var recentEarthquakes: [EarthquakeReport] = []
    @Published public var activeWarnings: [ImminentWarning] = []
    @Published public var pressureHistory: [(Date, Double)] = []

    public var pressureTrendHPa: Double? {
        guard let first = pressureHistory.first, let last = pressureHistory.last, pressureHistory.count >= 2 else { return nil }
        return last.1 - first.1
    }

    private var currentCoordinate = CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090)
    private var refreshTimer: AnyCancellable?

    public init() {
        // Initial setup with Delhi baseline
        evaluateImminentWarnings()
        Task {
            await refreshAllTelemetry()
        }
    }

    public func updateLocation(coordinate: CLLocationCoordinate2D) {
        self.currentCoordinate = coordinate
        Task {
            await reverseGeocode(coordinate: coordinate)
            await refreshAllTelemetry()
        }
    }

    public func refreshAllTelemetry() async {
        async let weatherTask = fetchWeather(coordinate: currentCoordinate)
        async let airQualityTask = fetchAirQuality(coordinate: currentCoordinate)
        async let quakesTask = fetchEarthquakes(coordinate: currentCoordinate)

        if let w = await weatherTask {
            self.weather = w
            self.recordPressure(w.pressureHPa)
        }
        if let aq = await airQualityTask {
            self.airQuality = aq
        }
        if let eq = await quakesTask {
            self.recentEarthquakes = eq
        }

        evaluateImminentWarnings()
    }

    // MARK: - Open-Meteo Weather API

    private func fetchWeather(coordinate: CLLocationCoordinate2D) async -> WeatherReport? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,wind_speed_10m,pressure_msl"),
            URLQueryItem(name: "daily", value: "precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let current = json?["current"] as? [String: Any] else { return nil }

            let temp = (current["temperature_2m"] as? NSNumber)?.doubleValue ?? 28.0
            let rh = (current["relative_humidity_2m"] as? NSNumber)?.doubleValue ?? 60.0
            let wind = (current["wind_speed_10m"] as? NSNumber)?.doubleValue ?? 12.0
            let pressure = (current["pressure_msl"] as? NSNumber)?.doubleValue ?? 1012.0

            var precipProb = 10.0
            if let daily = json?["daily"] as? [String: Any],
               let probs = daily["precipitation_probability_max"] as? [NSNumber],
               let first = probs.first {
                precipProb = first.doubleValue
            }

            return WeatherReport(
                temperatureC: temp,
                relativeHumidity: rh,
                windSpeedKmh: wind,
                pressureHPa: pressure,
                precipitationProbability: precipProb,
                asOf: Date(),
                isLive: true
            )
        } catch {
            return nil
        }
    }

    // MARK: - Open-Meteo Air Quality API

    private func fetchAirQuality(coordinate: CLLocationCoordinate2D) async -> AirQualityReport? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(name: "current", value: "pm2_5,pm10,us_aqi"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let current = json?["current"] as? [String: Any] else { return nil }

            let aqi = (current["us_aqi"] as? NSNumber)?.doubleValue ?? 65.0
            let pm25 = (current["pm2_5"] as? NSNumber)?.doubleValue
            let pm10 = (current["pm10"] as? NSNumber)?.doubleValue

            return AirQualityReport(usAqi: aqi, pm25: pm25, pm10: pm10, asOf: Date(), isLive: true)
        } catch {
            return nil
        }
    }

    // MARK: - USGS Earthquake API

    private func fetchEarthquakes(coordinate: CLLocationCoordinate2D) async -> [EarthquakeReport]? {
        let startTime = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30 * 86400))
        var components = URLComponents(string: "https://earthquake.usgs.gov/fdsnws/event/1/query")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "geojson"),
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(name: "maxradiuskm", value: "250"),
            URLQueryItem(name: "minmagnitude", value: "4.0"),
            URLQueryItem(name: "starttime", value: startTime),
            URLQueryItem(name: "orderby", value: "magnitude")
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let features = json?["features"] as? [[String: Any]] else { return nil }

            var reports: [EarthquakeReport] = []
            for f in features.prefix(5) {
                if let props = f["properties"] as? [String: Any],
                   let mag = (props["mag"] as? NSNumber)?.doubleValue,
                   let place = props["place"] as? String,
                   let timeMs = (props["time"] as? NSNumber)?.doubleValue {
                    let date = Date(timeIntervalSince1970: timeMs / 1000.0)
                    reports.append(EarthquakeReport(magnitude: mag, place: place, distanceKm: 110.0, timestamp: date))
                }
            }
            return reports
        } catch {
            return nil
        }
    }

    // MARK: - Reverse Geocoding

    private func reverseGeocode(coordinate: CLLocationCoordinate2D) async {
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/reverse")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: "\(coordinate.latitude)"),
            URLQueryItem(name: "lon", value: "\(coordinate.longitude)"),
            URLQueryItem(name: "format", value: "jsonv2")
        ]

        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.setValue("ForeverFit-iOS/1.0 (Hackathon SIH2026)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            if let displayName = json?["display_name"] as? String {
                self.currentLocationName = displayName
            }
            if let address = json?["address"] as? [String: Any], let state = address["state"] as? String {
                self.currentState = state
            }
        } catch {
            // Retain existing known location
        }
    }

    // MARK: - Hazard Evaluation

    private func recordPressure(_ pressure: Double) {
        pressureHistory.append((Date(), pressure))
        if pressureHistory.count > 50 {
            pressureHistory.removeFirst()
        }
    }

    public func evaluateImminentWarnings() {
        var warnings: [ImminentWarning] = []

        // 1. Extreme Heatwave Check
        let hi = HeatIndex.compute(tempC: weather.temperatureC, relativeHumidity: weather.relativeHumidity)
        let stress = HeatIndex.stressLevel(heatIndexC: hi)
        if stress.isConcerning {
            warnings.append(ImminentWarning(
                hazardType: .extremeHeat,
                headline: "Severe Heat Index: \(String(format: "%.1f", hi))°C",
                actionPrompt: "Dangerous heat stress imminent. Stay in shaded/air-conditioned shelter and hydrate immediately.",
                severity: stress == .extremeDanger ? .critical : .warning
            ))
        }

        // 2. Rapid Barometric Pressure Drop (Storm/Cyclone)
        if let first = pressureHistory.first, let last = pressureHistory.last {
            let drop = first.1 - last.1
            if drop >= 3.0 {
                warnings.append(ImminentWarning(
                    hazardType: .cyclone,
                    headline: "Rapid Barometric Drop (-\(String(format: "%.1f", drop)) hPa)",
                    actionPrompt: "Severe atmospheric instability detected. High probability of squall or cyclone.",
                    severity: .critical
                ))
            }
        }

        // 3. Air Quality Warning
        if airQuality.usAqi > 150 {
            warnings.append(ImminentWarning(
                hazardType: .airQuality,
                headline: "Unhealthy AQI (\(Int(airQuality.usAqi)))",
                actionPrompt: "Particulate PM2.5 levels are elevated. Vulnerable individuals and asthmatics must wear N95 filtration.",
                severity: airQuality.usAqi > 200 ? .critical : .warning
            ))
        }

        // 4. Offline State Hazard Baseline
        let stateProfile = IndiaHazardData.hazardProfile(for: currentState)
        if stateProfile.seismicZone == .v {
            warnings.append(ImminentWarning(
                hazardType: .earthquake,
                headline: "High Seismic Vulnerability (\(currentState))",
                actionPrompt: "Located in BIS Seismic Zone V. Keep emergency go-bag ready and inspect primary structural exits.",
                severity: .warning
            ))
        }

        self.activeWarnings = warnings
    }
}
