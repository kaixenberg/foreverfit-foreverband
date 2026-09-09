import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/watch_settings.dart';

/// Persists the wearable's watch-face preferences on the phone side —
/// same single-document Hive pattern as AppSettingsStore/
/// EmergencyContactStore. Kept as its own store rather than folded into
/// AppSettingsStore since every field here also needs pushing to the
/// wearable over BLE on change (see BleService.syncWatchSettings()),
/// unlike AppSettingsStore's purely phone-side preferences.
class WatchSettingsStore extends ChangeNotifier {
  static const _boxName = 'watch_settings';
  static const _key = 'settings';

  Box<Map>? _box;

  WatchSettings settings = WatchSettings.defaults;

  Future<void> init() async {
    final box = await Hive.openBox<Map>(_boxName);
    _box = box;
    final saved = box.get(_key);
    if (saved == null) return;
    settings = WatchSettings(
      selectedFace: WatchFace.values.firstWhere(
        (v) => v.name == saved['selectedFace'],
        orElse: () => WatchFace.primary,
      ),
      autoCycleEnabled: saved['autoCycleEnabled'] as bool? ?? false,
      autoCycleIntervalSeconds: saved['autoCycleIntervalSeconds'] as int? ?? 10,
      use24HourFormat: saved['use24HourFormat'] as bool? ?? true,
      dateFormat: WatchDateFormat.values.firstWhere(
        (v) => v.name == saved['dateFormat'],
        orElse: () => WatchDateFormat.weekdayShortWithYear,
      ),
      showSeconds: saved['showSeconds'] as bool? ?? false,
    );
  }

  /// Applies [next], persists it, and notifies — callers (the settings
  /// screen) are responsible for also calling
  /// `BleService.syncWatchSettings()` afterward to push it live if
  /// connected; this store only owns persistence, not the BLE write.
  Future<void> update(WatchSettings next) async {
    settings = next;
    await _box?.put(_key, {
      'selectedFace': settings.selectedFace.name,
      'autoCycleEnabled': settings.autoCycleEnabled,
      'autoCycleIntervalSeconds': settings.autoCycleIntervalSeconds,
      'use24HourFormat': settings.use24HourFormat,
      'dateFormat': settings.dateFormat.name,
      'showSeconds': settings.showSeconds,
    });
    notifyListeners();
  }
}
