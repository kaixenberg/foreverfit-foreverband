import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../domain/units.dart';
import '../models/insight.dart';

/// Whether ambient temperature/humidity/pressure prefers the wearable's
/// own BME280 or online weather when both are available — the one place
/// in the app that currently has more than one source for the same
/// reading (see ARCHITECTURE.md's "sensor precedence" section for why
/// this isn't a more general system yet).
enum AmbientSourcePreference { preferWearable, preferOnline }

/// Which motion sensor(s) the on-device fall-detection CNN runs on —
/// the phone's own accelerometer/gyroscope alone, or the wearable's
/// wrist-worn MPU6050 fused with the phone's accelerometer (the
/// original wrist+phone design, unavailable while the wearable's first
/// MPU6050 was dead — see ARCHITECTURE.md). Phone-only stays the
/// default: it works with no wearable connected at all, and watch mode
/// additionally requires a live BLE connection to produce any readings.
enum FallDetectionSensorSource { phone, watch }

/// App-wide preferences — units, appearance, sensor precedence, and
/// notification-category opt-outs. One Hive box, one document, same
/// single-document pattern as EmergencyContactStore. Deliberately
/// excluded from data export/import (see BackupService) — this is app
/// preference, not user data.
class AppSettingsStore extends ChangeNotifier {
  static const _boxName = 'app_settings';
  static const _key = 'settings';

  Box<Map>? _box;

  UnitSystem unitSystem = UnitSystem.metric;
  ThemeMode themeMode = ThemeMode.system;
  bool oledBlack = false;
  AmbientSourcePreference ambientSourcePreference =
      AmbientSourcePreference.preferWearable;
  bool notifyVitals = true;
  bool notifyHazards = true;
  bool notifyReminders = true;

  /// Whether the on-device fall-detection CNN runs at all — a safety
  /// feature, so on by default (opt-out, not opt-in). Settings' "Fall
  /// detection" screen exposes the toggle; `main.dart` reads this once
  /// at startup to decide whether to call `FallDetectorService.start()`.
  bool fallDetectionEnabled = true;

  /// Which sensor(s) fall detection runs on — see
  /// `FallDetectionSensorSource`'s own doc comment. Exposed on the same
  /// "Fall detection" Settings screen as `fallDetectionEnabled` above.
  FallDetectionSensorSource fallDetectionSensorSource =
      FallDetectionSensorSource.phone;

  bool isCategoryEnabled(InsightCategory category) {
    switch (category) {
      case InsightCategory.vitals:
        return notifyVitals;
      case InsightCategory.hazard:
        return notifyHazards;
      case InsightCategory.reminder:
        return notifyReminders;
    }
  }

  Future<void> init() async {
    final box = await Hive.openBox<Map>(_boxName);
    _box = box;
    final saved = box.get(_key);
    if (saved == null) return;
    unitSystem = UnitSystem.values.firstWhere(
      (v) => v.name == saved['unitSystem'],
      orElse: () => UnitSystem.metric,
    );
    themeMode = ThemeMode.values.firstWhere(
      (v) => v.name == saved['themeMode'],
      orElse: () => ThemeMode.system,
    );
    oledBlack = saved['oledBlack'] as bool? ?? false;
    ambientSourcePreference = AmbientSourcePreference.values.firstWhere(
      (v) => v.name == saved['ambientSourcePreference'],
      orElse: () => AmbientSourcePreference.preferWearable,
    );
    notifyVitals = saved['notifyVitals'] as bool? ?? true;
    notifyHazards = saved['notifyHazards'] as bool? ?? true;
    notifyReminders = saved['notifyReminders'] as bool? ?? true;
    fallDetectionEnabled = saved['fallDetectionEnabled'] as bool? ?? true;
    fallDetectionSensorSource = FallDetectionSensorSource.values.firstWhere(
      (v) => v.name == saved['fallDetectionSensorSource'],
      orElse: () => FallDetectionSensorSource.phone,
    );
  }

  Future<void> setUnitSystem(UnitSystem value) async {
    unitSystem = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setOledBlack(bool value) async {
    oledBlack = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setAmbientSourcePreference(AmbientSourcePreference value) async {
    ambientSourcePreference = value;
    await _persist();
    notifyListeners();
  }

  Future<void> resetAmbientSourcePreference() =>
      setAmbientSourcePreference(AmbientSourcePreference.preferWearable);

  Future<void> setNotifyVitals(bool value) async {
    notifyVitals = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setNotifyHazards(bool value) async {
    notifyHazards = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setNotifyReminders(bool value) async {
    notifyReminders = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setFallDetectionEnabled(bool value) async {
    fallDetectionEnabled = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setFallDetectionSensorSource(
      FallDetectionSensorSource value) async {
    fallDetectionSensorSource = value;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _box?.put(_key, {
      'unitSystem': unitSystem.name,
      'themeMode': themeMode.name,
      'oledBlack': oledBlack,
      'ambientSourcePreference': ambientSourcePreference.name,
      'notifyVitals': notifyVitals,
      'notifyHazards': notifyHazards,
      'notifyReminders': notifyReminders,
      'fallDetectionEnabled': fallDetectionEnabled,
      'fallDetectionSensorSource': fallDetectionSensorSource.name,
    });
  }
}
