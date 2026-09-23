import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../storage/app_settings_store.dart';

/// Scoped to the 3 insight-engine categories — the full-screen
/// imminent-disaster warning and the fall/SOS countdown are never
/// user-silenceable here; they're the safety-critical path, not a
/// notification preference. See ARCHITECTURE.md.
class WarningChoicesScreen extends StatelessWidget {
  const WarningChoicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('Warning choices')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Choose which categories of in-app suggestion/notification to '
            'receive. This never affects the full-screen disaster warning '
            'or the fall-detection/SOS alert — those always fire.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Vitals & wellness'),
            subtitle: const Text('Heart rate, SpO2, body temperature, blood '
                'pressure, glucose, sleep anomalies.'),
            value: settings.notifyVitals,
            onChanged: (v) => settings.setNotifyVitals(v),
          ),
          SwitchListTile(
            title: const Text('Map & disaster hazards'),
            subtitle: const Text(
                'Air quality, flood/cyclone risk, nearby earthquakes.'),
            value: settings.notifyHazards,
            onChanged: (v) => settings.setNotifyHazards(v),
          ),
          SwitchListTile(
            title: const Text('Tracking reminders'),
            subtitle: const Text('Hydration nudges, and scheduled '
                'medication dose-time reminders.'),
            value: settings.notifyReminders,
            onChanged: (v) => settings.setNotifyReminders(v),
          ),
        ],
      ),
    );
  }
}
