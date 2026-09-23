import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ble/ble_service.dart';
import '../disaster/disaster_service.dart';
import '../ml/activity_classifier_service.dart';
import '../models/insight.dart';
import '../services/baseline_service.dart';
import '../services/notification_service.dart';
import '../storage/app_settings_store.dart';
import '../storage/health_log_store.dart';
import '../storage/metrics_store.dart';
import '../storage/watch_settings_store.dart';
import 'insight_engine.dart';

/// Recomputes [computeInsights] whenever any input provider changes, plus on
/// a periodic timer (needed for the time-of-day reminders, which nothing
/// else would trigger a recompute for), and fires a local notification for
/// each new or re-triggered warning/critical insight — cooled down per
/// insight id so the same condition doesn't re-notify every recompute while
/// it persists. Exposes the current list so DashboardScreen can also just
/// display it, not only get notified.
class InsightWatcherService extends ChangeNotifier {
  InsightWatcherService({
    required this.ble,
    required this.disaster,
    required this.baseline,
    required this.activityClassifier,
    required this.healthLog,
    required this.metrics,
    required this.notifications,
    required this.appSettings,
    required this.watchSettings,
  });

  final BleService ble;
  final DisasterService disaster;
  final BaselineService baseline;
  final ActivityClassifierService activityClassifier;
  final HealthLogStore healthLog;
  final MetricsStore metrics;
  final NotificationService notifications;
  final AppSettingsStore appSettings;
  final WatchSettingsStore watchSettings;

  static const _periodicInterval = Duration(minutes: 15);
  static const _notifyCooldown = Duration(hours: 1);

  List<Insight> insights = [];
  final Map<String, DateTime> _lastNotifiedAt = {};
  Timer? _timer;

  Future<void> start() async {
    await notifications.init();
    ble.addListener(_recompute);
    disaster.addListener(_recompute);
    baseline.addListener(_recompute);
    activityClassifier.addListener(_recompute);
    healthLog.addListener(_recompute);
    metrics.addListener(_recompute);
    appSettings.addListener(_recompute);
    watchSettings.addListener(_recompute);
    _timer = Timer.periodic(_periodicInterval, (_) => _recompute());
    _recompute();
  }

  void _recompute() {
    final computed = computeInsights(
      ble: ble,
      disaster: disaster,
      baseline: baseline,
      currentActivity: activityClassifier.current,
      healthLog: healthLog,
      metrics: metrics,
      watchSettings: watchSettings,
    );
    // Filtered by category before it's stored OR notified on — a
    // disabled category should disappear from the Dashboard's Insights
    // card too, not just stop notifying (showing a card for a category
    // the user explicitly turned off would be confusing).
    final next = computed
        .where((i) => appSettings.isCategoryEnabled(i.category))
        .toList();
    insights = next;

    final now = DateTime.now();
    for (final insight in next) {
      if (insight.severity == InsightSeverity.info) continue;
      final lastNotified = _lastNotifiedAt[insight.id];
      if (lastNotified == null ||
          now.difference(lastNotified) > _notifyCooldown) {
        _lastNotifiedAt[insight.id] = now;
        notifications.showInsight(insight);
      }
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    ble.removeListener(_recompute);
    disaster.removeListener(_recompute);
    baseline.removeListener(_recompute);
    activityClassifier.removeListener(_recompute);
    healthLog.removeListener(_recompute);
    metrics.removeListener(_recompute);
    appSettings.removeListener(_recompute);
    watchSettings.removeListener(_recompute);
    super.dispose();
  }
}
