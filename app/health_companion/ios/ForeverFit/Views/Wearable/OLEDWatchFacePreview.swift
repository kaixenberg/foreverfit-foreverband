import SwiftUI

/// Pixel-perfect simulator of the ESP32 SSD1306 128x64 OLED display.
/// Renders Face 1 (Clock/Vitals) and Face 2 (Sensor Radar) matching health_companion.ino.
public struct OLEDWatchFacePreview: View {
    public let settings: WatchSettings
    public let vitals: VitalsReading?
    public let env: EnvReading?

    public var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // OLED Black Screen Chassis
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.05, green: 0.05, blue: 0.07))
                    .frame(width: 256, height: 128)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1.5)
                    }
                    .shadow(color: Color.black.opacity(0.8), radius: 12, x: 0, y: 6)

                // OLED Pixel Glow
                if settings.selectedFace == .primary {
                    primaryFaceView
                } else {
                    secondaryFaceView
                }
            }

            Text("ESP32-S3 DevKit 128×64 OLED")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }

    // MARK: - Face 1: Classic Vitals Clock

    private var primaryFaceView: some View {
        VStack(spacing: 4) {
            // Time
            Text(formattedTime)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.cyan)
                .shadow(color: Color.cyan.opacity(0.8), radius: 4)

            // Date
            Text(formattedDate)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.cyan.opacity(0.8))

            Divider().background(Color.cyan.opacity(0.3)).frame(width: 200)

            // Vitals Footer
            HStack(spacing: 18) {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red)
                    let hr = vitals?.fingerPresent == true ? "\(Int(vitals!.heartRate))" : "--"
                    Text("\(hr) BPM")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                }

                HStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.cyan)
                    let spo2 = vitals?.fingerPresent == true ? "\(Int(vitals!.spo2))" : "--"
                    Text("\(spo2)%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                }
            }
        }
    }

    // MARK: - Face 2: Sensor Radar Matrix

    private var secondaryFaceView: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("RADAR MATRIX BME280")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(Color.yellow)

            let t = env != nil ? String(format: "%.1f C", env!.ambientTempC) : "27.8 C"
            let h = env != nil ? "\(Int(env!.humidity))%" : "64%"
            let p = env != nil ? "\(Int(env!.pressureHPa)) hPa" : "1012 hPa"

            HStack {
                Text("TEMP: \(t)")
                Spacer()
                Text("HUM: \(h)")
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.cyan)

            Text("PRES: \(p)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.cyan)

            HStack {
                Text("IMU: MPU6050")
                Spacer()
                Text("BLE: 20Hz")
            }
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.6))
        }
        .frame(width: 220, alignment: .leading)
    }

    // MARK: - Formatters

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = settings.use24HourFormat
            ? (settings.showSeconds ? "HH:mm:ss" : "HH:mm")
            : (settings.showSeconds ? "h:mm:ss a" : "h:mm a")
        return formatter.string(from: Date())
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        switch settings.dateFormat {
        case .weekdayShort: formatter.dateFormat = "EEE, MMM d"
        case .weekdayShortWithYear: formatter.dateFormat = "EEE, MMM d yyyy"
        case .dayMonthYearSlash: formatter.dateFormat = "dd/MM/yyyy"
        case .monthDayYearSlash: formatter.dateFormat = "MM/dd/yyyy"
        }
        return formatter.string(from: Date())
    }
}
