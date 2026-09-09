import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/metric_point.dart';
import '../models/stored_entry.dart';

/// Local, manually-logged body/hydration metrics — same offline-first,
/// on-device-only storage pattern as HistoryStore, just for user-entered
/// data instead of wearable readings. No Health Connect dependency (this
/// app doesn't integrate with it) — a deliberate, much smaller substitute
/// for that piece of the reference app reviewed for the dashboard
/// redesign, see ARCHITECTURE.md. Extends ChangeNotifier (unlike
/// HistoryStore) so the dashboard can react immediately after a log entry.
class MetricsStore extends ChangeNotifier {
  static const String _bodyBoxName = 'body_metrics';
  static const String _hydrationBoxName = 'hydration_log';

  late Box<Map> _bodyBox;
  late Box<Map> _hydrationBox;

  Future<void> init() async {
    _bodyBox = await Hive.openBox<Map>(_bodyBoxName);
    _hydrationBox = await Hive.openBox<Map>(_hydrationBoxName);
  }

  Future<void> addWeightKg(double kg) async {
    await _bodyBox.add({
      'type': 'weight',
      'value': kg,
      'at': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  Future<void> addHeightCm(double cm) async {
    await _bodyBox.add({
      'type': 'height',
      'value': cm,
      'at': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  double? _latestOfType(String type) {
    Map? latest;
    DateTime? latestAt;
    for (final entry in _bodyBox.values) {
      if (entry['type'] != type) continue;
      final at = DateTime.tryParse(entry['at'] as String? ?? '');
      if (at == null) continue;
      if (latestAt == null || at.isAfter(latestAt)) {
        latest = entry;
        latestAt = at;
      }
    }
    return (latest?['value'] as num?)?.toDouble();
  }

  double? get latestWeightKg => _latestOfType('weight');
  double? get latestHeightCm => _latestOfType('height');

  /// Body Mass Index from the latest logged weight + height, or null if
  /// either is missing.
  double? get bmi {
    final w = latestWeightKg;
    final h = latestHeightCm;
    if (w == null || h == null || h <= 0) return null;
    final heightM = h / 100;
    return w / (heightM * heightM);
  }

  /// BMI over time, paired from the weight history against whatever
  /// height was on record at-or-before each weigh-in (falls back to the
  /// earliest known height for weigh-ins that predate any height log) —
  /// height rarely changes for an adult, so this is realistically driven
  /// by the weight series. Empty if either history is empty.
  List<MetricPoint> bmiHistory() {
    final weights = historyOfType('weight');
    final heights = historyOfType('height');
    if (weights.isEmpty || heights.isEmpty) return const [];
    final points = <MetricPoint>[];
    for (final w in weights) {
      double? heightAtTime;
      for (final h in heights) {
        if (!h.at.isAfter(w.at)) {
          heightAtTime = h.value;
        } else {
          break;
        }
      }
      heightAtTime ??= heights.first.value;
      if (heightAtTime <= 0) continue;
      final heightM = heightAtTime / 100;
      points.add(MetricPoint(at: w.at, value: w.value / (heightM * heightM)));
    }
    return points;
  }

  /// Full timestamped history for weight/height, oldest first — backs
  /// MetricHistoryScreen's chart for each.
  List<MetricPoint> historyOfType(String type) {
    final points = <MetricPoint>[];
    for (final entry in _bodyBox.values) {
      if (entry['type'] != type) continue;
      final at = DateTime.tryParse(entry['at'] as String? ?? '');
      final value = (entry['value'] as num?)?.toDouble();
      if (at == null || value == null) continue;
      points.add(MetricPoint(at: at, value: value));
    }
    points.sort((a, b) => a.at.compareTo(b.at));
    return points;
  }

  /// Editable entries for weight/height, newest first — backs
  /// MetricHistoryScreen's edit/delete list.
  List<StoredEntry> entriesOfType(String type) =>
      _entriesOf(_bodyBox, where: (e) => e['type'] == type);

  Future<void> updateBodyMetricEntry(dynamic key, double value) =>
      _updateEntry(_bodyBox, key, {'value': value});

  Future<void> deleteBodyMetricEntry(dynamic key) =>
      _deleteEntry(_bodyBox, key);

  Future<void> addHydrationMl(int ml) async {
    await _hydrationBox.add({
      'ml': ml,
      'at': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  List<StoredEntry> hydrationEntries() => _entriesOf(_hydrationBox);

  Future<void> updateHydrationEntry(dynamic key, int ml) =>
      _updateEntry(_hydrationBox, key, {'ml': ml});

  Future<void> deleteHydrationEntry(dynamic key) =>
      _deleteEntry(_hydrationBox, key);

  /// Sum of everything logged since local midnight today.
  int get todayHydrationMl {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    var total = 0;
    for (final entry in _hydrationBox.values) {
      final at = DateTime.tryParse(entry['at'] as String? ?? '');
      if (at == null || at.isBefore(startOfDay)) continue;
      total += (entry['ml'] as num?)?.toInt() ?? 0;
    }
    return total;
  }

  /// Daily totals (in liters) across every day something was logged,
  /// oldest first — backs the Hydration history chart.
  List<MetricPoint> hydrationDailyTotals() {
    final totalsByDay = <DateTime, int>{};
    for (final entry in _hydrationBox.values) {
      final at = DateTime.tryParse(entry['at'] as String? ?? '');
      final ml = (entry['ml'] as num?)?.toInt();
      if (at == null || ml == null) continue;
      final day = DateTime(at.year, at.month, at.day);
      totalsByDay[day] = (totalsByDay[day] ?? 0) + ml;
    }
    final days = totalsByDay.keys.toList()..sort();
    return [
      for (final day in days)
        MetricPoint(at: day, value: totalsByDay[day]! / 1000),
    ];
  }

  // --- Shared editable-entry helpers, reused by weight/height/hydration -

  List<StoredEntry> _entriesOf(
    Box<Map> box, {
    bool Function(Map entry)? where,
  }) {
    final result = <StoredEntry>[];
    for (final key in box.keys) {
      final entry = box.get(key);
      if (entry == null) continue;
      if (where != null && !where(entry)) continue;
      final at = DateTime.tryParse(entry['at'] as String? ?? '');
      if (at == null) continue;
      result.add(StoredEntry(
          key: key, at: at, data: Map<String, dynamic>.from(entry)));
    }
    result.sort((a, b) => b.at.compareTo(a.at));
    return result;
  }

  Future<void> _updateEntry(
    Box<Map> box,
    dynamic key,
    Map<String, dynamic> patch,
  ) async {
    final existing = box.get(key);
    if (existing == null) return;
    await box.put(key, {...Map<String, dynamic>.from(existing), ...patch});
    notifyListeners();
  }

  Future<void> _deleteEntry(Box<Map> box, dynamic key) async {
    await box.delete(key);
    notifyListeners();
  }
}
