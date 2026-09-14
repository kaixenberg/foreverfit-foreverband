import SwiftUI
import MapKit

public struct MapShelterPoint: Identifiable {
    public var id = UUID()
    public let name: String
    public let type: ShelterType
    public let coordinate: CLLocationCoordinate2D

    public enum ShelterType {
        case evacuationCenter
        case hospital
        case disasterRelief
    }
}

public struct DisasterMapView: View {
    @ObservedObject var disasterService: DisasterService
    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    private let shelterPoints: [MapShelterPoint] = [
        MapShelterPoint(name: "Central Evacuation Assembly (Stadium)", type: .evacuationCenter, coordinate: CLLocationCoordinate2D(latitude: 28.6210, longitude: 77.2140)),
        MapShelterPoint(name: "City Emergency Hospital & Trauma", type: .hospital, coordinate: CLLocationCoordinate2D(latitude: 28.6080, longitude: 77.2030)),
        MapShelterPoint(name: "NDRF Disaster Relief Camp", type: .disasterRelief, coordinate: CLLocationCoordinate2D(latitude: 28.6280, longitude: 77.2250))
    ]

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    // User Pin
                    Annotation("Your Location", coordinate: CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090)) {
                        ZStack {
                            Circle()
                                .fill(LiquidGlassTheme.neonCyan.opacity(0.3))
                                .frame(width: 32, height: 32)
                            Circle()
                                .fill(LiquidGlassTheme.neonCyan)
                                .frame(width: 14, height: 14)
                        }
                    }

                    // Emergency Shelter Points
                    ForEach(shelterPoints) { shelter in
                        Annotation(shelter.name, coordinate: shelter.coordinate) {
                            shelterBadge(for: shelter.type)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .ignoresSafeArea(edges: .bottom)

                // Liquid Floating Legend Overlay
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        legendItem(icon: "shield.checkered", color: LiquidGlassTheme.emeraldGreen, label: "Assembly")
                        legendItem(icon: "cross.case.fill", color: LiquidGlassTheme.alertCrimson, label: "Hospital")
                        legendItem(icon: "tent.fill", color: LiquidGlassTheme.amberWarning, label: "Relief")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .liquidGlass(cornerRadius: 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("Emergency Radar Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(LiquidGlassTheme.neonCyan)
                }
            }
        }
    }

    private func shelterBadge(for type: MapShelterPoint.ShelterType) -> some View {
        let icon: String = {
            switch type {
            case .evacuationCenter: return "shield.checkered"
            case .hospital: return "cross.case.fill"
            case .disasterRelief: return "tent.fill"
            }
        }()
        let color: Color = {
            switch type {
            case .evacuationCenter: return LiquidGlassTheme.emeraldGreen
            case .hospital: return LiquidGlassTheme.alertCrimson
            case .disasterRelief: return LiquidGlassTheme.amberWarning
            }
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(color)
                .frame(width: 28, height: 28)
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .shadow(color: color.opacity(0.6), radius: 6, x: 0, y: 3)
    }

    private func legendItem(icon: String, color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
        }
    }
}
