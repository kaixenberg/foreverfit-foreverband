import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../storage/app_settings_store.dart';

/// Scoped to the one place the app currently has more than one source
/// for the same reading — ambient temperature/humidity/pressure
/// (wearable BME280 vs. online weather). See ARCHITECTURE.md: everything
/// else (heart rate/SpO2/body temp, GPS) has exactly one source today,
/// so there's nothing else to prioritize yet.
class SensorPrecedenceScreen extends StatelessWidget {
  const SensorPrecedenceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsStore>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensor precedence'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Reset to default',
            onPressed: () => settings.resetAmbientSourcePreference(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'When both sources are available, which one should the '
            'Ambient temp/Humidity/Pressure cards use?',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          RadioGroup<AmbientSourcePreference>(
            groupValue: settings.ambientSourcePreference,
            onChanged: (v) {
              if (v != null) settings.setAmbientSourcePreference(v);
            },
            child: Column(
              children: [
                RadioListTile<AmbientSourcePreference>(
                  title: const Text('Prefer wearable sensor'),
                  subtitle: const Text(
                      'Falls back to online weather if disconnected.'),
                  value: AmbientSourcePreference.preferWearable,
                ),
                RadioListTile<AmbientSourcePreference>(
                  title: const Text('Prefer online weather'),
                  subtitle: const Text(
                      'Falls back to the wearable sensor if offline.'),
                  value: AmbientSourcePreference.preferOnline,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
