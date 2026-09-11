import Foundation

/// 100% Offline State-Level Disaster Baseline for India
/// Per Bureau of Indian Standards (BIS IS 1893:2016) and NDMA hazard profiles.
/// Matches lib/disaster/india_hazard_data.dart
public struct IndiaHazardData {
    public static let stateHazards: [String: StateHazardProfile] = [
        "Jammu and Kashmir": StateHazardProfile(seismicZone: .v, cycloneProne: false, floodProne: false),
        "Ladakh": StateHazardProfile(seismicZone: .v, cycloneProne: false, floodProne: false),
        "Himachal Pradesh": StateHazardProfile(seismicZone: .v, cycloneProne: false, floodProne: false),
        "Uttarakhand": StateHazardProfile(seismicZone: .v, cycloneProne: false, floodProne: false),
        "Gujarat": StateHazardProfile(seismicZone: .v, cycloneProne: true, floodProne: false),
        "Assam": StateHazardProfile(seismicZone: .v, cycloneProne: false, floodProne: true),
        "Arunachal Pradesh": StateHazardProfile(seismicZone: .v, cycloneProne: false, floodProne: false),
        "Manipur": StateHazardProfile(seismicZone: .v, cycloneProne: false, floodProne: false),
        "Meghalaya": StateHazardProfile(seismicZone: .v, cycloneProne: false, floodProne: false),
        "Mizoram": StateHazardProfile(seismicZone: .v, cycloneProne: false, floodProne: false),
        "Nagaland": StateHazardProfile(seismicZone: .v, cycloneProne: false, floodProne: false),
        "Tripura": StateHazardProfile(seismicZone: .v, cycloneProne: false, floodProne: false),
        "Andaman and Nicobar Islands": StateHazardProfile(seismicZone: .v, cycloneProne: true, floodProne: false),
        "Bihar": StateHazardProfile(seismicZone: .v, cycloneProne: false, floodProne: true),
        "Delhi": StateHazardProfile(seismicZone: .iv, cycloneProne: false, floodProne: false),
        "Punjab": StateHazardProfile(seismicZone: .iv, cycloneProne: false, floodProne: false),
        "Haryana": StateHazardProfile(seismicZone: .iv, cycloneProne: false, floodProne: false),
        "Uttar Pradesh": StateHazardProfile(seismicZone: .iv, cycloneProne: false, floodProne: true),
        "West Bengal": StateHazardProfile(seismicZone: .iv, cycloneProne: true, floodProne: true),
        "Sikkim": StateHazardProfile(seismicZone: .iv, cycloneProne: false, floodProne: false),
        "Maharashtra": StateHazardProfile(seismicZone: .iv, cycloneProne: true, floodProne: false),
        "Odisha": StateHazardProfile(seismicZone: .iii, cycloneProne: true, floodProne: true),
        "Andhra Pradesh": StateHazardProfile(seismicZone: .iii, cycloneProne: true, floodProne: false),
        "Tamil Nadu": StateHazardProfile(seismicZone: .iii, cycloneProne: true, floodProne: false),
        "Kerala": StateHazardProfile(seismicZone: .iii, cycloneProne: false, floodProne: true),
        "Karnataka": StateHazardProfile(seismicZone: .iii, cycloneProne: false, floodProne: false),
        "Goa": StateHazardProfile(seismicZone: .iii, cycloneProne: true, floodProne: false),
        "Rajasthan": StateHazardProfile(seismicZone: .iii, cycloneProne: false, floodProne: false),
        "Madhya Pradesh": StateHazardProfile(seismicZone: .iii, cycloneProne: false, floodProne: false),
        "Chhattisgarh": StateHazardProfile(seismicZone: .iii, cycloneProne: false, floodProne: false),
        "Jharkhand": StateHazardProfile(seismicZone: .iii, cycloneProne: false, floodProne: false),
        "Telangana": StateHazardProfile(seismicZone: .ii, cycloneProne: false, floodProne: false)
    ]

    public static func hazardProfile(for state: String) -> StateHazardProfile {
        for (key, profile) in stateHazards {
            if state.localizedCaseInsensitiveContains(key) {
                return profile
            }
        }
        return StateHazardProfile(seismicZone: .iii, cycloneProne: false, floodProne: false)
    }
}
