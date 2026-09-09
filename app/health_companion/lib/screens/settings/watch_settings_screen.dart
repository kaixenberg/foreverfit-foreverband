import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ble/ble_service.dart';
import '../../models/watch_settings.dart';
import '../../storage/watch_settings_store.dart';

/// Customizes the wearable's OLED watch faces from the phone — which
/// face is active, whether they auto-cycle, and the primary face's
/// clock/date formatting. Every change is persisted (WatchSettingsStore)
/// and, if a wearable is currently connected, pushed live over BLE
/// (BleService.syncWatchSettings()) — see health_companion.ino's
/// WatchSettingsPacket handling for how the firmware applies these.
class WatchSettingsScreen extends StatelessWidget {
  const WatchSettingsScreen({super.key});

  Future<void> _apply(BuildContext context, WatchSettings next) async {
    final store = context.read<WatchSettingsStore>();
    await store.update(next);
    if (!context.mounted) return;
    await context.read<BleService>().syncWatchSettings();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WatchSettingsStore>();
    final settings = store.settings;
    final connected = context.select<BleService, bool>(
        (b) => b.status == ConnectionStatus.connected);

    return Scaffold(
      appBar: AppBar(title: const Text('Watch customization')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!connected)
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  "Wearable not connected — changes are saved and will be "
                  'sent the next time it connects.',
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('Watch face', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'The BOOT button on the wearable also switches faces manually '
            'at any time.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          RadioGroup<WatchFace>(
            groupValue: settings.selectedFace,
            onChanged: (v) {
              if (v != null) {
                _apply(context, settings.copyWith(selectedFace: v));
              }
            },
            child: Column(
              children: [
                RadioListTile<WatchFace>(
                  title: const Text('Primary — clock, date, ambient stats'),
                  value: WatchFace.primary,
                ),
                RadioListTile<WatchFace>(
                  title: const Text('Secondary — HR, SpO2, body temp'),
                  value: WatchFace.secondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            title: const Text('Auto-cycle faces'),
            subtitle: const Text(
                'Automatically switch between both faces on a timer.'),
            value: settings.autoCycleEnabled,
            onChanged: (v) =>
                _apply(context, settings.copyWith(autoCycleEnabled: v)),
          ),
          if (settings.autoCycleEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Every'),
                  Expanded(
                    child: Slider(
                      value: settings.autoCycleIntervalSeconds.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11,
                      label: '${settings.autoCycleIntervalSeconds}s',
                      onChanged: (v) => _apply(
                        context,
                        settings.copyWith(autoCycleIntervalSeconds: v.round()),
                      ),
                    ),
                  ),
                  Text('${settings.autoCycleIntervalSeconds}s'),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text('Primary face format',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('24-hour time'),
            subtitle: const Text('Off shows 12-hour time with AM/PM.'),
            value: settings.use24HourFormat,
            onChanged: (v) =>
                _apply(context, settings.copyWith(use24HourFormat: v)),
          ),
          SwitchListTile(
            title: const Text('Show seconds'),
            value: settings.showSeconds,
            onChanged: (v) =>
                _apply(context, settings.copyWith(showSeconds: v)),
          ),
          const SizedBox(height: 8),
          Text('Date format', style: Theme.of(context).textTheme.titleSmall),
          RadioGroup<WatchDateFormat>(
            groupValue: settings.dateFormat,
            onChanged: (v) {
              if (v != null) _apply(context, settings.copyWith(dateFormat: v));
            },
            child: Column(
              children: [
                for (final format in WatchDateFormat.values)
                  RadioListTile<WatchDateFormat>(
                    title: Text(format.label),
                    value: format,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Firmware', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.system_update_outlined),
              title: Text('Check for firmware update'),
              subtitle: Text('Not available yet'),
              enabled: false,
            ),
          ),
        ],
      ),
    );
  }
}
