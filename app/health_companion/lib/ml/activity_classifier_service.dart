import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_litert/flutter_litert.dart';

import '../sensors/phone_motion_service.dart';

/// Activities the classifier distinguishes — "still" covers both sitting
/// and standing (the distinction doesn't matter for HR-threshold gating,
/// see ARCHITECTURE.md's AI/ML roadmap item 1).
enum Activity { still, walking, running }

/// Runs an on-device 1D-CNN over the phone's own motion to classify
/// still/walking/running — same windowing infrastructure and channel
/// convention as FallDetectorService (60 samples @ 20Hz, raw
/// gravity-included accel + gyro in m/s^2 / rad/s), trained on the
/// MotionSense dataset (see ml/README.md). Purpose: let vitals anomaly
/// checks know "elevated HR while running is normal, elevated HR while
/// sitting still isn't" instead of using one fixed threshold regardless
/// of what the user is doing.
class ActivityClassifierService extends ChangeNotifier {
  ActivityClassifierService({required this.phoneMotionService});

  final PhoneMotionService phoneMotionService;

  static const int _windowLen = 60; // 3s @ 20Hz — matches training
  static const String _modelAsset = 'assets/models/activity_classifier.tflite';
  static const _classes = [Activity.still, Activity.walking, Activity.running];

  Interpreter? _interpreter;
  Timer? _timer;

  final List<PhoneMotionSample> _phoneBuffer = [];

  Activity? current;
  double confidence = 0.0;
  String? lastError;

  Future<void> start() async {
    try {
      _interpreter = await Interpreter.fromAsset(_modelAsset);
    } catch (e) {
      lastError = 'Failed to load activity-classifier model: $e';
      notifyListeners();
      return;
    }

    phoneMotionService.addListener(_onPhoneUpdate);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _runInference());
  }

  void _onPhoneUpdate() {
    final sample = phoneMotionService.latest;
    if (sample == null) return;
    _phoneBuffer.add(sample);
    if (_phoneBuffer.length > _windowLen) _phoneBuffer.removeAt(0);
  }

  void _runInference() {
    final interpreter = _interpreter;
    if (interpreter == null) return;
    if (_phoneBuffer.length < _windowLen) return;

    final input = [
      List.generate(_windowLen, (i) {
        final p = _phoneBuffer[i];
        return [p.ax, p.ay, p.az, p.gx, p.gy, p.gz];
      })
    ];
    final output = List.generate(1, (_) => List.filled(_classes.length, 0.0));

    interpreter.run(input, output);
    final probs = output[0];

    var bestIdx = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[bestIdx]) bestIdx = i;
    }
    current = _classes[bestIdx];
    confidence = probs[bestIdx];

    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    phoneMotionService.removeListener(_onPhoneUpdate);
    _interpreter?.close();
    super.dispose();
  }
}
