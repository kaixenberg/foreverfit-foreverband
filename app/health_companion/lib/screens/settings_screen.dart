import 'package:flutter/material.dart';

import '../disaster/hazard_type.dart';
import 'health_log_screen.dart';
import 'imminent_warning_screen.dart';
import 'scan_connect_screen.dart';

/// Placeholder — see ARCHITECTURE.md roadmap item 5 (SOS). The emergency
/// contact form here is a UI stub only: nothing is persisted or wired to
/// FallDetectorService's dummy call yet.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.watch_outlined),
              title: const Text('Wearable'),
              subtitle:
                  const Text('Connect or manage your Health Companion device'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ScanConnectScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.list_alt_outlined),
              title: const Text('Health log'),
              subtitle: const Text(
                  'Blood pressure, glucose, insulin, meds, sleep, Medical ID'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HealthLogScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Emergency contact',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Not saved yet — this is a preview of what SOS escalation will '
            'use once wired up (see ARCHITECTURE.md roadmap).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Contact name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Emergency contacts are coming soon')),
            ),
            child: const Text('Save'),
          ),
          const SizedBox(height: 24),
          Text('Preview disaster warnings',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Shows the full-screen warning that normally appears only when '
            'a hazard crosses the imminent threshold (see ARCHITECTURE.md) — '
            'useful for demos since real conditions rarely cross it live.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final hazard in HazardType.values)
            Card(
              child: ListTile(
                leading: Icon(hazardGuidance[hazard]!.icon),
                title: Text(hazardGuidance[hazard]!.title),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => ImminentWarningScreen(
                      hazards: [hazard],
                      reason: 'Preview — no real threat detected',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
