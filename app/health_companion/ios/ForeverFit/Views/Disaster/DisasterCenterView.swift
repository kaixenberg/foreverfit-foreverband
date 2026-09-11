import SwiftUI

public struct DisasterCenterView: View {
    @ObservedObject var disasterService: DisasterService
    @State private var showingMapView = false

    public init(disasterService: DisasterService) {
        self.disasterService = disasterService
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                // Header
                headerSection

                // Active Warnings List
                if !disasterService.activeWarnings.isEmpty {
                    warningsSection
                }

                // Map Navigation Card
                mapQuickLinkCard

                // Weather & Pressure Microclimate
                weatherSection

                // Air Quality Card
                airQualitySection

                // BIS State Hazard Baseline
                stateHazardCard

                // USGS Earthquakes
                earthquakesSection
            }
            .padding()
            .padding(.bottom, 100)
        }
        .sheet(isPresented: $showingMapView) {
            DisasterMapView(disasterService: disasterService)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("DISASTER RESILIENCE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(LiquidGlassTheme.amberWarning)
                Spacer()
                Button {
                    Task {
                        await disasterService.refreshAllTelemetry()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Refresh")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LiquidGlassTheme.neonCyan)
                }
            }

            Text("Hazard Radar")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(Color.white)

            Text("Offline India BIS IS 1893:2016 baseline + Live Open-Meteo & USGS feeds.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var warningsSection: some View {
        VStack(spacing: 10) {
            ForEach(disasterService.activeWarnings) { w in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: w.hazardType.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(w.severity == .critical ? LiquidGlassTheme.alertCrimson : LiquidGlassTheme.amberWarning)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(w.headline)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text(w.actionPrompt)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                }
                .padding()
                .liquidGlass(
                    cornerRadius: 18,
                    highlightColor: (w.severity == .critical ? LiquidGlassTheme.alertCrimson : LiquidGlassTheme.amberWarning).opacity(0.6)
                )
            }
        }
    }

    private var mapQuickLinkCard: some View {
        Button {
            showingMapView = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LiquidGlassTheme.neonCyan.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "map.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(LiquidGlassTheme.neonCyan)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Interactive Evacuation Map")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("View safe assembly zones, hospital shelters, and seismic radius.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                Spacer()

                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(LiquidGlassTheme.neonCyan)
            }
            .padding()
            .liquidGlass(highlightColor: LiquidGlassTheme.neonCyan.opacity(0.3))
        }
        .buttonStyle(.plain)
    }

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("METEOROLOGICAL TELEMETRY")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.5))

            HStack(spacing: 12) {
                statTile(title: "Temperature", val: "\(String(format: "%.1f", disasterService.weather.temperatureC))°C", icon: "thermometer.medium")
                statTile(title: "Precipitation", val: "\(Int(disasterService.weather.precipitationProbability))%", icon: "cloud.rain.fill")
                statTile(title: "Wind Speed", val: "\(Int(disasterService.weather.windSpeedKmh)) km/h", icon: "wind")
            }
        }
    }

    private var airQualitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AIR QUALITY & PM PARTICULATES")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.5))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(disasterService.airQuality.usAqi))")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white)
                    Text("US AQI — \(disasterService.airQuality.aqiCategory)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(disasterService.airQuality.usAqi < 100 ? LiquidGlassTheme.emeraldGreen : LiquidGlassTheme.amberWarning)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let pm25 = disasterService.airQuality.pm25 {
                        Text("PM2.5: \(String(format: "%.1f", pm25)) µg/m³")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                    if let pm10 = disasterService.airQuality.pm10 {
                        Text("PM10: \(String(format: "%.1f", pm10)) µg/m³")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                    Text("Open-Meteo Station")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .padding()
            .liquidGlass()
        }
    }

    private var stateHazardCard: some View {
        let profile = IndiaHazardData.hazardProfile(for: disasterService.currentState)
        return VStack(alignment: .leading, spacing: 10) {
            Text("OFFLINE INDIA HAZARD PROFILE")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.5))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(disasterService.currentState)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                    Spacer()
                    Text(profile.seismicZone.rawValue)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LiquidGlassTheme.amberWarning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(LiquidGlassTheme.amberWarning.opacity(0.15)))
                }

                HStack(spacing: 16) {
                    Label("Cyclone Prone", systemImage: profile.cycloneProne ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(profile.cycloneProne ? LiquidGlassTheme.alertCrimson : LiquidGlassTheme.emeraldGreen)
                    Label("Flood Prone", systemImage: profile.floodProne ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(profile.floodProne ? LiquidGlassTheme.alertCrimson : LiquidGlassTheme.emeraldGreen)
                }
            }
            .padding()
            .liquidGlass()
        }
    }

    private var earthquakesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT SEISMIC ACTIVITY (USGS)")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.5))

            if disasterService.recentEarthquakes.isEmpty {
                Text("No earthquakes magnitude ≥ 4.0 detected within 250km in the last 30 days.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass()
            } else {
                ForEach(disasterService.recentEarthquakes) { eq in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("M \(String(format: "%.1f", eq.magnitude)) — \(eq.place)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.white)
                            Text(eq.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                        Spacer()
                    }
                    .padding()
                    .liquidGlass()
                }
            }
        }
    }

    private func statTile(title: String, val: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(LiquidGlassTheme.neonCyan)
            Text(val)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.white)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .liquidGlass()
    }
}
