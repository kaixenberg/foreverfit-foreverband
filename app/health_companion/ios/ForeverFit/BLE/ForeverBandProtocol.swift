import Foundation

/// ForeverBand BLE Protocol Spec
/// Byte-for-byte in sync with health_companion.ino and Flutter protocol.dart.
/// ESP32 native byte order is Little Endian.
public struct ForeverBandProtocol {
    public static let serviceUUID           = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let vitalsCharUUID        = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let envCharUUID           = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let motionCharUUID        = "6E400004-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let timeCharUUID          = "6E400005-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let watchSettingsCharUUID = "6E400006-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let deviceName            = "ForeverBand"

    public static let vitalsPacketLength                 = 17
    public static let vitalsPacketLengthWithPpgFlags     = 18
    public static let envPacketLength                    = 16
    public static let motionPacketLength                 = 28
    public static let timeSyncPacketLength               = 8
    public static let watchSettingsPacketLength          = 8

    /// ppgFlags bits — MUST match PPG_FLAG_* in health_companion.ino.
    public static let ppgFlagHrReady: UInt8   = 1 << 0 // 0x01
    public static let ppgFlagSpo2Ready: UInt8 = 1 << 1 // 0x02
    public static let ppgFlagSettling: UInt8  = 1 << 2 // 0x04
    public static let ppgFlagSaturated: UInt8 = 1 << 3 // 0x08

    // MARK: - Parsing

    /// VitalsPacket: uint32 tMs; float heartRate; float spo2; float bodyTempC; uint8 fingerPresent; [uint8 ppgFlags]
    public static func parseVitals(data: Data) -> VitalsReading? {
        guard data.count >= vitalsPacketLength else { return nil }

        let tMs = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        let hr = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Float.self) }
        let spo2 = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: Float.self) }
        let temp = data.withUnsafeBytes { $0.load(fromByteOffset: 12, as: Float.self) }
        let finger = data[16] != 0

        let hasFlags = data.count >= vitalsPacketLengthWithPpgFlags
        let flags: UInt8 = hasFlags ? data[17] : 0

        let hrReady = hasFlags ? ((flags & ppgFlagHrReady) != 0) : finger
        let spo2Ready = hasFlags ? ((flags & ppgFlagSpo2Ready) != 0) : finger
        let ppgSettling = hasFlags ? ((flags & ppgFlagSettling) != 0) : false
        let ppgSaturated = hasFlags ? ((flags & ppgFlagSaturated) != 0) : false

        return VitalsReading(
            deviceTimeMs: UInt32(littleEndian: tMs),
            receivedAt: Date(),
            heartRate: Float(bitPattern: UInt32(littleEndian: hr.bitPattern)),
            spo2: Float(bitPattern: UInt32(littleEndian: spo2.bitPattern)),
            bodyTempC: Float(bitPattern: UInt32(littleEndian: temp.bitPattern)),
            fingerPresent: finger,
            hrReady: hrReady,
            spo2Ready: spo2Ready,
            ppgSettling: ppgSettling,
            ppgSaturated: ppgSaturated
        )
    }

    /// EnvPacket: uint32 tMs; float ambientTempC; float humidity; float pressureHPa;
    public static func parseEnv(data: Data) -> EnvReading? {
        guard data.count >= envPacketLength else { return nil }

        let tMs = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        let temp = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Float.self) }
        let hum = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: Float.self) }
        let pres = data.withUnsafeBytes { $0.load(fromByteOffset: 12, as: Float.self) }

        return EnvReading(
            deviceTimeMs: UInt32(littleEndian: tMs),
            receivedAt: Date(),
            ambientTempC: Float(bitPattern: UInt32(littleEndian: temp.bitPattern)),
            humidity: Float(bitPattern: UInt32(littleEndian: hum.bitPattern)),
            pressureHPa: Float(bitPattern: UInt32(littleEndian: pres.bitPattern))
        )
    }

    /// MotionPacket: uint32 tMs; float ax,ay,az; float gx,gy,gz;
    public static func parseMotion(data: Data) -> MotionReading? {
        guard data.count >= motionPacketLength else { return nil }

        let tMs = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        let ax = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Float.self) }
        let ay = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: Float.self) }
        let az = data.withUnsafeBytes { $0.load(fromByteOffset: 12, as: Float.self) }
        let gx = data.withUnsafeBytes { $0.load(fromByteOffset: 16, as: Float.self) }
        let gy = data.withUnsafeBytes { $0.load(fromByteOffset: 20, as: Float.self) }
        let gz = data.withUnsafeBytes { $0.load(fromByteOffset: 24, as: Float.self) }

        return MotionReading(
            deviceTimeMs: UInt32(littleEndian: tMs),
            receivedAt: Date(),
            ax: Float(bitPattern: UInt32(littleEndian: ax.bitPattern)),
            ay: Float(bitPattern: UInt32(littleEndian: ay.bitPattern)),
            az: Float(bitPattern: UInt32(littleEndian: az.bitPattern)),
            gx: Float(bitPattern: UInt32(littleEndian: gx.bitPattern)),
            gy: Float(bitPattern: UInt32(littleEndian: gy.bitPattern)),
            gz: Float(bitPattern: UInt32(littleEndian: gz.bitPattern))
        )
    }

    // MARK: - Building Write Packets

    /// Builds TimeSyncPacket (8 bytes, Little Endian):
    /// uint8 hour; uint8 minute; uint8 second; uint8 day; uint8 month; uint16 year; uint8 weekday (0=Sun..6=Sat)
    public static func buildTimeSyncPacket(date: Date = Date()) -> Data {
        var data = Data(count: timeSyncPacketLength)
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.hour, .minute, .second, .day, .month, .year, .weekday], from: date)

        data[0] = UInt8(comps.hour ?? 0)
        data[1] = UInt8(comps.minute ?? 0)
        data[2] = UInt8(comps.second ?? 0)
        data[3] = UInt8(comps.day ?? 1)
        data[4] = UInt8(comps.month ?? 1)

        let yearLE = UInt16(comps.year ?? 2026).littleEndian
        withUnsafeBytes(of: yearLE) { bytes in
            data[5] = bytes[0]
            data[6] = bytes[1]
        }

        // Apple Calendar weekday: 1 = Sunday, 7 = Saturday -> map to 0..6
        let rawWeekday = comps.weekday ?? 1
        data[7] = UInt8((rawWeekday - 1) % 7)

        return data
    }

    /// Builds WatchSettingsPacket (8 bytes, Little Endian):
    /// uint8 selectedFace; uint8 autoCycle; uint16 autoCycleIntervalSec; uint8 use24h; uint8 dateFormat; uint8 showSeconds; uint8 ignoreBodyTempContactCheck
    public static func buildWatchSettingsPacket(settings: WatchSettings) -> Data {
        var data = Data(count: watchSettingsPacketLength)
        data[0] = settings.selectedFace.rawValue
        data[1] = settings.autoCycleEnabled ? 1 : 0

        let intervalLE = settings.autoCycleIntervalSeconds.littleEndian
        withUnsafeBytes(of: intervalLE) { bytes in
            data[2] = bytes[0]
            data[3] = bytes[1]
        }

        data[4] = settings.use24HourFormat ? 1 : 0
        data[5] = settings.dateFormat.rawValue
        data[6] = settings.showSeconds ? 1 : 0
        data[7] = settings.ignoreBodyTempContactCheck ? 1 : 0

        return data
    }
}
