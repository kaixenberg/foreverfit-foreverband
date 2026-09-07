import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../storage/history_store.dart';

/// Learns this user's own resting heart-rate baseline from their local
/// history — NOT a CNN, just a rolling mean/std (see ARCHITECTURE.md's
/// AI/ML roadmap item 2: "more honest about what it is than dressing it
/// up as deep learning"). A fixed global threshold (e.g. ">120 bpm")
/// can't tell "unusual for you" from "unusual in general" — someone whose
/// resting HR normally runs at 95 shouldn't need to hit the same 120
/// ceiling as someone who normally runs at 60 before it's flagged.
class BaselineService extends ChangeNotifier {
  BaselineService({required this.historyStore});

  final HistoryStore historyStore;

  static const _lookback = Duration(days: 7);
  static const _minSamples = 20;
  // Floor on the learned std dev — without it, a very stable short history
  // (e.g. 20 near-identical readings) would produce a tiny std and make
  // the z-score check absurdly trigger-happy.
  static const _minStdBpm = 3.0;
  static const _refreshInterval = Duration(seconds: 30);

  Timer? _timer;

  double? heartRateMean;
  double? heartRateStd;
  int sampleCount = 0;

  void start() {
    refresh();
    _timer = Timer.periodic(_refreshInterval, (_) => refresh());
  }

  void refresh() {
    final cutoff = DateTime.now().subtract(_lookback);
    final samples = historyStore
        .recentVitals(limit: 20000)
        .where((m) {
          final at = DateTime.tryParse(m['receivedAt'] as String? ?? '');
          return at != null && at.isAfter(cutoff);
        })
        .map((m) => (m['heartRate'] as num).toDouble())
        .where((hr) => hr > 0)
        .toList();

    sampleCount = samples.length;
    if (sampleCount < _minSamples) {
      heartRateMean = null;
      heartRateStd = null;
      notifyListeners();
      return;
    }

    final mean = samples.reduce((a, b) => a + b) / samples.length;
    final variance = samples.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
        samples.length;
    heartRateMean = mean;
    heartRateStd = math.max(math.sqrt(variance), _minStdBpm);
    notifyListeners();
  }

  /// True if [liveHeartRate] deviates more than 2 personal standard
  /// deviations from this user's own baseline. Returns false (not
  /// "unknown") when there isn't enough history yet — callers should
  /// treat that as "no personalized signal available", not "anomalous".
  bool isAnomalous(double liveHeartRate) {
    final mean = heartRateMean;
    final std = heartRateStd;
    if (mean == null || std == null) return false;
    return (liveHeartRate - mean).abs() > 2 * std;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
