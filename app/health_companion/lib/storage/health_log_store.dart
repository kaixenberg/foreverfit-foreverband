import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/metric_point.dart';
import '../models/stored_entry.dart';

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
  static const _cycleBoxName = 'menstrual_cycle_log';

  late Box<Map> _bpBox;
  late Box<Map> _glucoseBox;
  late Box<Map> _insulinBox;
  late Box<Map> _sleepBox;
  late Box<Map> _medicationsBox;
  late Box<Map> _medicationDosesBox;
  late Box<Map> _medicalIdBox;
  late Box<Map> _cycleBox;

  Future<void> init() async {
    _bpBox = await Hive.openBox<Map>(_bpBoxName);
    _glucoseBox = await Hive.openBox<Map>(_glucoseBoxName);
    _insulinBox = await Hive.openBox<Map>(_insulinBoxName);
    _sleepBox = await Hive.openBox<Map>(_sleepBoxName);
    _medicationsBox = await Hive.openBox<Map>(_medicationsBoxName);
    _medicationDosesBox = await Hive.openBox<Map>(_medicationDosesBoxName);
    _medicalIdBox = await Hive.openBox<Map>(_medicalIdBoxName);
    _cycleBox = await Hive.openBox<Map>(_cycleBoxName);
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

  List<StoredEntry> bloodPressureEntries() => _entriesOf(_bpBox);

  Future<void> updateBloodPressureEntry(
    dynamic key,
    int systolic,
    int diastolic,
  ) =>
      _updateEntry(_bpBox, key, {'systolic': systolic, 'diastolic': diastolic});

  Future<void> deleteBloodPressureEntry(dynamic key) =>
      _deleteEntry(_bpBox, key);

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

  List<StoredEntry> glucoseEntries() => _entriesOf(_glucoseBox);

  Future<void> updateGlucoseEntry(dynamic key, double value) =>
      _updateEntry(_glucoseBox, key, {'value': value});

  Future<void> deleteGlucoseEntry(dynamic key) =>
      _deleteEntry(_glucoseBox, key);

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

  List<StoredEntry> insulinEntries() => _entriesOf(_insulinBox);

  Future<void> updateInsulinEntry(dynamic key, double dose, String type) =>
      _updateEntry(_insulinBox, key, {'dose': dose, 'type': type});

  Future<void> deleteInsulinEntry(dynamic key) =>
      _deleteEntry(_insulinBox, key);

  // --- Sleep ----------------------------------------------------------

  Future<void> addSleep(double hours) async {
    await _sleepBox
        .add({'hours': hours, 'at': DateTime.now().toIso8601String()});
    notifyListeners();
  }

  List<MetricPoint> sleepHistory() => _historyOf(_sleepBox, 'hours');

  double? get latestSleepHours => _latestOf(_sleepBox, 'hours');

  List<StoredEntry> sleepEntries() => _entriesOf(_sleepBox);

  Future<void> updateSleepEntry(dynamic key, double hours) =>
      _updateEntry(_sleepBox, key, {'hours': hours});

  Future<void> deleteSleepEntry(dynamic key) => _deleteEntry(_sleepBox, key);

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

  // --- Menstrual cycle (period start/end, flow, notes) ------------------
  //
  // Unlike every other metric above, the meaningful date is when the
  // period *started* — often logged a day or more after the fact — not
  // "now". So 'at' is set to startDate itself rather than
  // DateTime.now(), which keeps this a drop-in fit for the same
  // _entriesOf/_updateEntry/_deleteEntry helpers everything else here
  // uses (they all key off 'at'). Cycle length and period length aren't
  // stored fields — they're derived from consecutive entries, computed
  // in cycleLengthHistory()/periodLengthHistory() below rather than kept
  // in sync by hand on every write.

  Future<void> addCycleEntry({
    required DateTime startDate,
    DateTime? endDate,
    String? flow,
    String? notes,
  }) async {
    await _cycleBox.add({
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'flow': flow,
      'notes': notes,
      'at': startDate.toIso8601String(),
    });
    notifyListeners();
  }

  Future<void> updateCycleEntry(
    dynamic key, {
    required DateTime startDate,
    DateTime? endDate,
    String? flow,
    String? notes,
  }) =>
      _updateEntry(_cycleBox, key, {
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'flow': flow,
        'notes': notes,
        'at': startDate.toIso8601String(),
      });

  Future<void> deleteCycleEntry(dynamic key) => _deleteEntry(_cycleBox, key);

  List<StoredEntry> cycleEntries() => _entriesOf(_cycleBox);

  /// Days between each logged period start and the one before it —
  /// there's no cycle length for the very first logged period (nothing
  /// to measure from), so this always has one fewer point than there are
  /// entries.
  List<MetricPoint> cycleLengthHistory() {
    final starts = <DateTime>[
      for (final e in _cycleBox.values)
        if (DateTime.tryParse(e['startDate'] as String? ?? '') != null)
          DateTime.parse(e['startDate'] as String),
    ]..sort();
    return [
      for (var i = 1; i < starts.length; i++)
        MetricPoint(
          at: starts[i],
          value: starts[i].difference(starts[i - 1]).inDays.toDouble(),
        ),
    ];
  }

  /// Length of each logged period itself (start to end, inclusive) —
  /// only for entries where an end date was actually given.
  List<MetricPoint> periodLengthHistory() => [
        for (final e in _cycleBox.values)
          if (DateTime.tryParse(e['startDate'] as String? ?? '') != null &&
              DateTime.tryParse(e['endDate'] as String? ?? '') != null)
            MetricPoint(
              at: DateTime.parse(e['startDate'] as String),
              value: DateTime.parse(e['endDate'] as String)
                      .difference(DateTime.parse(e['startDate'] as String))
                      .inDays
                      .toDouble() +
                  1,
            ),
      ]..sort((a, b) => a.at.compareTo(b.at));

  DateTime? get latestCycleStart {
    DateTime? latest;
    for (final e in _cycleBox.values) {
      final d = DateTime.tryParse(e['startDate'] as String? ?? '');
      if (d == null) continue;
      if (latest == null || d.isAfter(latest)) latest = d;
    }
    return latest;
  }

  /// Average of up to the last 6 computed cycle lengths — enough to
  /// smooth out one irregular cycle without old data dominating it.
  double? get averageCycleLengthDays {
    final points = cycleLengthHistory();
    if (points.isEmpty) return null;
    final recent =
        points.length > 6 ? points.sublist(points.length - 6) : points;
    return recent.map((p) => p.value).reduce((a, b) => a + b) / recent.length;
  }

  /// Best-effort predicted next period start — the last logged start
  /// plus the average cycle length. Null until there are at least two
  /// logged starts to derive a cycle length from at all.
  DateTime? get predictedNextPeriod {
    final start = latestCycleStart;
    final avg = averageCycleLengthDays;
    if (start == null || avg == null) return null;
    return start.add(Duration(days: avg.round()));
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

  List<StoredEntry> _entriesOf(Box<Map> box) {
    final result = <StoredEntry>[];
    for (final key in box.keys) {
      final entry = box.get(key);
      if (entry == null) continue;
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
