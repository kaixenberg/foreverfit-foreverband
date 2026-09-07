import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/metric_point.dart';

/// Today's step count from the phone's own hardware step counter — no
/// Health Connect involved (this app doesn't integrate with it; see
/// ARCHITECTURE.md). Android's TYPE_STEP_COUNTER sensor reports a
/// cumulative count since last boot, not since midnight, so this stores a
/// "steps at start of today" baseline and reports the difference,
/// persisting the baseline so it survives app restarts within the same
/// day. Each day's final total is archived into a history box when the
/// next day starts, so a trend builds up going forward (no retroactive
/// backfill — the sensor only ever reports "since boot").
class StepCounterService extends ChangeNotifier {
  static const _boxName = 'step_baseline';
  static const _historyBoxName = 'step_daily_history';

  StreamSubscription<StepCount>? _sub;
  Box? _box;
  Box<int>? _historyBox;

  int todaySteps = 0;
  String? lastError;

  Future<void> start() async {
    _box = await Hive.openBox(_boxName);
    _historyBox = await Hive.openBox<int>(_historyBoxName);

    final status = await Permission.activityRecognition.request();
    if (!status.isGranted) {
      lastError = 'Step counting needs the activity-recognition permission';
      notifyListeners();
      return;
    }

    _sub = Pedometer.stepCountStream.listen(_onStepCount, onError: (e) {
      lastError = 'Step counter unavailable: $e';
      notifyListeners();
    });
  }

  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  void _onStepCount(StepCount event) {
    final now = DateTime.now();
    final todayKey = _dayKey(now);
    final storedDay = _box?.get('day') as String?;

    if (storedDay != todayKey) {
      // Archive yesterday's final total before resetting the baseline.
      if (storedDay != null) _historyBox?.put(storedDay, todaySteps);
      _box?.put('day', todayKey);
      _box?.put('baseline', event.steps);
      todaySteps = 0;
    } else {
      final baseline = _box?.get('baseline') as int? ?? event.steps;
      todaySteps = (event.steps - baseline).clamp(0, 1 << 31);
    }
    notifyListeners();
  }

  /// Archived daily totals plus today's live count, oldest first — backs
  /// the Steps history chart.
  List<MetricPoint> dailyHistory() {
    final points = <MetricPoint>[];
    for (final key in _historyBox?.keys ?? const <dynamic>[]) {
      final parts = (key as String).split('-');
      if (parts.length != 3) continue;
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);
      final steps = _historyBox?.get(key);
      if (year == null || month == null || day == null || steps == null) {
        continue;
      }
      points.add(
          MetricPoint(at: DateTime(year, month, day), value: steps.toDouble()));
    }
    points.sort((a, b) => a.at.compareTo(b.at));

    final now = DateTime.now();
    points.add(MetricPoint(
      at: DateTime(now.year, now.month, now.day),
      value: todaySteps.toDouble(),
    ));
    return points;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
