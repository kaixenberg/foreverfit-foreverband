import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../storage/health_log_store.dart';
import '../theme/app_theme.dart';
import 'metric_history_screen.dart';

/// Medications aren't a number to chart — this manages the list (name,
/// dosage, frequency) and lets the user mark today's doses taken.
/// Adherence (doses/day) is the one thing about medications that IS a
/// meaningful trend, so it gets the same MetricHistoryScreen chart
/// everything else does, reachable from here rather than being the
/// screen's main focus.
class MedicationsScreen extends StatelessWidget {
  const MedicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final log = context.watch<HealthLogStore>();
    final medications = log.medications;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.show_chart),
            tooltip: 'Adherence history',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MetricHistoryScreen(
                  title: 'Doses taken',
                  unit: 'doses',
                  points: log.dosesTakenDailyHistory(),
                  accentColor: AppTheme.accentGreen,
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add medication'),
        onPressed: () => _showAddMedicationDialog(context, log),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Text('Doses taken today: ${log.dosesTakenToday}',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (medications.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('No medications added yet.')),
            )
          else
            for (final medication in medications)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.medication_outlined),
                  title: Text(medication.name),
                  subtitle:
                      Text('${medication.dosage} — ${medication.frequency}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check),
                        tooltip: 'Mark dose taken',
                        onPressed: () => log.logDoseTaken(medication.name),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remove',
                        onPressed: () => log.removeMedication(medication.key),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _showAddMedicationDialog(
      BuildContext context, HealthLogStore log) async {
    final nameController = TextEditingController();
    final dosageController = TextEditingController();
    final frequencyController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add medication'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dosageController,
              decoration:
                  const InputDecoration(labelText: 'Dosage (e.g. 500mg)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: frequencyController,
              decoration: const InputDecoration(
                  labelText: 'Frequency (e.g. Twice daily)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty) {
                Navigator.of(context).pop();
                return;
              }
              log.addMedication(
                name: nameController.text.trim(),
                dosage: dosageController.text.trim(),
                frequency: frequencyController.text.trim(),
              );
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
