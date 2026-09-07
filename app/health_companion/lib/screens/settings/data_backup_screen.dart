import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/backup_service.dart';

class DataBackupScreen extends StatefulWidget {
  const DataBackupScreen({super.key});

  @override
  State<DataBackupScreen> createState() => _DataBackupScreenState();
}

class _DataBackupScreenState extends State<DataBackupScreen> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final fileName =
          await context.read<BackupService>().exportToPickedFolder();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            fileName == null ? 'Export cancelled' : 'Exported to $fileName'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import backup?'),
        content: const Text(
          'This replaces ALL current data on this device — vitals '
          'history, body metrics, health log, emergency contact, step '
          'history, and profile — with what\'s in the chosen file. This '
          "cannot be undone. Your settings (units, appearance, etc.) "
          "aren't affected.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Replace data'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final backupService = context.read<BackupService>();

    setState(() => _busy = true);
    try {
      final imported = await backupService.importFromPickedFile();
      if (!mounted) return;
      if (imported) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Import complete'),
            content: const Text(
                'Please close and reopen the app to see your restored data.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data export & import')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Export', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Saves everything on this device — vitals history, body '
            'metrics, health log, emergency contact, step history, and '
            'profile — as one JSON file, wherever you choose to save it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.upload_outlined),
            onPressed: _busy ? null : _export,
            label: const Text('Export data'),
          ),
          const SizedBox(height: 24),
          Text('Import', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Replaces all current data with a previously exported file.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.download_outlined),
            onPressed: _busy ? null : _import,
            label: const Text('Import data'),
          ),
          const SizedBox(height: 24),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Exported files are plain text (not encrypted) — store them '
                "somewhere safe. There's no scheduled automatic backup yet "
                '— both encryption and a scheduled backup are on the '
                'roadmap. See ARCHITECTURE.md.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
