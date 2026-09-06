/// Parsed sensor readings from the wearable. Field names/order mirror the
/// firmware structs in firmware/health_companion/src/main.cpp.
library;

class VitalsReading {
  final int deviceTimeMs;
  final DateTime receivedAt;
  final double heartRate;
  final double spo2;
  final double bodyTempC;

  VitalsReading({
    required this.deviceTimeMs,
    required this.receivedAt,
    required this.heartRate,
    required this.spo2,
    required this.bodyTempC,
  });

  Map<String, dynamic> toMap() => {
        'deviceTimeMs': deviceTimeMs,
        'receivedAt': receivedAt.toIso8601String(),
        'heartRate': heartRate,
        'spo2': spo2,
        'bodyTempC': bodyTempC,
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
