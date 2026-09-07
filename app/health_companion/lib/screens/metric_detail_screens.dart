import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/ble_service.dart';
import '../domain/units.dart';
import '../models/metric_point.dart';
import '../services/step_counter_service.dart';
import '../storage/app_settings_store.dart';
import '../storage/health_log_store.dart';
import '../storage/history_store.dart';
import '../storage/metrics_store.dart';
import '../theme/app_theme.dart';
import '../widgets/log_value_dialog.dart';
import 'metric_history_screen.dart';

/// Converts a metric-valued history into the display unit — storage
/// stays metric everywhere, only the chart/log dialog sees the
/// converted numbers.
List<MetricPoint> _convert(
        List<MetricPoint> points, UnitValue Function(double) formatter) =>
    [
      for (final p in points)
        MetricPoint(at: p.at, value: formatter(p.value).value)
    ];

/// Thin per-metric wiring around the shared MetricHistoryScreen — each of
/// these just supplies the right data source and log action, all the
/// actual chart/stats/period-selector logic lives in one place.

class WeightHistoryScreen extends StatelessWidget {
  const WeightHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final metrics = context.watch<MetricsStore>();
    final unitSystem = resolveEffectiveUnitSystem(
        context.watch<AppSettingsStore>().unitSystem);
    final unit = formatWeightKg(0, unitSystem).unit;
    return MetricHistoryScreen(
      title: 'Weight',
      unit: unit,
      points: _convert(metrics.historyOfType('weight'),
          (v) => formatWeightKg(v, unitSystem)),
      accentColor: AppTheme.accentCoral,
      logAction: FilledButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Log weight'),
        onPressed: () async {
          final value = await showLogValueDialog(
              context: context, title: 'Log weight', unit: unit);
          if (value != null) {
            metrics.addWeightKg(parseWeightToKg(value, unitSystem));
          }
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
    final unitSystem = resolveEffectiveUnitSystem(
        context.watch<AppSettingsStore>().unitSystem);
    final unit = formatHeightCm(0, unitSystem).unit;
    return MetricHistoryScreen(
      title: 'Height',
      unit: unit,
      points: _convert(metrics.historyOfType('height'),
          (v) => formatHeightCm(v, unitSystem)),
      accentColor: AppTheme.accentPurple,
      logAction: FilledButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Log height'),
        onPressed: () async {
          final value = await showLogValueDialog(
              context: context, title: 'Log height', unit: unit);
          if (value != null) {
            metrics.addHeightCm(parseHeightToCm(value, unitSystem));
          }
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
      accentColor: AppTheme.accentTeal,
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

  // Always logged in mL regardless of display unit — quick-add chips are a
  // fixed, well-known set of round numbers, not something worth converting.
  static const _quickAddMl = [100, 250, 500];

  @override
  Widget build(BuildContext context) {
    final metrics = context.watch<MetricsStore>();
    final unitSystem = resolveEffectiveUnitSystem(
        context.watch<AppSettingsStore>().unitSystem);
    // hydrationDailyTotals() already returns liters (mL / 1000) — convert
    // back to mL first so formatHydrationMl (which expects mL) is correct.
    final unit = formatHydrationMl(0, unitSystem).unit;
    return MetricHistoryScreen(
      title: 'Hydration',
      unit: unit,
      points: _convert(metrics.hydrationDailyTotals(),
          (litres) => formatHydrationMl(litres * 1000, unitSystem)),
      accentColor: AppTheme.accentBlue,
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
      accentColor: AppTheme.accentGreen,
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
      accentColor: AppTheme.accentPink,
    );
  }
}

class BloodPressureHistoryScreen extends StatelessWidget {
  const BloodPressureHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final log = context.watch<HealthLogStore>();
    return MetricHistoryScreen(
      title: 'Blood pressure',
      unit: 'mmHg',
      points: log.bloodPressureSystolicHistory(),
      secondaryPoints: log.bloodPressureDiastolicHistory(),
      secondaryLabel: 'Diastolic',
      accentColor: AppTheme.accentCoral,
      secondaryColor: AppTheme.accentBlue,
      logAction: FilledButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Log blood pressure'),
        onPressed: () async {
          final result = await showBloodPressureDialog(context: context);
          if (result != null) log.addBloodPressure(result.$1, result.$2);
        },
      ),
    );
  }
}

class BloodGlucoseHistoryScreen extends StatelessWidget {
  const BloodGlucoseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final log = context.watch<HealthLogStore>();
    return MetricHistoryScreen(
      title: 'Blood glucose',
      unit: 'mg/dL',
      points: log.glucoseHistory(),
      accentColor: AppTheme.accentPurple,
      logAction: FilledButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Log blood glucose'),
        onPressed: () async {
          final value = await showLogValueDialog(
              context: context, title: 'Log blood glucose', unit: 'mg/dL');
          if (value != null) log.addGlucose(value);
        },
      ),
    );
  }
}

class InsulinHistoryScreen extends StatelessWidget {
  const InsulinHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final log = context.watch<HealthLogStore>();
    return MetricHistoryScreen(
      title: 'Insulin',
      unit: 'units',
      points: log.insulinDoseHistory(),
      accentColor: AppTheme.accentTeal,
      logAction: FilledButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Log insulin dose'),
        onPressed: () async {
          final result = await showInsulinDialog(context: context);
          if (result != null) log.addInsulin(result.$1, result.$2);
        },
      ),
    );
  }
}

class SleepHistoryScreen extends StatelessWidget {
  const SleepHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final log = context.watch<HealthLogStore>();
    return MetricHistoryScreen(
      title: 'Sleep',
      unit: 'hrs',
      points: log.sleepHistory(),
      accentColor: AppTheme.accentBlue,
      logAction: FilledButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Log sleep'),
        onPressed: () async {
          final value = await showLogValueDialog(
              context: context, title: 'Log sleep duration', unit: 'hrs');
          if (value != null) log.addSleep(value);
        },
      ),
    );
  }
}
