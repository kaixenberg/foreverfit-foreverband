import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../disaster/disaster_service.dart';
import '../ml/fall_inference.dart';
import '../sensors/phone_motion_service.dart';

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
/// happens after a fall is detected, since that has to go through a
/// notification instead of the in-app countdown UI.
///
/// See ARCHITECTURE.md's background fall-detection section for the full
/// design and its documented limitations (mandatory persistent
/// notification, Hive multi-isolate coordination for the disaster
/// check, the Android 14 full-screen-intent grant).
class FallDetectionTaskHandler extends TaskHandler {
  static const _consecutiveTriggersToAlert = 2;
  static const _alertCountdownSeconds = 10;
  static const _disasterCheckInterval = Duration(minutes: 15);
  static const _monitoringTitle = 'Monitoring for falls';
  static const _monitoringText =
      'Health Companion is watching for falls in the background.';

  final _phoneMotion = PhoneMotionService();
  final _inference = FallInference();

  int _consecutiveTriggers = 0;
  bool _alertActive = false;
  Timer? _countdownTimer;
  int? _secondsRemaining;
  DateTime? _lastDisasterCheck;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _inference.load();
    _phoneMotion.addListener(_onPhoneUpdate);
    _phoneMotion.start();
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

  /// Updates the service's own persistent notification to show the
  /// fall alert + "I'm OK" button — reusing the one mandatory
  /// foreground-service notification rather than showing a second,
  /// separate one (a normal, common pattern for foreground services
  /// that need to surface a transient status change).
  Future<void> _startAlert() async {
    _alertActive = true;
    _secondsRemaining = _alertCountdownSeconds;
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Possible fall detected',
      notificationText: "Tap \"I'm OK\" if you're fine — otherwise help is "
          'on the way in ${_alertCountdownSeconds}s',
      notificationButtons: const [
        NotificationButton(id: 'im_ok', text: "I'm OK")
      ],
    );
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _secondsRemaining = (_secondsRemaining ?? 1) - 1;
      if (_secondsRemaining! <= 0) {
        timer.cancel();
        unawaited(_escalate());
      }
    });
  }

  /// Unaddressed for the full countdown — brings the app to the
  /// foreground (waking the screen, over the lock screen if the Activity
  /// requested that visibility) with a route marker `BackgroundEscalationGate`
  /// reads to immediately run the existing emergency-call workflow,
  /// skipping the in-app countdown since it already elapsed here.
  Future<void> _escalate() async {
    FlutterForegroundTask.wakeUpScreen();
    FlutterForegroundTask.launchApp('escalate_fall');
    await _resetAlert();
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'im_ok' && _alertActive) {
      unawaited(_resetAlert());
    }
  }

  Future<void> _resetAlert() async {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _alertActive = false;
    _secondsRemaining = null;
    _consecutiveTriggers = 0;
    await FlutterForegroundTask.updateService(
      notificationTitle: _monitoringTitle,
      notificationText: _monitoringText,
      notificationButtons: const [],
    );
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
  }
}
