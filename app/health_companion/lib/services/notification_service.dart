import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/insight.dart';

/// Thin wrapper around flutter_local_notifications — the only file in the
/// app that talks to the plugin directly, so the API surface (channel ids,
/// importance mapping) only needs to be gotten right in one place.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  int _nextId = 0;

  static const _channelId = 'health_companion_insights';
  static const _channelName = 'Health insights & warnings';
  static const _channelDescription =
      'Vitals anomalies, disaster/air-quality warnings, and tracking reminders';

  /// A separate, higher-priority channel for the fall-detection emergency
  /// alert — its own channel rather than reusing `_channelId`, since
  /// Android locks a channel's sound/vibration/importance in at first
  /// creation, and this one needs to be louder and more insistent than a
  /// routine insight notification.
  static const _emergencyChannelId = 'health_companion_emergency';
  static const _emergencyChannelName = 'Fall & emergency alerts';
  static const _emergencyChannelDescription =
      'The actionable alert shown when a possible fall is detected — '
      'vibrates and sounds an alarm even in silent/Do Not Disturb mode';

  /// A strong, unmistakable pattern: buzz, pause, buzz, pause, buzz.
  static final _emergencyVibrationPattern =
      Int64List.fromList([0, 1000, 500, 1000, 500, 1000]);

  static const _medicationChannelId = 'health_companion_medication';
  static const _medicationChannelName = 'Medication reminders';
  static const _medicationChannelDescription =
      "Reminders for a medication's dose times";

  /// Medication reminder ids all live at and above this — far above
  /// `showInsight`'s per-session auto-incrementing counter (starts at 0)
  /// and `_alertNotificationId`'s fixed 5001, so the three id spaces
  /// can't collide. Reusing the same id for a given (medication, dose
  /// time) pair (see `MedicationReminderService`) just means a repeat
  /// firing replaces the previous notification instead of stacking
  /// duplicates — there's no "pending/scheduled" set to track any more,
  /// see the class doc below for why.
  static const medicationReminderIdBase = 1000000;

  static int medicationReminderId(String medicationKey, int scheduleIndex) {
    final hash = Object.hash(medicationKey, scheduleIndex) & 0x0fffffff;
    return medicationReminderIdBase + hash;
  }

  /// [onNotificationResponse] fires when the user taps the notification
  /// body or one of its actions — passed through from `initialize()` so a
  /// caller running in its own isolate (the background fall-detection
  /// task handler creates its own `NotificationService` instance — see
  /// `lib/background/fall_detection_task_handler.dart`) can react to it
  /// directly, without needing a separate top-level background callback.
  ///
  /// Idempotent and race-safe: more than one owner now calls this on the
  /// same shared instance at app startup (`InsightWatcherService`,
  /// `MedicationReminderService`), both from `MultiProvider` create
  /// callbacks that can run in either order — caching the Future rather
  /// than guarding with a plain bool means a second caller that arrives
  /// before the first `_plugin.initialize()` has finished awaits that
  /// same call instead of racing a second one against it.
  Future<void>? _initFuture;

  Future<void> init({
    DidReceiveNotificationResponseCallback? onNotificationResponse,
  }) {
    return _initFuture ??= _doInit(onNotificationResponse);
  }

  Future<void> _doInit(
    DidReceiveNotificationResponseCallback? onNotificationResponse,
  ) async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: onNotificationResponse,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> showInsight(Insight insight) async {
    final importance = switch (insight.severity) {
      InsightSeverity.critical => Importance.max,
      InsightSeverity.warning => Importance.high,
      InsightSeverity.info => Importance.defaultImportance,
    };
    final priority = switch (insight.severity) {
      InsightSeverity.critical => Priority.max,
      InsightSeverity.warning => Priority.high,
      InsightSeverity.info => Priority.defaultPriority,
    };
    await _plugin.show(
      id: _nextId++,
      title: insight.title,
      body: insight.message,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: importance,
          priority: priority,
        ),
      ),
    );
  }

  /// The actionable fall-detection alert — max importance/priority,
  /// `AndroidNotificationCategory.alarm` + `AudioAttributesUsage.alarm` so
  /// the sound plays through the alarm audio stream (the same mechanism
  /// `AlarmSoundService` uses for the in-app disaster warning) rather than
  /// the notification stream, plus a custom vibration pattern — the most a
  /// normal app is allowed to do to get through silent/Do Not Disturb
  /// without requesting special "bypass DND" access
  /// (`channelBypassDnd`/`requestNotificationPolicyAccess`), which this
  /// deliberately does not request.
  ///
  /// Deliberately NOT a full-screen-intent notification: escalating to the
  /// SOS screen is a decision the caller makes itself after its own 10s
  /// response window, not something the notification should trigger
  /// automatically the moment it's posted.
  Future<void> showEmergencyAlert({
    required int id,
    required String title,
    required String body,
    List<AndroidNotificationAction> actions = const [],
  }) async {
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _emergencyChannelId,
          _emergencyChannelName,
          channelDescription: _emergencyChannelDescription,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          sound: const RawResourceAndroidNotificationSound('alarm_siren'),
          enableVibration: true,
          vibrationPattern: _emergencyVibrationPattern,
          autoCancel: true,
          actions: actions,
        ),
      ),
    );
  }

  Future<void> cancelNotification(int id) => _plugin.cancel(id: id);

  /// Fires a medication-dose-time reminder right now — see
  /// `MedicationReminderService`, which is what decides *when* "now" is
  /// the right time to call this (a plain immediate `.show()`, not
  /// `zonedSchedule`/AlarmManager — see that class's doc for why). Reused
  /// for both a real dose-time firing and the "send test reminder now"
  /// debug button (same [id]/channel either way, see `medicationReminderId`
  /// and `DeveloperDemoScreen`).
  Future<void> showMedicationReminder({
    required int id,
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _medicationChannelId,
          _medicationChannelName,
          channelDescription: _medicationChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
