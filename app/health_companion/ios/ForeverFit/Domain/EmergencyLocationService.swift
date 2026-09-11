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
        text: "Connaught Place, New Delhi, Delhi 110001 (Lat 28.6315, Lon 77.2167)",
        latitude: 28.6315,
        longitude: 77.2167
    )
}

public final class EmergencyLocationService: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?

    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    public func resolveLocation() async -> EmergencyLocation {
        if let loc = lastLocation {
            let lat = loc.coordinate.latitude
            let lon = loc.coordinate.longitude
            let latLonStr = String(format: "%.5f, %.5f", lat, lon)

            // Attempt reverse geocode via CLGeocoder
            if let placemark = try? await CLGeocoder().reverseGeocodeLocation(loc).first {
                var addressParts: [String] = []
                if let name = placemark.name { addressParts.append(name) }
                if let subLocality = placemark.subLocality { addressParts.append(subLocality) }
                if let locality = placemark.locality { addressParts.append(locality) }
                if let adminArea = placemark.administrativeArea { addressParts.append(adminArea) }
                let formatted = addressParts.joined(separator: ", ")
                return EmergencyLocation(text: "\(formatted) (\(latLonStr))", latitude: lat, longitude: lon)
            }

            return EmergencyLocation(text: "Coordinates: \(latLonStr)", latitude: lat, longitude: lon)
        }

        return EmergencyLocation.fallback
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.lastLocation = locations.last
    }
}
