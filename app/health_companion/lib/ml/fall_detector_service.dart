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
/// version — no heuristic corroboration was needed at first. One was
/// reintroduced later once real on-device testing found specific
/// motions the CNN alone confidently misclassifies — see
/// `_consecutiveTriggersToAlert`'s comment below for the full history.
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

  // Was briefly raised to 3 alongside FallInference's threshold bump
  // (0.5 -> 0.8) to dial down false positives, but reverted back to 2 —
  // unlike the threshold change, requiring 3 consecutive high-confidence
  // windows was never validated against real held-out fall data (only
  // per-window precision/recall was measured, not the compounded
  // "N-in-a-row" alert-level requirement), and stacking it on top of the
  // already-stricter threshold made real falls harder to trigger, not
  // just false positives — confirmed by live on-device testing. See
  // fall_inference.dart / ml/README.md's "Threshold tuning" for the part
  // of this that IS backed by real data.
  static const int _consecutiveTriggersToAlert = 2;
  static const int _emergencyCountdownSeconds = 10;

  // Real on-device evidence (a pulled logcat, not a guess) showed the
  // CNN alone confidently — 0.999-1.000, sustained across the model's
  // entire ~3s sliding window — misclassifies two specific motions as
  // falls: picking the phone up quickly, and short (~1ft) falls. Neither
  // is fixable with `threshold` or `_consecutiveTriggersToAlert` above:
  // the confidence isn't borderline, and a brief jerk stays visible to
  // every window it's inside for the full ~3s it takes to slide back
  // out, so it satisfies "N consecutive" the same way a longer real fall
  // does.
  //
  // The first corroboration attempt used free-fall *duration*
  // (`FallInference.longestFreefallRun()`), reasoned from t = sqrt(2h/g):
  // 300ms from an assumed ~1ft fall, then raised to 700ms after a real
  // logcat from deliberate quick/jerky phone handling (no fall at all)
  // showed freefallMs values up to 550ms — a sharp deceleration right
  // after grabbing the phone can momentarily cancel gravity almost the
  // same way true unsupported falling does. But a SECOND round of real
  // testing at 700ms produced a worse problem: genuine confident fall
  // triggers (cnnProb sustained at 0.999-1.000 for a full ~3s window —
  // clearly real drop tests, not handling noise) measured only **~50ms**
  // of free-fall, nowhere near 700ms, while the handling jerks separately
  // measured up to 550ms. Duration is *inverted* for short falls on this
  // device/sampling rate — real short drops read shorter than false-
  // positive handling jerks — so no duration threshold can separate the
  // two; it's not a mistuning, it's the wrong signal for this case.
  //
  // Replaced with impact-based corroboration:
  // `FallInference.hasPostFreefallImpact()` gates on a hard deceleration
  // spike shortly *after* the free-fall dip — a real fall ends by
  // hitting the ground; a pickup ends by decelerating gently into a
  // hand. Reasoned to not be backwards the way duration was — but a
  // THIRD round of real testing disproved that too: a fast pickup catch
  // measured `peakImpactG` up to **4.02g**, well past the 2.0g gate,
  // meaning a hard catch decelerates the phone just as sharply as many
  // real falls would. Two corroboration heuristics in a row, each
  // reasoned from real physics, each disproven by the next round of real
  // data — see ml/README.md for the full trail.
  //
  // Decision (given the SIH26 demo deadline and no time left to validate
  // a third heuristic): dropped corroboration entirely and gated back on
  // `threshold`/`_consecutiveTriggersToAlert` alone — the only piece of
  // this pipeline actually validated against real held-out labeled data.
  // `longestFreefallRun`/`peakImpactGAfterFreefall`/
  // `hasPostFreefallImpact` are kept in `fall_inference.dart` and still
  // logged below (`freefallMs`/`peakImpactG`/`hasImpact`) for visibility
  // and future tuning, just no longer gated on. This knowingly brings
  // back the pickup/short-fall false-positive rate — accepted because
  // the 10s "I'm OK" countdown (`_emergencyCountdownSeconds` below) makes
  // a false positive cost one tap, not a real emergency call, while a
  // missed real fall has no equivalent recovery.

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

  /// Whether live detection is currently running — Settings' "Fall
  /// detection" toggle reads this to show current state.
  bool isRunning = false;

  Future<void> start() async {
    if (isRunning) return;
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
    isRunning = true;
    notifyListeners();
  }

  /// Settings' "Fall detection" toggle turning it off. Leaves any
  /// already-active alert alone — `dismissAlert` handles that separately
  /// — so turning detection off mid-alert can't silently swallow a real
  /// one that's already in its countdown.
  void stop() {
    if (!isRunning) return;
    _timer?.cancel();
    _timer = null;
    phoneMotionService.removeListener(_onPhoneUpdate);
    _inference.close();
    _consecutiveTriggers = 0;
    fallProbability = 0.0;
    isRunning = false;
    notifyListeners();
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
    final freefallMs = _inference.longestFreefallRun().inMilliseconds;
    final peakImpactG = _inference.peakImpactGAfterFreefall();
    final hasImpact = _inference.hasPostFreefallImpact();

    // Only START a new alert from live detection — while one is already
    // active, ignore further triggers so the live signal dropping back
    // down (which happens within ~1s of a real fall settling) can't
    // interfere with the latched alert/countdown already in progress.
    //
    // Gated on the CNN + consecutive-count alone — the only piece
    // actually validated against real held-out labeled data (92%/92%,
    // see ml/README.md's "Threshold tuning"). Both corroboration
    // heuristics tried on top of it (free-fall duration, then impact
    // magnitude) failed against real on-device test data, and a fast
    // pickup jerk can match or exceed a real fall on either signal — see
    // this class's own doc comment and ml/README.md for the full
    // evidence trail. `freefallMs`/`peakImpactG`/`hasImpact` are still
    // logged below for visibility, just no longer gated on. Accepted
    // tradeoff: pickup/short-fall false positives are back, but the 10s
    // "I'm OK" countdown below means a false positive costs one tap, not
    // a real emergency call — a missed real fall is the worse failure
    // mode of the two.
    if (!alertActive && _consecutiveTriggers >= _consecutiveTriggersToAlert) {
      _startAlert(AlertSource.fall);
    }

    debugPrint('[FallDetector] cnnProb=${fallProbability.toStringAsFixed(3)} '
        'triggeredNow=$triggeredNow consecutive=$_consecutiveTriggers '
        'freefallMs=$freefallMs peakImpactG=${peakImpactG.toStringAsFixed(2)} '
        'hasImpact=$hasImpact alertActive=$alertActive');

    notifyListeners();
  }

  /// Manually raised SOS — same countdown/escalation flow as an
  /// auto-detected fall, minus the CNN. Ignored while an alert (of either
  /// kind) is already active, so it can't stomp on an in-progress one.
  void triggerManualSOS() {
    if (alertActive) return;
    _startAlert(AlertSource.manual);
  }

  /// Settings' "Fall detection" screen — previews exactly what a real
  /// detected fall looks like (banner text, 10s countdown, "I'm OK"
  /// dismiss) without needing to actually drop the phone. Always forced
  /// into test mode so a demo left running to completion can never place
  /// a real call, regardless of the app's real test-mode setting —
  /// matches `DeveloperDemoScreen`'s "Preview emergency workflow" button.
  void triggerFallDemo() {
    if (alertActive) return;
    _startAlert(AlertSource.fall, forceMock: true);
  }

  bool _alertForceMock = false;

  void _startAlert(AlertSource source, {bool forceMock = false}) {
    alertActive = true;
    alertSource = source;
    isCalling = false;
    secondsUntilCall = _emergencyCountdownSeconds;
    _alertForceMock = forceMock;

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
    emergencyWorkflow.start(triggerReason: reason, forceMock: _alertForceMock);
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
