import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_litert/flutter_litert.dart';

import '../sensors/phone_motion_service.dart';

enum AlertSource { fall, manual }

/// Runs the on-device fall-detection CNN on the phone's own motion alone.
///
/// Originally designed to fuse the wearable's wrist motion with the
/// phone's accelerometer (see git history / ARCHITECTURE.md), but the
/// wearable's MPU6050 died on the breadboard build — so this now runs on
/// a model retrained on phone-only data: real UMAFall phone accelerometer
/// + the co-located waist sensor's gyro as a physically-justified proxy
/// for "phone gyro" (UMAFall's own phone has no gyroscope — see
/// ml/prepare_windows_phone_only.py and ml/README.md for why). Both
/// channels are properly trained now, so — unlike the wrist+phone
/// version — there's no separate heuristic corroboration step needed.
///
/// Channel order (must match training exactly):
///   [phone_ax, phone_ay, phone_az, phone_gx, phone_gy, phone_gz]
///
/// Revert to the wrist+phone model + BleService motion fusion once the
/// wearable's IMU is replaced — see git history for that version.
class FallDetectorService extends ChangeNotifier {
  FallDetectorService({required this.phoneMotionService});

  final PhoneMotionService phoneMotionService;

  static const int _windowLen = 60; // 3s @ 20Hz
  static const String _modelAsset =
      'assets/models/fall_detector_phone_only.tflite';

  // Tunable — matches the 0.5 threshold used when evaluating the trained
  // model (ml/train_fall_model_phone_only.py: 99% accuracy, 94% fall
  // recall, 88% fall precision on held-out subjects).
  static const double _cnnThreshold = 0.5;
  static const int _consecutiveTriggersToAlert = 2;
  static const int _emergencyCountdownSeconds = 10;

  Interpreter? _interpreter;
  Timer? _timer;
  Timer? _countdownTimer;

  final List<PhoneMotionSample> _phoneBuffer = [];
  int _consecutiveTriggers = 0;

  double fallProbability = 0.0;
  String? lastError;

  /// True from the moment a fall is detected until the user dismisses it
  /// or the emergency call fires — deliberately NOT tied to the live
  /// cnnProb, which drops back down once the phone stops moving. Without
  /// this latch the banner would auto-dismiss itself a second after
  /// showing, before a real user could react.
  bool alertActive = false;
  bool isCalling = false;
  int? secondsUntilCall;

  /// Which flow raised the current alert — lets the banner distinguish
  /// "you fell" from "you asked for help" without a second state machine.
  AlertSource? alertSource;

  Future<void> start() async {
    try {
      _interpreter = await Interpreter.fromAsset(_modelAsset);
    } catch (e) {
      lastError = 'Failed to load fall-detector model: $e';
      notifyListeners();
      return;
    }

    phoneMotionService.addListener(_onPhoneUpdate);
    _timer = Timer.periodic(
        const Duration(milliseconds: 500), (_) => _runInference());
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
    final output = List.generate(1, (_) => List.filled(1, 0.0));

    interpreter.run(input, output);
    fallProbability = output[0][0];

    final triggeredNow = fallProbability > _cnnThreshold;
    _consecutiveTriggers = triggeredNow ? _consecutiveTriggers + 1 : 0;

    // Only START a new alert from live detection — while one is already
    // active, ignore further triggers so the live signal dropping back
    // down (which happens within ~1s of a real fall settling) can't
    // interfere with the latched alert/countdown already in progress.
    if (!alertActive && _consecutiveTriggers >= _consecutiveTriggersToAlert) {
      _startAlert(AlertSource.fall);
    }

    debugPrint('[FallDetector] cnnProb=${fallProbability.toStringAsFixed(3)} '
        'triggeredNow=$triggeredNow consecutive=$_consecutiveTriggers '
        'alertActive=$alertActive');

    notifyListeners();
  }

  /// Manually raised SOS — same countdown/escalation flow as an
  /// auto-detected fall, minus the CNN. Ignored while an alert (of either
  /// kind) is already active, so it can't stomp on an in-progress one.
  void triggerManualSOS() {
    if (alertActive) return;
    _startAlert(AlertSource.manual);
  }

  void _startAlert(AlertSource source) {
    alertActive = true;
    alertSource = source;
    isCalling = false;
    secondsUntilCall = _emergencyCountdownSeconds;

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      secondsUntilCall = (secondsUntilCall ?? 1) - 1;
      if (secondsUntilCall! <= 0) {
        timer.cancel();
        _triggerEmergencyCall();
      }
      notifyListeners();
    });
  }

  /// Placeholder for the real SOS flow (see ARCHITECTURE.md roadmap) — a
  /// dummy action only, no real call is placed.
  void _triggerEmergencyCall() {
    isCalling = true;
    secondsUntilCall = null;
    debugPrint('[FallDetector] EMERGENCY: no response within '
        '${_emergencyCountdownSeconds}s — dummy call to emergency contact '
        'would fire here.');
    notifyListeners();
  }

  /// Call when the user acknowledges the alert (e.g. taps "I'm OK") —
  /// cancels any pending countdown/call and fully re-arms detection.
  void dismissAlert() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    alertActive = false;
    isCalling = false;
    secondsUntilCall = null;
    alertSource = null;
    _consecutiveTriggers = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _countdownTimer?.cancel();
    phoneMotionService.removeListener(_onPhoneUpdate);
    _interpreter?.close();
    super.dispose();
  }
}
