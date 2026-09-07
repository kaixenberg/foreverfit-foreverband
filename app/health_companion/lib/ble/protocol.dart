/// BLE protocol constants and wire-format parsing for the Health Companion
/// wearable. This file MUST stay byte-for-byte in sync with the packed
/// structs in firmware/health_companion/src/main.cpp — see ARCHITECTURE.md
/// for the authoritative spec. All multi-byte fields are little-endian,
/// matching the ESP32's native byte order.
library;

import 'dart:typed_data';

import '../models/sensor_reading.dart';

class HealthCompanionProtocol {
  static const String serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String vitalsCharUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String envCharUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
  static const String motionCharUuid = '6e400004-b5a3-f393-e0a9-e50e24dcca9e';
  static const String deviceName = 'HealthCompanion';

  /// VitalsPacket: uint32 tMs; float heartRate; float spo2; float bodyTempC;
  /// uint8 fingerPresent;
  static const int vitalsPacketLength = 17;

  /// EnvPacket: uint32 tMs; float ambientTempC; float humidity; float pressureHPa;
  static const int envPacketLength = 16;

  /// MotionPacket: uint32 tMs; float ax,ay,az; float gx,gy,gz;
  static const int motionPacketLength = 28;

  static VitalsReading? parseVitals(List<int> bytes) {
    if (bytes.length < vitalsPacketLength) return null;
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    return VitalsReading(
      deviceTimeMs: data.getUint32(0, Endian.little),
      receivedAt: DateTime.now(),
      heartRate: data.getFloat32(4, Endian.little),
      spo2: data.getFloat32(8, Endian.little),
      bodyTempC: data.getFloat32(12, Endian.little),
      fingerPresent: data.getUint8(16) != 0,
    );
  }

  static EnvReading? parseEnv(List<int> bytes) {
    if (bytes.length < envPacketLength) return null;
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    return EnvReading(
      deviceTimeMs: data.getUint32(0, Endian.little),
      receivedAt: DateTime.now(),
      ambientTempC: data.getFloat32(4, Endian.little),
      humidity: data.getFloat32(8, Endian.little),
      pressureHPa: data.getFloat32(12, Endian.little),
    );
  }

  static MotionReading? parseMotion(List<int> bytes) {
    if (bytes.length < motionPacketLength) return null;
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    return MotionReading(
      deviceTimeMs: data.getUint32(0, Endian.little),
      receivedAt: DateTime.now(),
      ax: data.getFloat32(4, Endian.little),
      ay: data.getFloat32(8, Endian.little),
      az: data.getFloat32(12, Endian.little),
      gx: data.getFloat32(16, Endian.little),
      gy: data.getFloat32(20, Endian.little),
      gz: data.getFloat32(24, Endian.little),
    );
  }
}
