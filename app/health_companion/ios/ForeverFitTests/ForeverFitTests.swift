import XCTest
@testable import ForeverFit

@MainActor
final class ForeverFitTests: XCTestCase {

    func testVitalsPacketParsing() throws {
        // Construct 17-byte test payload matching health_companion.ino
        var data = Data(count: 17)
        let tMs: UInt32 = 12500
        let hr: Float = 76.5
        let spo2: Float = 98.2
        let temp: Float = 36.7
        let finger: UInt8 = 1

        withUnsafeBytes(of: tMs.littleEndian) { data.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: hr.bitPattern.littleEndian) { data.replaceSubrange(4..<8, with: $0) }
        withUnsafeBytes(of: spo2.bitPattern.littleEndian) { data.replaceSubrange(8..<12, with: $0) }
        withUnsafeBytes(of: temp.bitPattern.littleEndian) { data.replaceSubrange(12..<16, with: $0) }
        data[16] = finger

        guard let vitals = ForeverBandProtocol.parseVitals(data: data) else {
            XCTFail("Failed to parse valid 17-byte vitals payload")
            return
        }

        XCTAssertEqual(vitals.deviceTimeMs, 12500)
        XCTAssertEqual(vitals.heartRate, 76.5, accuracy: 0.01)
        XCTAssertEqual(vitals.spo2, 98.2, accuracy: 0.01)
        XCTAssertEqual(vitals.bodyTempC, 36.7, accuracy: 0.01)
        XCTAssertTrue(vitals.fingerPresent)
    }

    func testEnvPacketParsing() throws {
        var data = Data(count: 16)
        let tMs: UInt32 = 5000
        let temp: Float = 28.4
        let hum: Float = 62.0
        let pres: Float = 1013.2

        withUnsafeBytes(of: tMs.littleEndian) { data.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: temp.bitPattern.littleEndian) { data.replaceSubrange(4..<8, with: $0) }
        withUnsafeBytes(of: hum.bitPattern.littleEndian) { data.replaceSubrange(8..<12, with: $0) }
        withUnsafeBytes(of: pres.bitPattern.littleEndian) { data.replaceSubrange(12..<16, with: $0) }

        guard let env = ForeverBandProtocol.parseEnv(data: data) else {
            XCTFail("Failed to parse valid 16-byte env payload")
            return
        }

        XCTAssertEqual(env.ambientTempC, 28.4, accuracy: 0.01)
        XCTAssertEqual(env.humidity, 62.0, accuracy: 0.01)
        XCTAssertEqual(env.pressureHPa, 1013.2, accuracy: 0.1)
    }

    func testTimeSyncPacketBuilding() throws {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 9
        comps.day = 10
        comps.hour = 14
        comps.minute = 30
        comps.second = 15
        comps.weekday = 5 // Thursday
        let date = calendar.date(from: comps)!

        let packet = ForeverBandProtocol.buildTimeSyncPacket(date: date)
        XCTAssertEqual(packet.count, 8)
        XCTAssertEqual(packet[0], 14) // hour
        XCTAssertEqual(packet[1], 30) // min
        XCTAssertEqual(packet[2], 15) // sec
        XCTAssertEqual(packet[3], 10) // day
        XCTAssertEqual(packet[4], 9)  // month
    }

    func testWatchSettingsPacketBuilding() throws {
        let settings = WatchSettings(
            selectedFace: .secondary,
            autoCycleEnabled: true,
            autoCycleIntervalSeconds: 15,
            use24HourFormat: false,
            dateFormat: .monthDayYearSlash,
            showSeconds: true
        )

        let packet = ForeverBandProtocol.buildWatchSettingsPacket(settings: settings)
        XCTAssertEqual(packet.count, 7)
        XCTAssertEqual(packet[0], 1) // secondary face
        XCTAssertEqual(packet[1], 1) // autoCycle true
        XCTAssertEqual(packet[4], 0) // 12h format
        XCTAssertEqual(packet[5], 3) // monthDayYearSlash
        XCTAssertEqual(packet[6], 1) // showSeconds true
    }

    func testWellnessScoreCalculation() throws {
        // Perfect condition
        let perfect = HealthThresholds.computeWellnessScore(
            hasVitals: true,
            heartRateWarn: false,
            spo2Warn: false,
            bodyTempWarn: false,
            ambientWarn: false,
            heatStressWarn: false
        )
        XCTAssertEqual(perfect, 100)

        // Tachycardia (-25) + Hypoxia (-30)
        let critical = HealthThresholds.computeWellnessScore(
            hasVitals: true,
            heartRateWarn: true,
            spo2Warn: true,
            bodyTempWarn: false,
            ambientWarn: false,
            heatStressWarn: false
        )
        XCTAssertEqual(critical, 45)
    }

    func testIndiaHazardBaseline() throws {
        let delhiProfile = IndiaHazardData.hazardProfile(for: "National Capital Territory of Delhi")
        XCTAssertEqual(delhiProfile.seismicZone, .iv)

        let gujaratProfile = IndiaHazardData.hazardProfile(for: "State of Gujarat")
        XCTAssertEqual(gujaratProfile.seismicZone, .v)
        XCTAssertTrue(gujaratProfile.cycloneProne)
    }

    func testEmergencySummaryScript() throws {
        let summary = EmergencySummary(
            readings: [
                EmergencyReading(label: "heart rate", valueText: "145 beats per minute"),
                EmergencyReading(label: "oxygen saturation", valueText: "88 percent")
            ],
            durationText: "approximately 4 minutes",
            location: EmergencyLocation(text: "New Delhi Central (28.61, 77.20)"),
            triggerReason: "a possible fall was detected"
        )

        let script = EmergencySummaryBuilder.buildEmergencyServicesScript(summary: summary)
        XCTAssertTrue(script.contains("145 beats per minute"))
        XCTAssertTrue(script.contains("88 percent"))
        XCTAssertTrue(script.contains("New Delhi Central"))
    }
}
