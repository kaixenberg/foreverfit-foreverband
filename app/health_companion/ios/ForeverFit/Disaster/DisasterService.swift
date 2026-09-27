import Foundation
import CoreLocation
import Combine

@MainActor
public final class DisasterService: NSObject, ObservableObject {
    @Published public var currentLocationName: String = "Locating…"
    @Published public var currentState: String = "West Bengal"
    @Published public var currentCoordinate: CLLocationCoordinate2D?
    @Published public var weather: WeatherReport = WeatherReport()
    @Published public var airQuality: AirQualityReport = AirQualityReport()
    @Published public var recentEarthquakes: [EarthquakeReport] = []
    @Published public var activeWarnings: [ImminentWarning] = []
    @Published public var pressureHistory: [(Date, Double)] = []

    public var pressureTrendHPa: Double? {
        guard let first = pressureHistory.first, let last = pressureHistory.last, pressureHistory.count >= 2 else { return nil }
        return last.1 - first.1
    }

    private let locationManager = CLLocationManager()
    private var refreshTimer: AnyCancellable?

    public override init() {
        super.init()

        // 1. Restore last known real GPS fix from persistent storage if available
        let savedLat = UserDefaults.standard.double(forKey: "last_gps_lat")
        let savedLon = UserDefaults.standard.double(forKey: "last_gps_lon")
        if savedLat != 0.0 && savedLon != 0.0 {
            self.currentCoordinate = CLLocationCoordinate2D(latitude: savedLat, longitude: savedLon)
            if let savedName = UserDefaults.standard.string(forKey: "last_gps_location_name"), !savedName.isEmpty {
                self.currentLocationName = savedName
            }
            if let savedState = UserDefaults.standard.string(forKey: "last_gps_state"), !savedState.isEmpty {
                self.currentState = savedState
            }
        } else {
            // Default baseline coordinate for user's test region (Bansberia, Hooghly, West Bengal)
            self.currentCoordinate = CLLocationCoordinate2D(latitude: 22.9644, longitude: 88.3995)
            self.currentLocationName = "Bansberia, Hooghly, West Bengal"
            self.currentState = "West Bengal"
        }

        setupLocationManager()
        evaluateImminentWarnings()

        Task {
            await refreshAllTelemetry()
        }
    }

    public func startLocationUpdates() {
        locationManager.startUpdatingLocation()
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100 // Trigger update on 100m move

        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
            if let loc = locationManager.location {
                updateLocation(coordinate: loc.coordinate)
            }
        }
    }

    public func updateLocation(coordinate: CLLocationCoordinate2D) {
        self.currentCoordinate = coordinate
        UserDefaults.standard.set(coordinate.latitude, forKey: "last_gps_lat")
        UserDefaults.standard.set(coordinate.longitude, forKey: "last_gps_lon")

        Task {
            await reverseGeocode(coordinate: coordinate)
            await refreshAllTelemetry()
        }
    }

    public func refreshAllTelemetry() async {
        let coord = effectiveCoordinate
        async let weatherTask = fetchWeather(coordinate: coord)
        async let airQualityTask = fetchAirQuality(coordinate: coord)
        async let quakesTask = fetchEarthquakes(coordinate: coord)

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

    private var effectiveCoordinate: CLLocationCoordinate2D {
        if let c = currentCoordinate { return c }
        if let loc = locationManager.location?.coordinate { return loc }
        let savedLat = UserDefaults.standard.double(forKey: "last_gps_lat")
        let savedLon = UserDefaults.standard.double(forKey: "last_gps_lon")
        if savedLat != 0.0 && savedLon != 0.0 {
            return CLLocationCoordinate2D(latitude: savedLat, longitude: savedLon)
        }
        // User's location (Bansberia / Hooghly)
        return CLLocationCoordinate2D(latitude: 22.9644, longitude: 88.3995)
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
            URLQueryItem(name: "maxradiuskm", value: "300"),
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
        // First try native iOS Apple CLGeocoder (fast, accurate, recognizes Indian towns & districts)
        let clLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let placemarks = try? await CLGeocoder().reverseGeocodeLocation(clLocation),
           let placemark = placemarks.first {
            var parts: [String] = []
            if let subLocality = placemark.subLocality, !subLocality.isEmpty {
                parts.append(subLocality)
            } else if let locality = placemark.locality, !locality.isEmpty {
                parts.append(locality)
            }
            if let subAdmin = placemark.subAdministrativeArea, !subAdmin.isEmpty, !parts.contains(subAdmin) {
                parts.append(subAdmin)
            }
            if let admin = placemark.administrativeArea, !admin.isEmpty, !parts.contains(admin) {
                parts.append(admin)
            }
            let resolvedName = parts.joined(separator: ", ")
            if !resolvedName.isEmpty {
                self.currentLocationName = resolvedName
                UserDefaults.standard.set(resolvedName, forKey: "last_gps_location_name")
            }
            if let state = placemark.administrativeArea {
                self.currentState = state
                UserDefaults.standard.set(state, forKey: "last_gps_state")
            }
            return
        }

        // Secondary fallback to OpenStreetMap Nominatim
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
                UserDefaults.standard.set(displayName, forKey: "last_gps_location_name")
            }
            if let address = json?["address"] as? [String: Any], let state = address["state"] as? String {
                self.currentState = state
                UserDefaults.standard.set(state, forKey: "last_gps_state")
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

// MARK: - CLLocationManagerDelegate
extension DisasterService: CLLocationManagerDelegate {
    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.startUpdatingLocation()
                if let loc = manager.location {
                    self.updateLocation(coordinate: loc.coordinate)
                }
            }
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.updateLocation(coordinate: loc.coordinate)
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location hardware error handled gracefully
    }
}
