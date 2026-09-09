import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// True while a demo run's 10s wait is in progress — guards against a
/// second tap re-triggering the countdown mid-wait.
bool _demoRunning = false;

/// Manually-triggered preview of the lock-screen SOS escalation path, for
/// verifying `MainActivity.kt`'s `applyLockScreenVisibility` on a real
/// device (lock the phone during the 10s wait, confirm the SOS screen
/// still comes up over the lock screen when it elapses).
///
/// Exercises the exact same wake-screen + `launchApp` mechanism the real
/// background fall alert uses after its own unanswered 10s window (see
/// `lib/background/fall_detection_task_handler.dart`) — reusing
/// `FlutterForegroundTask.wakeUpScreen`/`launchApp` directly rather than
/// duplicating them, since neither depends on the foreground service
/// actually being started (see PluginUtils.kt: both are plain
/// `Context`-based utilities).
///
/// Deliberately isolated from the real fall-detection flow: it never
/// touches `FallDetectorService`/`FallDetectionTaskHandler` and never
/// posts the real emergency notification. `BackgroundEscalationGate`
/// routes `'escalate_demo'` straight to `EmergencyWorkflowService.start`
/// with `forceMock: true`, so this can never place a real call regardless
/// of the app's real test-mode setting.
Future<void> triggerDemoLockScreenEscalation() async {
  if (_demoRunning) return;
  _demoRunning = true;
  const delay = Duration(seconds: 10);

  debugPrint('[DemoEscalation] Triggered — waking the screen and showing '
      'the SOS screen in ${delay.inSeconds}s.');
  var remaining = delay.inSeconds;
  final ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
    remaining--;
    if (remaining > 0) {
      debugPrint('[DemoEscalation] ${remaining}s remaining…');
    } else {
      timer.cancel();
    }
  });

  await Future.delayed(delay);
  ticker.cancel();

  debugPrint('[DemoEscalation] Delay elapsed — waking the screen and '
      "launching over the lock screen if it's locked.");
  FlutterForegroundTask.wakeUpScreen();
  FlutterForegroundTask.launchApp('escalate_demo');
  _demoRunning = false;
}
