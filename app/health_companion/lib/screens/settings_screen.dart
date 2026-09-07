import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../disaster/hazard_type.dart';
import '../domain/emergency_workflow_service.dart';
import '../storage/emergency_contact_store.dart';
import 'imminent_warning_screen.dart';
import 'scan_connect_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emergencyNumberController = TextEditingController();
  bool _prefilled = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emergencyNumberController.dispose();
    super.dispose();
  }

  void _prefillOnce(EmergencyContactStore store) {
    if (_prefilled) return;
    _prefilled = true;
    _nameController.text = store.contactName;
    _phoneController.text = store.contactPhone;
    _emergencyNumberController.text = store.customEmergencyNumber;
  }

  Future<void> _confirmDisableMockMode(EmergencyContactStore store) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn off test mode?'),
        content: const Text(
          'With test mode off, a real fall or manual SOS will place a REAL '
          'phone call to emergency services, REAL calls to your emergency '
          'contact, and may send a REAL SMS. Only turn this off when you '
          'mean it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Turn off test mode'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await store.setMockMode(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactStore = context.watch<EmergencyContactStore>();
    final workflow = context.watch<EmergencyWorkflowService>();
    _prefillOnce(contactStore);

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
          const SizedBox(height: 16),
          Text('Emergency contact',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Called automatically (with a spoken summary) after a fall or '
            'manual SOS, following the emergency-services call. See '
            'ARCHITECTURE.md for how this works and its platform limits.',
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
            onPressed: () async {
              await contactStore.saveContact(
                name: _nameController.text,
                phone: _phoneController.text,
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Emergency contact saved')),
              );
            },
            child: const Text('Save contact'),
          ),
          const SizedBox(height: 24),
          Text('Emergency number',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            "Leave blank to auto-detect your region's emergency number "
            '(falls back to 112). Set this only if auto-detection is wrong '
            'for your device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emergencyNumberController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Custom emergency number (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => contactStore
                .setCustomEmergencyNumber(_emergencyNumberController.text),
            child: const Text('Save emergency number'),
          ),
          const SizedBox(height: 24),
          Text('Test mode', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            contactStore.mockMode
                ? 'On — a triggered emergency simulates calls/SMS instead of '
                    'placing real ones. Safe to leave on for demos.'
                : 'OFF — a triggered emergency will place REAL calls and may '
                    'send a REAL SMS.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: contactStore.mockMode
                      ? null
                      : Theme.of(context).colorScheme.error,
                  fontWeight: contactStore.mockMode ? null : FontWeight.bold,
                ),
          ),
          SwitchListTile(
            title: const Text('Test mode (simulate calls/SMS)'),
            value: contactStore.mockMode,
            onChanged: (value) {
              if (value) {
                contactStore.setMockMode(true);
              } else {
                _confirmDisableMockMode(contactStore);
              }
            },
          ),
          if (contactStore.mockMode) ...[
            const SizedBox(height: 4),
            Text('Simulated contact answers on attempt:',
                style: Theme.of(context).textTheme.bodySmall),
            Wrap(
              spacing: 8,
              children: [
                for (final n in [1, 2, 3, 4, 5])
                  ChoiceChip(
                    label: Text('$n'),
                    selected: contactStore.mockAnswerOnAttempt == n,
                    onSelected: (_) => contactStore.setMockAnswerOnAttempt(n),
                  ),
                ChoiceChip(
                  label: const Text('Never'),
                  selected: contactStore.mockAnswerOnAttempt == null,
                  onSelected: (_) => contactStore.setMockAnswerOnAttempt(null),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: workflow.isActive
                ? null
                : () => workflow.start(
                      triggerReason: 'this is a preview — no real emergency '
                          'was detected',
                      forceMock: true,
                    ),
            child: const Text('Preview emergency workflow'),
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
