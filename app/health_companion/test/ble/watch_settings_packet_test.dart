import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/ble/protocol.dart';
import 'package:health_companion/models/watch_settings.dart';

void main() {
  group('buildWatchSettingsPacket', () {
    test('body stats demo mode is the 9th byte, off by default', () {
      final bytes = HealthCompanionProtocol.buildWatchSettingsPacket(
          WatchSettings.defaults);
      expect(bytes.length, 9);
      expect(bytes[8], 0);
    });

    test('body stats demo mode on', () {
      final bytes = HealthCompanionProtocol.buildWatchSettingsPacket(
          WatchSettings.defaults.copyWith(bodyStatsDemoMode: true));
      expect(bytes[8], 1);
      // Earlier fields keep their positions for older firmware.
      expect(bytes[7], 0);
    });
  });
}
