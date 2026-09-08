import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'fall_detection_task_handler.dart';

/// Dart-side controller for the background fall-detection foreground
/// service — see `fall_detection_task_handler.dart` for what actually
/// runs inside it, and ARCHITECTURE.md for why a foreground service is
/// unavoidable for this. Fall detection is a safety feature, not an
/// opt-in extra, so this is started automatically once onboarding
/// completes (see `main.dart`) — Settings' Background permission screen
/// exposes an explicit toggle to turn it back off.
class BackgroundMonitoringService {
  static const _serviceId = 1000;

  bool _initialized = false;

  void _init() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'health_companion_fall_monitoring',
        channelName: 'Background fall monitoring',
        channelDescription:
            'Shown while the app watches for falls with the screen off '
            'or another app in the foreground.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(500),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  Future<void> start() async {
    if (!Platform.isAndroid) {
      return; // background service is Android-only for now
    }
    _init();
    if (await FlutterForegroundTask.isRunningService) return;

    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: const [ForegroundServiceTypes.health],
      notificationTitle: 'Monitoring for falls',
      notificationText:
          'Health Companion is watching for falls in the background.',
      callback: fallDetectionTaskCallback,
    );
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }
}
