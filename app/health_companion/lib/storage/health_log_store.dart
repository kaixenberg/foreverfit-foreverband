import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/metric_point.dart';

/// One tracked medication's schedule info — not time-series data, so it
/// lives as a small list of records rather than timestamped entries.
class Medication {
  final String key;
  final String name;
  final String dosage;
  final String frequency;

  const Medication({
    required this.key,
    required this.name,
    required this.dosage,
    required this.frequency,
  });
}

/// The static "in case of emergency" profile — blood type, allergies,
/// conditions. Deliberately NOT time-series data (there's no meaningful
/// "average blood type"), so unlike everything else in this store it has
/// no MetricPoint history and no chart screen — just a single saved
/// profile, same idea as a physical medical-alert card.
class MedicalIdProfile {
  final String bloodType;
  final String allergies;
  final String conditions;
  final String notes;

  const MedicalIdProfile({
    required this.bloodType,
    required this.allergies,
    required this.conditions,
    required this.notes,
  });

  bool get isEmpty =>
      bloodType.isEmpty &&
      allergies.isEmpty &&
      conditions.isEmpty &&
      notes.isEmpty;
}

/// Local storage for the remaining Health Log metrics — blood pressure,
/// blood glucose, insulin, medications, sleep, and Medical ID. Same
/// offline-first Hive pattern as MetricsStore; kept in its own store
/// since these are a distinct domain (clinical tracking vs. body
/// composition/hydration).
class HealthLogStore extends ChangeNotifier {
  static const _bpBoxName = 'bp_log';
  static const _glucoseBoxName = 'glucose_log';
  static const _insulinBoxName = 'insulin_log';
  static const _sleepBoxName = 'sleep_log';
  static const _medicationsBoxName = 'medications';
  static const _medicationDosesBoxName = 'medication_doses_log';
  static const _medicalIdBoxName = 'medical_id';

  late Box<Map> _bpBox;
  late Box<Map> _glucoseBox;
  late Box<Map> _insulinBox;
  late Box<Map> _sleepBox;
  late Box<Map> _medicationsBox;
  late Box<Map> _medicationDosesBox;
  late Box<Map> _medicalIdBox;

  Future<void> init() async {
    _bpBox = await Hive.openBox<Map>(_bpBoxName);
    _glucoseBox = await Hive.openBox<Map>(_glucoseBoxName);
    _insulinBox = await Hive.openBox<Map>(_insulinBoxName);
    _sleepBox = await Hive.openBox<Map>(_sleepBoxName);
    _medicationsBox = await Hive.openBox<Map>(_medicationsBoxName);
    _medicationDosesBox = await Hive.openBox<Map>(_medicationDosesBoxName);
    _medicalIdBox = await Hive.openBox<Map>(_medicalIdBoxName);
  }

  // --- Blood pressure (two values per entry) --------------------------

