import 'package:flutter/material.dart';

/// Remaining health-tracking ideas not yet promoted to real Dashboard
/// widgets — see ARCHITECTURE.md roadmap item 3. Weight/height/body
/// fat/hydration/steps moved to the Dashboard's "Body & activity" section
/// and are real, not stubs; every tile here still is one.
class HealthLogScreen extends StatelessWidget {
  const HealthLogScreen({super.key});

  static const _stubs = [
    (
      Icons.favorite_border,
      'Blood pressure',
      'Log systolic/diastolic readings'
    ),
    (
      Icons.water_drop_outlined,
      'Blood glucose',
      'Track glucose readings over time'
    ),
    (
      Icons.vaccines_outlined,
      'Insulin log',
      'Dose, type, and time of insulin doses'
    ),
    (
      Icons.medication_outlined,
      'Medications',
      'Schedule, dosage, and refill reminders'
    ),
    (Icons.bedtime_outlined, 'Sleep', 'Duration and quality tracking'),
    (
      Icons.badge_outlined,
      'Medical ID',
      'Blood type, allergies, conditions — for responders'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health Log')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child:
                Text('More tracking is coming soon. Weight, height, body fat, '
                    'hydration, and steps are already live on the Dashboard.'),
          ),
          for (final (icon, title, subtitle) in _stubs)
            ListTile(
              leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$title tracking is coming soon')),
              ),
            ),
        ],
      ),
    );
  }
}
