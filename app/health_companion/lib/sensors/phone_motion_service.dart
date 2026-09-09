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
  DateTime? _lastEmit;

  PhoneMotionSample? latest;
  String? lastError;

  void start() {
    _accelSub =
        accelerometerEventStream(samplingPeriod: _samplingPeriod).listen(
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
    // `samplingPeriod` above is only a hint to the OS, not a guarantee —
    // confirmed on real hardware (a HyperOS/MIUI phone) delivering
    // accelerometer/gyroscope events well above the requested ~20Hz.
    // Without this throttle, two independently-firing streams meant
    // notifyListeners() ran far more than 20 times/sec (real evidence:
    // ActivityClassifierService's own windowSpanMs debug log showed a
    // 60-sample window spanning ~400ms of wall-clock time, not the
    // expected ~3000ms) — wasted CPU competing with frame rendering on
    // every single tick, on top of quietly shrinking FallDetectorService/
    // ActivityClassifierService's windows to a fraction of the real-world
    // time span their models were actually trained on.
    final now = DateTime.now();
    if (_lastEmit != null && now.difference(_lastEmit!) < _samplingPeriod) {
      return;
    }
    _lastEmit = now;
    latest = PhoneMotionSample(
      timestamp: now,
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