  Future<void> addBloodPressure(int systolic, int diastolic) async {
    await _bpBox.add({
      'systolic': systolic,
      'diastolic': diastolic,
      'at': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  List<MetricPoint> bloodPressureSystolicHistory() => [
        for (final e in _bpBox.values)
          if (DateTime.tryParse(e['at'] as String? ?? '') != null)
            MetricPoint(
              at: DateTime.parse(e['at'] as String),
              value: (e['systolic'] as num).toDouble(),
            ),
      ]..sort((a, b) => a.at.compareTo(b.at));

  List<MetricPoint> bloodPressureDiastolicHistory() => [
        for (final e in _bpBox.values)
          if (DateTime.tryParse(e['at'] as String? ?? '') != null)
            MetricPoint(
              at: DateTime.parse(e['at'] as String),
              value: (e['diastolic'] as num).toDouble(),
            ),
      ]..sort((a, b) => a.at.compareTo(b.at));

  (int, int)? get latestBloodPressure {
    Map? latest;
    DateTime? latestAt;
    for (final e in _bpBox.values) {
      final at = DateTime.tryParse(e['at'] as String? ?? '');
      if (at == null) continue;
      if (latestAt == null || at.isAfter(latestAt)) {
        latest = e;
        latestAt = at;
      }
    }
    if (latest == null) return null;
    return (
      (latest['systolic'] as num).toInt(),
      (latest['diastolic'] as num).toInt()
    );
  }

  // --- Blood glucose ----------------------------------------------------

  Future<void> addGlucose(double value) async {
    await _glucoseBox
        .add({'value': value, 'at': DateTime.now().toIso8601String()});
    notifyListeners();
  }

  List<MetricPoint> glucoseHistory() => _historyOf(_glucoseBox, 'value');

  double? get latestGlucose => _latestOf(_glucoseBox, 'value');

  // --- Insulin ------------------------------------------------------------

  Future<void> addInsulin(double doseUnits, String type) async {
    await _insulinBox.add({
      'dose': doseUnits,
      'type': type,
      'at': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  List<MetricPoint> insulinDoseHistory() => _historyOf(_insulinBox, 'dose');

  double? get latestInsulinDose => _latestOf(_insulinBox, 'dose');

  // --- Sleep ----------------------------------------------------------

  Future<void> addSleep(double hours) async {
    await _sleepBox
        .add({'hours': hours, 'at': DateTime.now().toIso8601String()});
    notifyListeners();
  }

  List<MetricPoint> sleepHistory() => _historyOf(_sleepBox, 'hours');

  double? get latestSleepHours => _latestOf(_sleepBox, 'hours');

  // --- Medications (a list, not time-series) + dose-taken log --------

  List<Medication> get medications => [
        for (final key in _medicationsBox.keys)
          Medication(
            key: key as String,
            name: _medicationsBox.get(key)!['name'] as String,
            dosage: _medicationsBox.get(key)!['dosage'] as String,
            frequency: _medicationsBox.get(key)!['frequency'] as String,
          ),
      ];

  Future<void> addMedication({
    required String name,
    required String dosage,
    required String frequency,
  }) async {
    final key = DateTime.now().microsecondsSinceEpoch.toString();
    await _medicationsBox
        .put(key, {'name': name, 'dosage': dosage, 'frequency': frequency});
    notifyListeners();
  }

  Future<void> removeMedication(String key) async {
    await _medicationsBox.delete(key);
    notifyListeners();
  }

  Future<void> logDoseTaken(String medicationName) async {
    await _medicationDosesBox.add({
      'medication': medicationName,
      'at': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  int get dosesTakenToday {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    return _medicationDosesBox.values.where((e) {
      final at = DateTime.tryParse(e['at'] as String? ?? '');
      return at != null && !at.isBefore(startOfDay);
    }).length;
  }

  /// Daily dose counts — the closest thing to a "trend" medication
  /// adherence has, since a medication name/dosage isn't itself a number
  /// worth charting.
  List<MetricPoint> dosesTakenDailyHistory() {
    final byDay = <DateTime, int>{};
    for (final e in _medicationDosesBox.values) {
      final at = DateTime.tryParse(e['at'] as String? ?? '');
      if (at == null) continue;
      final day = DateTime(at.year, at.month, at.day);
      byDay[day] = (byDay[day] ?? 0) + 1;
    }
    final days = byDay.keys.toList()..sort();
    return [
      for (final d in days) MetricPoint(at: d, value: byDay[d]!.toDouble())
    ];
  }

  // --- Medical ID (a single saved profile, not time-series) ------------

  MedicalIdProfile? get medicalId {
    if (_medicalIdBox.isEmpty) return null;
    final e = _medicalIdBox.get('profile');
    if (e == null) return null;
    return MedicalIdProfile(
      bloodType: e['bloodType'] as String? ?? '',
      allergies: e['allergies'] as String? ?? '',
      conditions: e['conditions'] as String? ?? '',
      notes: e['notes'] as String? ?? '',
    );
  }

  Future<void> saveMedicalId(MedicalIdProfile profile) async {
    await _medicalIdBox.put('profile', {
      'bloodType': profile.bloodType,
      'allergies': profile.allergies,
      'conditions': profile.conditions,
      'notes': profile.notes,
    });
    notifyListeners();
  }

  // --- Shared helpers ---------------------------------------------------

  List<MetricPoint> _historyOf(Box<Map> box, String field) => [
        for (final e in box.values)
          if (DateTime.tryParse(e['at'] as String? ?? '') != null)
            MetricPoint(
              at: DateTime.parse(e['at'] as String),
              value: (e[field] as num).toDouble(),
            ),
      ]..sort((a, b) => a.at.compareTo(b.at));

  double? _latestOf(Box<Map> box, String field) {
    Map? latest;
    DateTime? latestAt;
    for (final e in box.values) {
      final at = DateTime.tryParse(e['at'] as String? ?? '');
      if (at == null) continue;
      if (latestAt == null || at.isAfter(latestAt)) {
        latest = e;
        latestAt = at;
      }
    }
    return (latest?[field] as num?)?.toDouble();
  }
}
