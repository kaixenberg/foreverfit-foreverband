import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

/// Today's step count from the phone's own hardware step counter — no
/// Health Connect involved (this app doesn't integrate with it; see
/// ARCHITECTURE.md). Android's TYPE_STEP_COUNTER sensor reports a
/// cumulative count since last boot, not since midnight, so this stores a
/// "steps at start of today" baseline and reports the difference,
/// persisting the baseline so it survives app restarts within the same
/// day.
class StepCounterService extends ChangeNotifier {
  static const _boxName = 'step_baseline';

  StreamSubscription<StepCount>? _sub;
  Box? _box;

  int todaySteps = 0;
  String? lastError;

  Future<void> start() async {
    _box = await Hive.openBox(_boxName);

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

  void _onStepCount(StepCount event) {
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month}-${now.day}';
    final storedDay = _box?.get('day') as String?;

    if (storedDay != todayKey) {
      // First reading of a new day — this cumulative count becomes the
      // new baseline, so today starts at 0.
      _box?.put('day', todayKey);
      _box?.put('baseline', event.steps);
      todaySteps = 0;
    } else {
      final baseline = _box?.get('baseline') as int? ?? event.steps;
      todaySteps = (event.steps - baseline).clamp(0, 1 << 31);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
