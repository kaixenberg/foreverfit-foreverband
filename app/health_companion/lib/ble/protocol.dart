/// BLE protocol constants and wire-format parsing for the ForeverBand
/// wearable. This file MUST stay byte-for-byte in sync with the packed
/// structs in firmware/health_companion/health_companion.ino — see
/// ARCHITECTURE.md for the authoritative spec. All multi-byte fields are
/// little-endian, matching the ESP32's native byte order.
library;

import 'dart:typed_data';

import '../models/sensor_reading.dart';
import '../models/watch_settings.dart';

class HealthCompanionProtocol {
  static const String serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String vitalsCharUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String envCharUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
  static const String motionCharUuid = '6e400004-b5a3-f393-e0a9-e50e24dcca9e';
  static const String timeCharUuid = '6e400005-b5a3-f393-e0a9-e50e24dcca9e';
  static const String watchSettingsCharUuid =
      '6e400006-b5a3-f393-e0a9-e50e24dcca9e';
  static const String deviceName = 'ForeverBand';

  /// VitalsPacket: uint32 tMs; float heartRate; float spo2; float bodyTempC;
  /// uint8 fingerPresent; uint8 ppgFlags (see the ppgFlag* bits below).
  /// 17 bytes = firmware from before the MAX30102 PPG pipeline (no flags
  /// byte) — still accepted, treating contact as "ready" the way that
  /// firmware did.
  static const int vitalsPacketLength = 17;
  static const int vitalsPacketLengthWithPpgFlags = 18;

  /// ppgFlags bits — MUST match PPG_FLAG_* in health_companion.ino.
  static const int ppgFlagHrReady = 1 << 0;
  static const int ppgFlagSpo2Ready = 1 << 1;
  static const int ppgFlagSettling = 1 << 2;
  static const int ppgFlagSaturated = 1 << 3;

  /// EnvPacket: uint32 tMs; float ambientTempC; float humidity; float pressureHPa;
  static const int envPacketLength = 16;

  /// MotionPacket: uint32 tMs; float ax,ay,az; float gx,gy,gz;
  static const int motionPacketLength = 28;

  /// TimeSyncPacket (phone -> wearable, WRITE only, no notify/parse side):
  /// uint8 hour(0-23); uint8 minute; uint8 second; uint8 day(1-31);
  /// uint8 month(1-12); uint16 year; uint8 weekday(0=Sunday..6=Saturday).
  /// Lets the OLED show a real clock/date without an RTC or network
  /// access on the ESP32 side — see health_companion.ino's time-sync
  /// handling and the primary watch face.
  static const int timeSyncPacketLength = 8;

  /// WatchSettingsPacket (phone -> wearable, WRITE only, no notify/parse
  /// side): uint8 selectedFace(0=primary,1=secondary); uint8
  /// autoCycleEnabled(0/1); uint16 autoCycleIntervalSec; uint8
  /// use24HourFormat(0/1); uint8 dateFormat (see WatchDateFormat's
  /// index — must stay in the same order there); uint8 showSeconds(0/1);
  /// uint8 ignoreBodyTempContactCheck(0/1) — developer/demo override, see
  /// WatchSettings.ignoreBodyTempContactCheck and health_companion.ino's
  /// WatchSettingsPacket for what it does on the firmware side.
  /// Pushed on connect and again whenever a setting changes while
  /// connected — see BleService.syncWatchSettings().
  static const int watchSettingsPacketLength = 8;

  static List<int> buildWatchSettingsPacket(WatchSettings settings) {
    final data = ByteData(watchSettingsPacketLength);
    data.setUint8(0, settings.selectedFace.index);
    data.setUint8(1, settings.autoCycleEnabled ? 1 : 0);
    data.setUint16(2, settings.autoCycleIntervalSeconds, Endian.little);
    data.setUint8(4, settings.use24HourFormat ? 1 : 0);
    data.setUint8(5, settings.dateFormat.index);
    data.setUint8(6, settings.showSeconds ? 1 : 0);
    data.setUint8(7, settings.ignoreBodyTempContactCheck ? 1 : 0);
    return data.buffer.asUint8List();
  }

  static VitalsReading? parseVitals(List<int> bytes) {
    if (bytes.length < vitalsPacketLength) return null;
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final fingerPresent = data.getUint8(16) != 0;
    final hasFlags = bytes.length >= vitalsPacketLengthWithPpgFlags;
    final flags = hasFlags ? data.getUint8(17) : 0;
    return VitalsReading(
      deviceTimeMs: data.getUint32(0, Endian.little),
      receivedAt: DateTime.now(),
      heartRate: data.getFloat32(4, Endian.little),
      spo2: data.getFloat32(8, Endian.little),
      bodyTempC: data.getFloat32(12, Endian.little),
      fingerPresent: fingerPresent,
      hrReady: hasFlags ? flags & ppgFlagHrReady != 0 : fingerPresent,
      spo2Ready: hasFlags ? flags & ppgFlagSpo2Ready != 0 : fingerPresent,
      ppgSettling: flags & ppgFlagSettling != 0,
      ppgSaturated: flags & ppgFlagSaturated != 0,
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

  /// Builds a TimeSyncPacket for the current local time.
  static List<int> buildTimeSyncPacket(DateTime at) {
    final data = ByteData(timeSyncPacketLength);
    data.setUint8(0, at.hour);
    data.setUint8(1, at.minute);
    data.setUint8(2, at.second);
    data.setUint8(3, at.day);
    data.setUint8(4, at.month);
    data.setUint16(5, at.year, Endian.little);
    // Dart's DateTime.weekday is 1=Monday..7=Sunday (ISO-8601); converted
    // to 0=Sunday..6=Saturday here since that's a simpler array index for
    // a day-name lookup table in C++ than doing the same conversion there.
    data.setUint8(7, at.weekday % 7);
    return data.buffer.asUint8List();
  }
}
