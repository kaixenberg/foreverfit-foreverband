import 'package:flutter/services.dart';

/// Wraps the native `battery_optimization` channel (MainActivity.kt) —
/// lets Settings show whether background vitals/fall-detection
/// monitoring is currently exempt from Android's Doze battery
/// restrictions, and offer the system prompt to grant that exemption.
class BatteryOptimizationService {
  static const _channel =
      MethodChannel('com.example.health_companion/battery_optimization');

  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _channel
              .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
  }
}
