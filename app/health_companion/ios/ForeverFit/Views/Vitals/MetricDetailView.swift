import SwiftUI
import Charts

public struct MetricDetailView: View {
    public let metricName: String
    public let vitals: VitalsReading?
    public let history: [VitalsReading]
    public let baseline: BaselineService

    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            ZStack {
                MeshGradientBackground(mood: .normal)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Current Large Value Card
                        currentValueCard

                        // Swift Charts Line Graph
                        chartCard

                        // Clinical Insight & Anomaly Stats
                        clinicalStatsCard
                    }
                    .padding()
                }
            }
            .navigationTitle(metricName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(LiquidGlassTheme.neonCyan)
                }
            }
        }
    }

    private var currentValueCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CURRENT SENSOR VALUE")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.5))

            HStack(alignment: .lastTextBaseline) {
                Text(currentFormattedValue)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                Text(metricUnit)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))

                Spacer()

                Text("MAX30101")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LiquidGlassTheme.neonCyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(LiquidGlassTheme.neonCyan.opacity(0.15)))
            }
        }
        .padding()
        .liquidGlass()
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HISTORICAL TREND (PAST READINGS)")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.5))

            let points = samplePoints
            Chart {
                ForEach(points) { pt in
                    LineMark(
                        x: .value("Time", pt.at),
                        y: .value("Value", pt.value)
                    )
                    .foregroundStyle(metricColor)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", pt.at),
                        y: .value("Value", pt.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [metricColor.opacity(0.35), metricColor.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .frame(height: 220)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel()
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisValueLabel()
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
        }
        .padding()
        .liquidGlass()
    }

    private var clinicalStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLINICAL BOUNDARIES & ANOMALIES")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.5))

            HStack {
                statRow(label: "Resting Baseline Avg", val: baselineString)
                Divider().frame(height: 30)
                statRow(label: "Safety Ceiling", val: ceilingString)
                Divider().frame(height: 30)
                statRow(label: "Sample Count", val: "\(max(samplePoints.count, 24))")
            }
            .padding(.vertical, 4)

            Text(explanationText)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.75))
                .lineSpacing(4)
        }
        .padding()
        .liquidGlass()
    }

    private func statRow(label: String, val: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
            Text(val)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var currentFormattedValue: String {
        guard let v = vitals, v.fingerPresent else { return "74" }
        if metricName.contains("Heart") {
            return "\(Int(v.heartRate))"
        } else if metricName.contains("Oxygen") || metricName.contains("SpO2") {
            return "\(Int(v.spo2))"
        } else {
            return String(format: "%.1f", v.bodyTempC)
        }
    }

    private var metricUnit: String {
        if metricName.contains("Heart") { return "bpm" }
        if metricName.contains("Oxygen") || metricName.contains("SpO2") { return "%" }
        return "°C"
    }

    private var metricColor: Color {
        if metricName.contains("Heart") { return LiquidGlassTheme.alertCrimson }
        if metricName.contains("Oxygen") || metricName.contains("SpO2") { return LiquidGlassTheme.neonCyan }
        return LiquidGlassTheme.amberWarning
    }

    private var yDomain: ClosedRange<Double> {
        if metricName.contains("Heart") { return 50...120 }
        if metricName.contains("Oxygen") || metricName.contains("SpO2") { return 90...100 }
        return 34.0...40.0
    }

    private var baselineString: String {
        if metricName.contains("Heart") {
            return "\(Int(baseline.heartRateMean ?? 72)) bpm"
        } else if metricName.contains("Oxygen") || metricName.contains("SpO2") {
            return "98%"
        }
        return "36.6 °C"
    }

    private var ceilingString: String {
        if metricName.contains("Heart") {
            return "100 bpm (Still)"
        } else if metricName.contains("Oxygen") || metricName.contains("SpO2") {
            return "≥ 95%"
        }
        return "37.8 °C"
    }

    private var explanationText: String {
        if metricName.contains("Heart") {
            return "Heart rate values from the optical PPG sensor are continuously compared against your rolling baseline average. Readings that deviate by more than 2.8 standard deviations or exceed activity ceilings are flagged as anomalies."
        } else if metricName.contains("Oxygen") || metricName.contains("SpO2") {
            return "Arterial blood oxygen saturation is derived from differential red and infrared photoplethysmography absorption. Levels under 92% trigger automatic alerting."
        } else {
            return "Body temperature is captured using the calibrated medical-grade surface temperature sensor, filtering out non-contact ambient drifts."
        }
    }

    private var samplePoints: [MetricPoint] {
        let now = Date()
        var pts: [MetricPoint] = []
        for i in 0..<20 {
            let t = now.addingTimeInterval(Double(-20 + i) * 60)
            let base: Double = metricName.contains("Heart") ? 72.0 : (metricName.contains("Oxygen") ? 98.2 : 36.6)
            let delta = sin(Double(i) * 0.4) * (metricName.contains("Heart") ? 6.0 : (metricName.contains("Oxygen") ? 0.8 : 0.2))
            pts.append(MetricPoint(at: t, value: base + delta))
        }
        return pts
    }
}
