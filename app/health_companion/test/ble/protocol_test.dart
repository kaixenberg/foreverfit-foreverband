import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/ble/protocol.dart';

List<int> _vitalsBytes({
  double hr = 0,
  double spo2 = 0,
  double bodyTemp = 0,
  bool finger = false,
  int? ppgFlags,
}) {
  final data = ByteData(ppgFlags == null ? 17 : 18);
  data.setUint32(0, 1234, Endian.little);
  data.setFloat32(4, hr, Endian.little);
  data.setFloat32(8, spo2, Endian.little);
  data.setFloat32(12, bodyTemp, Endian.little);
  data.setUint8(16, finger ? 1 : 0);
  if (ppgFlags != null) data.setUint8(17, ppgFlags);
  return data.buffer.asUint8List();
}

void main() {
  group('parseVitals', () {
    test('contact but still settling is not a heart-rate reading', () {
      final r = HealthCompanionProtocol.parseVitals(_vitalsBytes(
        finger: true,
        ppgFlags: HealthCompanionProtocol.ppgFlagSettling,
      ))!;
      expect(r.fingerPresent, isTrue);
      expect(r.ppgSettling, isTrue);
      expect(r.hasHeartRate, isFalse);
      expect(r.hasSpo2, isFalse);
    });

    test('HR ready before SpO2 is reported independently', () {
      final r = HealthCompanionProtocol.parseVitals(_vitalsBytes(
        hr: 72,
        finger: true,
        ppgFlags: HealthCompanionProtocol.ppgFlagHrReady,
      ))!;
      expect(r.hasHeartRate, isTrue);
      expect(r.hasSpo2, isFalse);
    });

    test('both ready, with saturation flag', () {
      final r = HealthCompanionProtocol.parseVitals(_vitalsBytes(
        hr: 72,
        spo2: 97,
        finger: true,
        ppgFlags: HealthCompanionProtocol.ppgFlagHrReady |
            HealthCompanionProtocol.ppgFlagSpo2Ready |
            HealthCompanionProtocol.ppgFlagSaturated,
      ))!;
      expect(r.hasHeartRate, isTrue);
      expect(r.hasSpo2, isTrue);
      expect(r.ppgSaturated, isTrue);
    });

    test('ready flags without contact are never a reading', () {
      final r = HealthCompanionProtocol.parseVitals(_vitalsBytes(
        hr: 72,
        spo2: 97,
        ppgFlags: HealthCompanionProtocol.ppgFlagHrReady |
            HealthCompanionProtocol.ppgFlagSpo2Ready,
      ))!;
      expect(r.hasHeartRate, isFalse);
      expect(r.hasSpo2, isFalse);
    });

    test('17-byte packet from older firmware treats contact as ready', () {
      final r = HealthCompanionProtocol.parseVitals(
          _vitalsBytes(hr: 70, spo2: 98, finger: true))!;
      expect(r.hasHeartRate, isTrue);
      expect(r.hasSpo2, isTrue);
    });

    test('short packet is rejected', () {
      expect(HealthCompanionProtocol.parseVitals(List.filled(16, 0)), isNull);
    });
  });
}
