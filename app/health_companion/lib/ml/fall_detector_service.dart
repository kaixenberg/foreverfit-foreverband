import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/emergency_workflow_service.dart';
import '../sensors/phone_motion_service.dart';
import 'fall_inference.dart';

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
  FallDetectorService({
    required this.phoneMotionService,
    required this.emergencyWorkflow,
  });

  final PhoneMotionService phoneMotionService;
  final EmergencyWorkflowService emergencyWorkflow;

  static const int _consecutiveTriggersToAlert = 2;
  static const int _emergencyCountdownSeconds = 10;

  final _inference = FallInference();
  Timer? _timer;
  Timer? _countdownTimer;

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
      await _inference.load();
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
    _inference.addSample(MotionSample(
      ax: sample.ax,
      ay: sample.ay,
      az: sample.az,
      gx: sample.gx,
      gy: sample.gy,
      gz: sample.gz,
    ));
  }

  void _runInference() {
    final probability = _inference.runIfReady();
    if (probability == null) return;
    fallProbability = probability;

    final triggeredNow = fallProbability > FallInference.threshold;
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

  /// No response within the countdown — hands off to the real
  /// AI-assisted emergency-call workflow (see ARCHITECTURE.md).
  void _triggerEmergencyCall() {
    isCalling = true;
    secondsUntilCall = null;
    notifyListeners();
    final reason = alertSource == AlertSource.manual
        ? 'the user manually requested emergency assistance'
        : 'a possible fall was detected';
    emergencyWorkflow.start(triggerReason: reason);
  }

  /// A fall was detected while the app was backgrounded — the
  /// background foreground-service task handler already ran its own
  /// 10s "I'm OK" notification window (see
  /// `lib/background/fall_detection_task_handler.dart`) and it went
  /// unanswered, so this skips straight to the emergency workflow
  /// instead of re-running the in-app countdown. Called from
  /// `BackgroundEscalationGate` once the app is brought to the
  /// foreground by the escalation launch.
  void triggerBackgroundEscalatedCall() {
    if (alertActive) return;
    alertActive = true;
    alertSource = AlertSource.fall;
    isCalling = true;
    secondsUntilCall = null;
    notifyListeners();
    emergencyWorkflow.start(
      triggerReason: 'a possible fall was detected while the app was in '
          'the background',
    );
  }

  /// Call when the user acknowledges the alert (e.g. taps "I'm OK") —
  /// cancels any pending countdown/call and fully re-arms detection. Also
  /// requests cancellation of the emergency workflow if it already
  /// started (best-effort — see EmergencyWorkflowService.cancel()).
  void dismissAlert() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    alertActive = false;
    isCalling = false;
    secondsUntilCall = null;
    alertSource = null;
    _consecutiveTriggers = 0;
    emergencyWorkflow.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _countdownTimer?.cancel();
    phoneMotionService.removeListener(_onPhoneUpdate);
    _inference.close();
    super.dispose();
  }
}
