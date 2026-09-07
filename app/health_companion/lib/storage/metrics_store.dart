import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

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

  Future<void> addBodyFatPercent(double percent) async {
    await _bodyBox.add({
      'type': 'bodyFat',
      'value': percent,
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
  double? get latestBodyFatPercent => _latestOfType('bodyFat');

  /// Body Mass Index from the latest logged weight + height, or null if
  /// either is missing.
  double? get bmi {
    final w = latestWeightKg;
    final h = latestHeightCm;
    if (w == null || h == null || h <= 0) return null;
    final heightM = h / 100;
    return w / (heightM * heightM);
  }

  List<Map> recentWeights({int limit = 30}) => _bodyBox.values
      .where((e) => e['type'] == 'weight')
      .toList()
      .reversed
      .take(limit)
      .toList()
      .reversed
      .toList();

  Future<void> addHydrationMl(int ml) async {
    await _hydrationBox.add({
      'ml': ml,
      'at': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

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
}
