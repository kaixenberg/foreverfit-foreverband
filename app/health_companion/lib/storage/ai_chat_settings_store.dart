import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// User consent + preferences for the optional on-device AI assistant
/// (see lib/ai_chat/ai_chat_service.dart). Deliberately does NOT track
/// whether the model file itself is downloaded — flutter_gemma already
/// persists that on-device (FlutterGemma.isModelInstalled); duplicating it
/// here would just be a second source of truth that can drift.
///
/// Same single-Hive-document pattern as AppSettingsStore. Excluded from
/// data export/import (BackupService) — this is app preference plus a
/// multi-GB on-device file, not user health data.
class AiChatSettingsStore extends ChangeNotifier {
  static const _boxName = 'ai_chat_settings';
  static const _key = 'settings';

  Box<Map>? _box;

  /// User has opted in (seen the download-size warning and accepted).
  bool enabled = false;

  /// Restrict the model download to Wi-Fi, off by explicit user override.
  bool wifiOnlyDownload = true;

  Future<void> init() async {
    final box = await Hive.openBox<Map>(_boxName);
    _box = box;
    final saved = box.get(_key);
    if (saved == null) return;
    enabled = saved['enabled'] as bool? ?? false;
    wifiOnlyDownload = saved['wifiOnlyDownload'] as bool? ?? true;
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setWifiOnlyDownload(bool value) async {
    wifiOnlyDownload = value;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _box?.put(_key, {
      'enabled': enabled,
      'wifiOnlyDownload': wifiOnlyDownload,
    });
  }
}
