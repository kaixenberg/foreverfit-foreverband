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

  Future<void> _persist() async {
    await _box?.put(_key, {
      'unitSystem': unitSystem.name,
      'themeMode': themeMode.name,
      'oledBlack': oledBlack,
      'ambientSourcePreference': ambientSourcePreference.name,
      'notifyVitals': notifyVitals,
      'notifyHazards': notifyHazards,
      'notifyReminders': notifyReminders,
    });
  }
}
