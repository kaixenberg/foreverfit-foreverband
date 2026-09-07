import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/ble_service.dart';
import '../services/step_counter_service.dart';
import '../storage/history_store.dart';
import '../storage/metrics_store.dart';
import '../widgets/log_value_dialog.dart';
import 'metric_history_screen.dart';

/// Thin per-metric wiring around the shared MetricHistoryScreen — each of
/// these just supplies the right data source and log action, all the
/// actual chart/stats/period-selector logic lives in one place.

class WeightHistoryScreen extends StatelessWidget {
  const WeightHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final metrics = context.watch<MetricsStore>();
    return MetricHistoryScreen(
      title: 'Weight',
      unit: 'kg',
      points: metrics.historyOfType('weight'),
      logAction: FilledButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Log weight'),
        onPressed: () async {
          final value = await showLogValueDialog(
              context: context, title: 'Log weight', unit: 'kg');
          if (value != null) metrics.addWeightKg(value);
        },
      ),
    );
  }
}

class HeightHistoryScreen extends StatelessWidget {
  const HeightHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final metrics = context.watch<MetricsStore>();
    return MetricHistoryScreen(
      title: 'Height',
      unit: 'cm',
      points: metrics.historyOfType('height'),
      logAction: FilledButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Log height'),
        onPressed: () async {
          final value = await showLogValueDialog(
              context: context, title: 'Log height', unit: 'cm');
          if (value != null) metrics.addHeightCm(value);
        },
      ),
    );
  }
}

class BodyFatHistoryScreen extends StatelessWidget {
  const BodyFatHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final metrics = context.watch<MetricsStore>();
    return MetricHistoryScreen(
      title: 'Body fat',
      unit: '%',
      points: metrics.historyOfType('bodyFat'),
      logAction: FilledButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Log body fat'),
        onPressed: () async {
          final value = await showLogValueDialog(
              context: context, title: 'Log body fat', unit: '%');
          if (value != null) metrics.addBodyFatPercent(value);
        },
      ),
    );
  }
}

class HydrationHistoryScreen extends StatelessWidget {
  const HydrationHistoryScreen({super.key});

  static const _quickAddMl = [100, 250, 500];

  @override
  Widget build(BuildContext context) {
    final metrics = context.watch<MetricsStore>();
    return MetricHistoryScreen(
      title: 'Hydration',
      unit: 'L',
      points: metrics.hydrationDailyTotals(),
      logAction: Wrap(
        spacing: 8,
        children: [
          for (final ml in _quickAddMl)
            ActionChip(
              label: Text('+${ml}ml'),
              onPressed: () => metrics.addHydrationMl(ml),
            ),
        ],
      ),
    );
  }
}

class StepsHistoryScreen extends StatelessWidget {
  const StepsHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final steps = context.watch<StepCounterService>();
    return MetricHistoryScreen(
      title: 'Steps',
      unit: 'steps',
      points: steps.dailyHistory(),
    );
  }
}

class HeartRateHistoryScreen extends StatelessWidget {
  const HeartRateHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Watching BleService (not HistoryStore, which isn't itself
    // observable) so this screen keeps updating live while a new vitals
    // reading comes in every ~1s, same as the sparkline it replaced.
    context.watch<BleService>();
    final history = context.read<HistoryStore>();
    return MetricHistoryScreen(
      title: 'Heart rate',
      unit: 'bpm',
      points: history.heartRateHistory(),
    );
  }
}
