import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../disaster/disaster_service.dart';
import '../ml/fall_inference.dart';
import '../sensors/phone_motion_service.dart';
import '../services/notification_service.dart';

/// Must always be a top-level function — this is the entry point the
/// foreground service spins up as a separate background isolate/engine.
@pragma('vm:entry-point')
void fallDetectionTaskCallback() {
  FlutterForegroundTask.setTaskHandler(FallDetectionTaskHandler());
}

/// Runs fall detection continuously while the app is backgrounded — the
/// one thing that genuinely cannot happen without a foreground service
/// (Android hard-stops continuous-mode accelerometer/gyroscope delivery
/// to backgrounded apps on API 28+). Reuses `PhoneMotionService` and
/// `FallInference` completely unchanged (both are plain classes with no
/// Provider/BuildContext dependency) — the only new logic here is what
/// happens after a fall is detected: a high-priority actionable
/// notification (vibration + alarm-stream sound) starts a 10s response
/// window, and only an unanswered window wakes the screen and brings the
/// app forward (over the lock screen, for that one launch only — see
/// `MainActivity.kt`) into the existing emergency-call workflow. Never
/// shows anything over the lock screen at the moment a fall is detected —
/// only after that window elapses unanswered.
///
/// See ARCHITECTURE.md's background fall-detection section for the full
/// design and its documented limitations (mandatory persistent
/// monitoring notification, Hive multi-isolate coordination for the
/// disaster check).
class FallDetectionTaskHandler extends TaskHandler {
  // Kept in sync with FallDetectorService's identical constant — see its
  // comment for why this was briefly raised to 3, then reverted back to
  // 2 (real falls stopped triggering reliably once stacked with
  // FallInference's threshold bump).
  static const _consecutiveTriggersToAlert = 2;

  // Kept in sync with FallDetectorService's identical decision — see its
  // comment for the full evidence trail: free-fall duration (300ms, then
  // 700ms) and impact magnitude were each tried as corroboration and
  // each disproven by the next round of real on-device test data (a
  // pickup jerk can match or exceed a real fall on both signals).
  // Reverted to gating on `threshold`/`_consecutiveTriggersToAlert`
  // alone — the only piece validated against real held-out labeled
  // data — accepting the pickup/short-fall false-positive rate back in
  // exchange for not risking a missed real fall, since the 10s "I'm OK"
  // window below means a false positive costs one tap, not a real call.

  static const _alertCountdownSeconds = 10;
  static const _disasterCheckInterval = Duration(minutes: 15);

  /// A fixed id (distinct from the foreground service's own persistent
  /// notification id in `background_monitoring_service.dart`) so the
  /// alert can be updated/cancelled by id rather than tracked separately.
  static const _alertNotificationId = 5001;

  final _phoneMotion = PhoneMotionService();
  final _inference = FallInference();

  /// A separate plugin instance/channel registration from the main
  /// isolate's `NotificationService` (see main.dart) — this isolate has
  /// its own Flutter engine, so it needs its own `init()` call.
  final _notifications = NotificationService();

