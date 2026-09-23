import 'dart:async';

import '../storage/app_settings_store.dart';
import '../storage/health_log_store.dart';
import 'notification_service.dart';

/// Fires a notification when a medication's dose time is reached — by
/// polling the clock every 20s while the app is alive, NOT by scheduling
/// an OS-level alarm.
///
/// This replaced an `AndroidAlarmManager`/`flutter_local_notifications`
/// `zonedSchedule` implementation after extensive on-device debugging
/// (real device, `adb`/`dumpsys` at every layer) confirmed the *entire*
/// scheduling pipeline was working correctly — the Dart call succeeded,
/// the native alarm fired at the right wall-clock time, the plugin's
/// `ScheduledNotificationReceiver` ran to completion and even
/// successfully rescheduled its own next occurrence — and the
/// notification still never got posted. Two separate MIUI-specific
/// app-ops restrictions (`Autostart`, and a second "ask"-state op) were
/// found and fixed along the way and neither one was the actual fix.
/// Whatever was left blocking it happens silently inside MIUI's
/// notification-manager fork with no exception, no log line, and no
/// `adb`-queryable state — effectively undebuggable from here.
///
/// This polling approach only uses `NotificationService.showMedicationReminder`
/// (a plain immediate `.show()`), the exact call already proven to work
/// reliably on this device (it's what `InsightWatcherService` has used
/// successfully all along) — no AlarmManager, no background broadcast
/// receiver, nothing MIUI's battery/notification management can silently
/// intercept the way it did the alarm-based path.
///
/// The trade-off, and it's a real one: this only fires while the app's
/// Dart isolate is alive — open, or recently backgrounded before Android
/// kills the process. It will NOT wake the phone up from a killed/
/// swiped-away state the way a real OS alarm would have. Given the
/// alarm-based approach was silently not firing AT ALL on this device
/// despite being textbook-correct, an approach that reliably fires
/// whenever the app is running is a strict improvement over one that
/// was supposed to work everywhere but silently didn't — and it's
/// honest about its own limit rather than pretending to a guarantee
/// this device wasn't actually honoring anyway.
class MedicationReminderService {
  MedicationReminderService({
    required this.healthLog,
    required this.notifications,
    required this.appSettings,
  });

  final HealthLogStore healthLog;
  final NotificationService notifications;
  final AppSettingsStore appSettings;

  static const _pollInterval = Duration(seconds: 20);

  Timer? _timer;

  /// '$medicationKey#$scheduleIndex' entries already fired today —
  /// prevents re-notifying on every 20s tick for the rest of the minute
  /// a dose time falls in. Cleared when the calendar date rolls over
  /// (see `_checkNow`), so the same schedule fires again tomorrow.
  final Set<String> _firedToday = {};
  DateTime? _firedTodayDate;

  Future<void> start() async {
    await notifications.init();
    _checkNow();
    _timer = Timer.periodic(_pollInterval, (_) => _checkNow());
  }

  void dispose() {
    _timer?.cancel();
  }

  void _checkNow() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_firedTodayDate != today) {
      _firedToday.clear();
      _firedTodayDate = today;
    }

    if (!appSettings.notifyReminders) return;

    for (final medication in healthLog.medications) {
      if (!medication.isActive) continue;
      for (var i = 0; i < medication.schedules.length; i++) {
        final schedule = medication.schedules[i];
        if (schedule.hour != now.hour || schedule.minute != now.minute) {
          continue;
        }
        final fireKey = '${medication.key}#$i';
        if (!_firedToday.add(fireKey)) continue; // already fired this minute

        notifications.showMedicationReminder(
          id: NotificationService.medicationReminderId(medication.key, i),
          title: 'Time for ${medication.name}',
          body: medication.dosage.isNotEmpty
              ? medication.dosage
              : 'Take your scheduled dose.',
        );
      }
    }
  }
}
