import 'package:flutter/material.dart';

/// Placeholder — see ARCHITECTURE.md roadmap item 4. Every tile here is a
/// UI stub only; tapping shows what it'll eventually do, nothing is
/// tracked or persisted yet.
class HealthLogScreen extends StatelessWidget {
  const HealthLogScreen({super.key});

  static const _stubs = [
    (
      Icons.monitor_weight_outlined,
      'Weight',
      'Track weight over time with BMI'
    ),
    (Icons.height, 'Height', 'One-time or periodic height entry'),
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
    (Icons.local_drink_outlined, 'Hydration', 'Daily water intake'),
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
            child: Text('Health tracking is coming soon. Planned features:'),
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