  int _consecutiveTriggers = 0;
  bool _alertActive = false;
  Timer? _countdownTimer;
  DateTime? _lastDisasterCheck;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _inference.load();
    await _notifications.init(onNotificationResponse: _onNotificationResponse);
    _phoneMotion.addListener(_onPhoneUpdate);
    _phoneMotion.start();
  }

  /// Fires when the user taps the alert notification's body or its
  /// "I'm OK" action — either counts as acknowledging it, so both cancel
  /// the escalation the same way.
  void _onNotificationResponse(NotificationResponse response) {
    if (response.id == _alertNotificationId && _alertActive) {
      unawaited(_resetAlert());
    }
  }

  void _onPhoneUpdate() {
    final sample = _phoneMotion.latest;
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

  @override
  void onRepeatEvent(DateTime timestamp) {
    _runFallInference();
    unawaited(_maybeCheckDisasterRisk(timestamp));
  }

  void _runFallInference() {
    if (_alertActive) return; // one alert at a time
    final probability = _inference.runIfReady();
    if (probability == null) return;
    final triggeredNow = probability > FallInference.threshold;
    _consecutiveTriggers = triggeredNow ? _consecutiveTriggers + 1 : 0;
    if (_consecutiveTriggers >= _consecutiveTriggersToAlert) {
      unawaited(_startAlert());
    }
  }

  /// Shows the actionable emergency notification (vibration + alarm-stream
  /// sound + an "I'm OK" action — see
  /// `NotificationService.showEmergencyAlert`) and starts the 10-second
  /// response window. Deliberately does NOT wake the screen or bring the
  /// app forward yet — only an unanswered timeout does that (`_escalate`),
  /// so a detected fall never shows anything over the lock screen before
  /// the user has had a chance to respond right from the notification.
  Future<void> _startAlert() async {
    _alertActive = true;
    await _notifications.showEmergencyAlert(
      id: _alertNotificationId,
      title: 'Possible fall detected',
      body: "Tap \"I'm OK\" if you're fine — otherwise help is on the way "
          'in ${_alertCountdownSeconds}s.',
      actions: const [
        AndroidNotificationAction('im_ok', "I'm OK", showsUserInterface: false),
      ],
    );
    _countdownTimer?.cancel();
    _countdownTimer =
        Timer(const Duration(seconds: _alertCountdownSeconds), () {
      unawaited(_escalate());
    });
  }

  /// Unanswered for the full 10s window — wakes the screen and brings the
  /// app forward with a route marker `BackgroundEscalationGate` reads to
  /// immediately run the existing emergency-call workflow, skipping the
  /// in-app countdown since it already elapsed here. `MainActivity.kt`
  /// shows the launched Activity over the lock screen for exactly this
  /// launch (see its `applyLockScreenVisibility`), not as a standing
  /// app-wide setting.
  Future<void> _escalate() async {
    FlutterForegroundTask.wakeUpScreen();
    FlutterForegroundTask.launchApp('escalate_fall');
    await _resetAlert();
  }

  Future<void> _resetAlert() async {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _alertActive = false;
    _consecutiveTriggers = 0;
    await _notifications.cancelNotification(_alertNotificationId);
  }

  /// Reuses `DisasterService` completely unchanged for the periodic
  /// check — zero new disaster-risk logic. Skips entirely whenever the
  /// main app is foregrounded (its own `DisasterService` already handles
  /// this live) so this never touches the `disaster_cache` Hive box at
  /// the same time the main isolate does; closes the box again
  /// immediately after, to keep the window it's open in this isolate as
  /// short as possible. This is a best-effort mitigation, not a
  /// guarantee — see ARCHITECTURE.md.
  Future<void> _maybeCheckDisasterRisk(DateTime now) async {
    final last = _lastDisasterCheck;
    if (last != null && now.difference(last) < _disasterCheckInterval) return;
    _lastDisasterCheck = now;

    if (await FlutterForegroundTask.isAppOnForeground) return;

    try {
      await Hive.initFlutter();
      final disaster = DisasterService();
      await disaster.init();
      final hazards = disaster.risk?.imminentHazards ?? const [];
      if (hazards.isNotEmpty) {
        FlutterForegroundTask.wakeUpScreen();
        FlutterForegroundTask.launchApp('escalate_disaster');
      }
    } catch (_) {
      // Best-effort — try again next interval.
    } finally {
      if (Hive.isBoxOpen('disaster_cache')) {
        await Hive.box('disaster_cache').close();
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _countdownTimer?.cancel();
    _phoneMotion.removeListener(_onPhoneUpdate);
    _phoneMotion.dispose();
    _inference.close();
    await _notifications.cancelNotification(_alertNotificationId);
  }
}
