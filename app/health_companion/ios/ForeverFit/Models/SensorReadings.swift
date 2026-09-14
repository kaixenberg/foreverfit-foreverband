import Foundation

/// VitalsReading received over BLE from the ESP32 MAX30101 & MAX30205 sensors.
/// Matches health_companion.ino VitalsPacket (17 bytes)
public struct VitalsReading: Identifiable, Codable {
    public var id: UUID = UUID()
    public let deviceTimeMs: UInt32
    public let receivedAt: Date
    public let heartRate: Float
    public let spo2: Float
    public let bodyTempC: Float
    public let fingerPresent: Bool

    public init(
        id: UUID = UUID(),
        deviceTimeMs: UInt32,
        receivedAt: Date = Date(),
        heartRate: Float,
        spo2: Float,
        bodyTempC: Float,
        fingerPresent: Bool
    ) {
        self.id = id
        self.deviceTimeMs = deviceTimeMs
        self.receivedAt = receivedAt
        self.heartRate = heartRate
        self.spo2 = spo2
        self.bodyTempC = bodyTempC
        self.fingerPresent = fingerPresent
    }
}

/// EnvReading received over BLE from the BME280 sensor.
/// Matches health_companion.ino EnvPacket (16 bytes)
public struct EnvReading: Identifiable, Codable {
    public var id: UUID = UUID()
    public let deviceTimeMs: UInt32
    public let receivedAt: Date
    public let ambientTempC: Float
    public let humidity: Float
    public let pressureHPa: Float

    public init(
        id: UUID = UUID(),
        deviceTimeMs: UInt32,
        receivedAt: Date = Date(),
        ambientTempC: Float,
        humidity: Float,
        pressureHPa: Float
    ) {
        self.id = id
        self.deviceTimeMs = deviceTimeMs
        self.receivedAt = receivedAt
        self.ambientTempC = ambientTempC
        self.humidity = humidity
        self.pressureHPa = pressureHPa
    }
}

/// MotionReading received over BLE from the MPU6050 wearable IMU.
/// Matches health_companion.ino MotionPacket (28 bytes)
public struct MotionReading: Identifiable, Codable {
    public var id: UUID = UUID()
    public let deviceTimeMs: UInt32
    public let receivedAt: Date
    public let ax: Float
    public let ay: Float
    public let az: Float
    public let gx: Float
    public let gy: Float
    public let gz: Float

    public init(
        id: UUID = UUID(),
        deviceTimeMs: UInt32,
        receivedAt: Date = Date(),
        ax: Float, ay: Float, az: Float,
        gx: Float, gy: Float, gz: Float
    ) {
        self.id = id
        self.deviceTimeMs = deviceTimeMs
        self.receivedAt = receivedAt
        self.ax = ax
        self.ay = ay
        self.az = az
        self.gx = gx
        self.gy = gy
        self.gz = gz
    }
}
