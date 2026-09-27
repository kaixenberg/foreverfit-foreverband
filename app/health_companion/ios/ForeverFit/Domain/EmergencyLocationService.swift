import Foundation
import CoreLocation

public struct EmergencyLocation {
    public let text: String
    public let latitude: Double?
    public let longitude: Double?

    public init(text: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.text = text
        self.latitude = latitude
        self.longitude = longitude
    }

    public static let fallback = EmergencyLocation(
        text: "User GPS Coordinates (Resolving live satellite fix...)",
        latitude: nil,
        longitude: nil
    )
}

public final class EmergencyLocationService: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?

    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        locationManager.startUpdatingLocation()
        if let current = locationManager.location {
            self.lastLocation = current
        }
    }

    public func resolveLocation() async -> EmergencyLocation {
        let loc = lastLocation ?? locationManager.location
        if let loc = loc {
            let lat = loc.coordinate.latitude
            let lon = loc.coordinate.longitude
            let latLonStr = String(format: "%.5f, %.5f", lat, lon)

            // Reverse geocode via native CLGeocoder
            if let placemark = try? await CLGeocoder().reverseGeocodeLocation(loc).first {
                var addressParts: [String] = []
                if let name = placemark.name { addressParts.append(name) }
                if let subLocality = placemark.subLocality, !addressParts.contains(subLocality) { addressParts.append(subLocality) }
                if let locality = placemark.locality, !addressParts.contains(locality) { addressParts.append(locality) }
                if let subAdmin = placemark.subAdministrativeArea, !addressParts.contains(subAdmin) { addressParts.append(subAdmin) }
                if let adminArea = placemark.administrativeArea, !addressParts.contains(adminArea) { addressParts.append(adminArea) }
                let formatted = addressParts.joined(separator: ", ")
                return EmergencyLocation(text: "\(formatted) (\(latLonStr))", latitude: lat, longitude: lon)
            }

            return EmergencyLocation(text: "Coordinates: \(latLonStr)", latitude: lat, longitude: lon)
        }

        // Try cached coordinates from UserDefaults if location hardware is still acquiring
        let cachedLat = UserDefaults.standard.double(forKey: "last_gps_lat")
        let cachedLon = UserDefaults.standard.double(forKey: "last_gps_lon")
        if cachedLat != 0.0 && cachedLon != 0.0 {
            let latLonStr = String(format: "%.5f, %.5f", cachedLat, cachedLon)
            return EmergencyLocation(text: "Recent Coordinates: \(latLonStr)", latitude: cachedLat, longitude: cachedLon)
        }

        return EmergencyLocation.fallback
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            self.lastLocation = loc
            UserDefaults.standard.set(loc.coordinate.latitude, forKey: "last_gps_lat")
            UserDefaults.standard.set(loc.coordinate.longitude, forKey: "last_gps_lon")
        }
    }
}
