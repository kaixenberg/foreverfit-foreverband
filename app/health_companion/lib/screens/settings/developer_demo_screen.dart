import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../disaster/hazard_type.dart';
import '../../domain/emergency_workflow_service.dart';
import '../../storage/emergency_contact_store.dart';
import '../imminent_warning_screen.dart';

/// Test mode + on-demand previews for both full-screen alert flows —
/// grouped here, out of the everyday settings flow, per "categorize
/// everything... including the demos".
class DeveloperDemoScreen extends StatelessWidget {
  const DeveloperDemoScreen({super.key});

  Future<void> _confirmDisableMockMode(
      BuildContext context, EmergencyContactStore store) async {
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

    return Scaffold(
      appBar: AppBar(title: const Text('Developer / demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                _confirmDisableMockMode(context, contactStore);
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
