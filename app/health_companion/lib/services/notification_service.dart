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

  Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings),
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
}
