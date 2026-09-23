import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ble/ble_service.dart';
import '../../disaster/hazard_type.dart';
import '../../domain/demo_escalation_trigger.dart';
import '../../domain/emergency_workflow_service.dart';
import '../../services/notification_service.dart';
import '../../storage/emergency_contact_store.dart';
import '../../storage/watch_settings_store.dart';
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

  Future<void> _setIgnoreBodyTempContactCheck(
      BuildContext context, bool value) async {
    final store = context.read<WatchSettingsStore>();
    await store
        .update(store.settings.copyWith(ignoreBodyTempContactCheck: value));
    if (!context.mounted) return;
    await context.read<BleService>().syncWatchSettings();
  }

  @override
  Widget build(BuildContext context) {
    final contactStore = context.watch<EmergencyContactStore>();
    final workflow = context.watch<EmergencyWorkflowService>();
    final watchSettings = context.watch<WatchSettingsStore>().settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Developer / demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Body-temp contact check',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            watchSettings.ignoreBodyTempContactCheck
                ? 'OFF — body temp is reported without confirming '
                    'finger/wrist contact first, e.g. when the SpO2 sensor '
                    'is unavailable. The low/high body-temp warning is '
                    'disabled while this is on, since an unverified reading '
                    "could just be the watch lying on a table — you'll "
                    'still see the raw number, just no warning from it.'
                : 'ON (default) — body temp only counts as a real reading '
                    'once the MAX30101 also detects finger/wrist contact, '
                    'same signal HR/SpO2 already use, plus a 1-minute '
                    "settle time after connecting for the DS18B20 to reach "
                    "the wrist's temperature. Prevents a false low/high "
                    'body-temp warning from a watch that isn\'t being worn.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          SwitchListTile(
            title: const Text('Ignore body-temp contact check'),
            subtitle: const Text(
                'Also disables the low/high body-temp warning while on.'),
            value: watchSettings.ignoreBodyTempContactCheck,
            onChanged: (value) =>
                _setIgnoreBodyTempContactCheck(context, value),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () =>
                context.read<NotificationService>().showMedicationReminder(
                      id: NotificationService.medicationReminderIdBase - 1,
                      title: 'Test medication reminder',
                      body: "If you see this, medication reminders can post — "
                          "MedicationReminderService's own 20s clock poll (see "
                          'its class doc) drives real ones the same way.',
                    ),
            child: const Text('Send test medication reminder now'),
          ),
          const SizedBox(height: 4),
          Text(
            'Fires immediately on the same channel a real dose-time '
            'reminder uses — a quick sanity check that notifications from '
            'this channel actually post on this device/OS build.',
            style: Theme.of(context).textTheme.bodySmall,
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
          Text('Lock-screen SOS escalation (demo)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Waits 10 seconds (watch the logs for a live countdown), then '
            'wakes the screen and shows the SOS screen exactly the way an '
            'unanswered fall alert does — including over the lock screen '
            'if the phone is locked during the wait. Always forced into '
            'test mode: this can never place a real call, and never '
            'touches the real fall-detection flow.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Triggered — wait ~10s for the screen to wake and the '
                    'SOS screen to appear (see logs for the countdown).',
                  ),
                ),
              );
              triggerDemoLockScreenEscalation();
            },
            child: const Text('Trigger lock-screen SOS escalation'),
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
