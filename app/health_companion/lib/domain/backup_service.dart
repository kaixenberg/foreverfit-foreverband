import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

/// Every Hive box considered "user data" for export/import — deliberately
/// excludes `app_settings` (preference, not data) and pure-cache/
/// transient boxes (`disaster_cache`, `emergency_workflow`,
/// `step_baseline` — a device-specific sensor-boot-count offset that
/// wouldn't mean anything restored onto another device or after a
/// reboot). Hardcoded here as the single source of truth for what a
/// backup covers, since each store manages its own (often private) box
/// name — see ARCHITECTURE.md.
const exportableBoxNames = [
  'vitals_history', 'env_history', // HistoryStore
  'body_metrics', 'hydration_log', // MetricsStore
  'bp_log', 'glucose_log', 'insulin_log', 'sleep_log', // HealthLogStore
  'medications', 'medication_doses_log', 'medical_id', // HealthLogStore
  'emergency_settings', // EmergencyContactStore
  'step_daily_history', // StepCounterService
  'user_profile', // UserProfileStore
];

const _appVersion = '0.1.0';

/// Local-only, unencrypted JSON export/import via Android's Storage
/// Access Framework (SAF) — the user picks the real destination/source
/// file each time, so nothing is written to or read from app-internal
/// storage. See ARCHITECTURE.md's Data export & import section for why
/// encryption and scheduled auto-backup are deliberately deferred.
class BackupService {
  final _safUtil = SafUtil();
  final _safStream = SafStream();

  String _buildExportJson() {
    final boxes = <String, Map<String, dynamic>>{};
    for (final name in exportableBoxNames) {
      if (!Hive.isBoxOpen(name)) continue;
      final box = Hive.box(name);
      final entries = <String, dynamic>{};
      for (final key in box.keys) {
        entries[key.toString()] = box.get(key);
      }
      boxes[name] = entries;
    }
    final payload = {
      'exportedAt': DateTime.now().toIso8601String(),
      'appVersion': _appVersion,
      'boxes': boxes,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Lets the user pick a folder, then writes the export there. Returns
  /// the chosen file name, or null if the user cancelled the picker.
  Future<String?> exportToPickedFolder() async {
    final folder = await _safUtil.pickDirectory(writePermission: true);
    if (folder == null) return null;
    final json = _buildExportJson();
    final fileName =
        'health_companion_backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}.json';
    final result = await _safStream.writeFileBytes(
      folder.uri,
      fileName,
      'application/json',
      Uint8List.fromList(utf8.encode(json)),
    );
    return result.fileName ?? fileName;
  }

  /// Lets the user pick a JSON file, clears every box in
  /// [exportableBoxNames], and repopulates them from the file. Returns
  /// true if a file was picked and imported, false if the user
  /// cancelled. Callers must confirm with the user before calling this
  /// — it's destructive.
  Future<bool> importFromPickedFile() async {
    final file = await _safUtil.pickFile(mimeTypes: const ['application/json']);
    if (file == null) return false;

    final bytes = await _safStream.readFileBytes(file.uri);
    final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final boxes = payload['boxes'] as Map<String, dynamic>? ?? {};

    for (final name in exportableBoxNames) {
      if (!Hive.isBoxOpen(name)) continue;
      final box = Hive.box(name);
      await box.clear();
      final entries = boxes[name] as Map<String, dynamic>?;
      if (entries == null) continue;
      for (final entry in entries.entries) {
        await box.put(entry.key, entry.value);
      }
    }
    return true;
  }
}
