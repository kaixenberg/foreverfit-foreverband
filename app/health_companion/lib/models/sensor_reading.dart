/// Parsed sensor readings from the wearable. Field names/order mirror the
/// firmware structs in firmware/health_companion/health_companion.ino.
library;

class VitalsReading {
  final int deviceTimeMs;
  final DateTime receivedAt;
  final double heartRate;
  final double spo2;
  final double bodyTempC;

  /// False when the MAX30102 doesn't detect finger/wrist contact — the
  /// firmware zeroes heartRate/spo2 in that state, so this flag is what
  /// tells "no reading" apart from "a reading of 0" (which would
  /// otherwise look like a false medical warning in the app). Contact
  /// alone is NOT a heart-rate reading — see [hrReady]/[spo2Ready].
  final bool fingerPresent;

  /// The firmware's PPG pipeline only reports HR/SpO2 after ~2 s of
  /// settling plus 4 good beats (and drops back to "measuring" if beats
  /// stop, e.g. wrist motion) — see ppgFlags in health_companion.ino.
  /// Until then heartRate/spo2 are 0 even though [fingerPresent] is true.
  final bool hrReady;
  final bool spo2Ready;

  /// Contact just detected; the signal baseline is still settling.
  final bool ppgSettling;

  /// The sensor's LEDs are saturating (too bright for this fit/skin).
  final bool ppgSaturated;

  VitalsReading({
    required this.deviceTimeMs,
    required this.receivedAt,
    required this.heartRate,
    required this.spo2,
    required this.bodyTempC,
    required this.fingerPresent,
    required this.hrReady,
    required this.spo2Ready,
    this.ppgSettling = false,
    this.ppgSaturated = false,
  });

  /// A heart-rate value that's safe to display, store, and warn on.
  bool get hasHeartRate => fingerPresent && hrReady && heartRate > 0;

  /// An SpO2 value that's safe to display, store, and warn on.
  bool get hasSpo2 => fingerPresent && spo2Ready && spo2 > 0;

  Map<String, dynamic> toMap() => {
        'deviceTimeMs': deviceTimeMs,
        'receivedAt': receivedAt.toIso8601String(),
        'heartRate': heartRate,
        'spo2': spo2,
        'bodyTempC': bodyTempC,
        'fingerPresent': fingerPresent,
      };
}

class EnvReading {
  final int deviceTimeMs;
  final DateTime receivedAt;
  final double ambientTempC;
  final double humidity;
  final double pressureHPa;

  EnvReading({
    required this.deviceTimeMs,
    required this.receivedAt,
    required this.ambientTempC,
    required this.humidity,
    required this.pressureHPa,
  });

  Map<String, dynamic> toMap() => {
        'deviceTimeMs': deviceTimeMs,
        'receivedAt': receivedAt.toIso8601String(),
        'ambientTempC': ambientTempC,
        'humidity': humidity,
        'pressureHPa': pressureHPa,
      };
}

class MotionReading {
  final int deviceTimeMs;
  final DateTime receivedAt;
  final double ax, ay, az;
  final double gx, gy, gz;

  MotionReading({
    required this.deviceTimeMs,
    required this.receivedAt,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });
}
