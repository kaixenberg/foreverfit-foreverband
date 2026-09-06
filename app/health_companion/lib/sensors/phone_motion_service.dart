import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// One phone motion sample: raw accelerometer (gravity included, matching
/// the UMAFall training data's raw hardware accelerometer convention — not
/// gravity-filtered) and gyroscope, both in the units Android/iOS report
/// natively (m/s^2, rad/s) — the same units Adafruit_MPU6050 reports on the
/// wearable, so no conversion is needed on either side.
class PhoneMotionSample {
  final DateTime timestamp;
  final double ax, ay, az;
  final double gx, gy, gz;

  PhoneMotionSample({
    required this.timestamp,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });
}

/// Reads the phone's own accelerometer + gyroscope at ~20Hz — the same
/// nominal rate as the wearable's BLE motion notifications — so downstream
/// consumers can fuse the two streams without runtime resampling.
class PhoneMotionService extends ChangeNotifier {
  static const _samplingPeriod = Duration(milliseconds: 50); // ~20Hz

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  double _ax = 0, _ay = 0, _az = 0;
  double _gx = 0, _gy = 0, _gz = 0;
  bool _hasAccel = false, _hasGyro = false;

  PhoneMotionSample? latest;
  String? lastError;

  void start() {
    _accelSub = accelerometerEventStream(samplingPeriod: _samplingPeriod).listen(
      (event) {
        _ax = event.x;
        _ay = event.y;
        _az = event.z;
        _hasAccel = true;
        _emitIfReady();
      },
      onError: (e) => lastError = 'Accelerometer unavailable: $e',
    );

    _gyroSub = gyroscopeEventStream(samplingPeriod: _samplingPeriod).listen(
      (event) {
        _gx = event.x;
        _gy = event.y;
        _gz = event.z;
        _hasGyro = true;
        _emitIfReady();
      },
      onError: (e) => lastError = 'Gyroscope unavailable: $e',
    );
  }

  void _emitIfReady() {
    if (!_hasAccel || !_hasGyro) return;
    latest = PhoneMotionSample(
      timestamp: DateTime.now(),
      ax: _ax,
      ay: _ay,
      az: _az,
      gx: _gx,
      gy: _gy,
      gz: _gz,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    super.dispose();
  }
}
