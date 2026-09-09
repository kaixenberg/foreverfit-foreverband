import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/ble_service.dart';
import '../domain/body_composition.dart';
import '../domain/units.dart';
import '../models/metric_point.dart';
import '../services/step_counter_service.dart';
import '../storage/app_settings_store.dart';
import '../storage/health_log_store.dart';
import '../storage/history_store.dart';
import '../storage/metrics_store.dart';
import '../storage/user_profile_store.dart';
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
    final rawEntries = metrics.entriesOfType('weight');
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
      entries: [
        for (final e in rawEntries)
          LoggedEntry(
            key: e.key,
            at: e.at,
            display:
                formatWeightKg((e.data['value'] as num).toDouble(), unitSystem)
                    .toStringAsFixed(1),
          ),
      ],
      onEditEntry: (entry) async {
        final currentKg = (rawEntries
                .firstWhere((e) => e.key == entry.key)
                .data['value'] as num)
            .toDouble();
        final value = await showLogValueDialog(
          context: context,
          title: 'Edit weight',
          unit: unit,
          initialValue: formatWeightKg(currentKg, unitSystem).value,
        );
        if (value != null) {
          await metrics.updateBodyMetricEntry(
              entry.key, parseWeightToKg(value, unitSystem));
        }
      },
      onDeleteEntry: (entry) => metrics.deleteBodyMetricEntry(entry.key),
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
    final rawEntries = metrics.entriesOfType('height');
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
      entries: [
        for (final e in rawEntries)
          LoggedEntry(
            key: e.key,
            at: e.at,
            display:
                formatHeightCm((e.data['value'] as num).toDouble(), unitSystem)
                    .toStringAsFixed(1),
          ),
      ],
      onEditEntry: (entry) async {
        final currentCm = (rawEntries
                .firstWhere((e) => e.key == entry.key)
                .data['value'] as num)
            .toDouble();
        final value = await showLogValueDialog(
          context: context,
          title: 'Edit height',
          unit: unit,
          initialValue: formatHeightCm(currentCm, unitSystem).value,
        );
        if (value != null) {
          await metrics.updateBodyMetricEntry(
              entry.key, parseHeightToCm(value, unitSystem));
        }
      },
      onDeleteEntry: (entry) => metrics.deleteBodyMetricEntry(entry.key),
    );
  }
}

class BmiHistoryScreen extends StatelessWidget {
  const BmiHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final metrics = context.watch<MetricsStore>();
    return MetricHistoryScreen(
      title: 'BMI',
      unit: '',
      points: metrics.bmiHistory(),
      accentColor: AppTheme.accentBlue,
      // No log action — BMI is always derived from weight/height, logged
      // from their own cards, never entered directly.
    );
  }
}

/// Body fat is derived from BMI + age + sex (Deurenberg formula, see
/// body_composition.dart) — no longer manually logged. The chart mirrors
/// the shape of the BMI trend, since age/sex are applied uniformly
/// across the whole history rather than changing per point.
class BodyFatHistoryScreen extends StatelessWidget {
  const BodyFatHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final metrics = context.watch<MetricsStore>();
    final profile = context.watch<UserProfileStore>();
    final points = [
      for (final bmiPoint in metrics.bmiHistory())
        if (computeBodyFatPercent(
          bmi: bmiPoint.value,
          dateOfBirth: profile.dateOfBirth,
          sex: profile.sex,
        )
            case final bodyFat?)
          MetricPoint(at: bmiPoint.at, value: bodyFat),
    ];
    return MetricHistoryScreen(
      title: 'Body fat',
      unit: '%',
      points: points,
      accentColor: AppTheme.accentTeal,
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
    final rawEntries = metrics.hydrationEntries();
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
      // Always shown/edited in raw mL, not the display unit — each entry
      // here is one individual log (a quick-add tap), unlike the chart
      // above which plots daily totals; matches the quick-add chips,
      // which are also fixed mL amounts regardless of unit system.
      entries: [
        for (final e in rawEntries)
          LoggedEntry(
            key: e.key,
            at: e.at,
            display: '${e.data['ml']} ml',
          ),
      ],
      onEditEntry: (entry) async {
        final currentMl =
            (rawEntries.firstWhere((e) => e.key == entry.key).data['ml'] as num)
                .toInt();
        final value = await showLogValueDialog(
          context: context,
          title: 'Edit hydration entry',
          unit: 'ml',
          initialValue: currentMl.toDouble(),
        );
        if (value != null) {
          await metrics.updateHydrationEntry(entry.key, value.round());
        }
      },
      onDeleteEntry: (entry) => metrics.deleteHydrationEntry(entry.key),
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

class SpO2HistoryScreen extends StatelessWidget {
  const SpO2HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Watching BleService (not HistoryStore, which isn't itself
    // observable) so this screen keeps updating live while a new vitals
    // reading comes in — same pattern as HeartRateHistoryScreen.
    context.watch<BleService>();
    final history = context.read<HistoryStore>();
    return MetricHistoryScreen(
      title: 'SpO2',
      unit: '%',
      points: history.spo2History(),
      accentColor: AppTheme.accentBlue,
    );
  }
}

class BodyTempHistoryScreen extends StatelessWidget {
  const BodyTempHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<BleService>();
    final history = context.read<HistoryStore>();
    final unitSystem = resolveEffectiveUnitSystem(
        context.watch<AppSettingsStore>().unitSystem);
    final unit = formatTemperatureC(0, unitSystem).unit;
    return MetricHistoryScreen(
      title: 'Body temp',
      unit: unit,
      points: _convert(
          history.bodyTempHistory(), (v) => formatTemperatureC(v, unitSystem)),
      accentColor: AppTheme.accentCoral,
    );
  }
}

class BloodPressureHistoryScreen extends StatelessWidget {
  const BloodPressureHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final log = context.watch<HealthLogStore>();
    final rawEntries = log.bloodPressureEntries();
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
      entries: [
        for (final e in rawEntries)
          LoggedEntry(
            key: e.key,
            at: e.at,
            display: '${e.data['systolic']}/${e.data['diastolic']} mmHg',
          ),
      ],
      onEditEntry: (entry) async {
        final current = rawEntries.firstWhere((e) => e.key == entry.key).data;
        final result = await showBloodPressureDialog(
          context: context,
          title: 'Edit blood pressure',
          initialSystolic: (current['systolic'] as num).toInt(),
          initialDiastolic: (current['diastolic'] as num).toInt(),
        );
        if (result != null) {
          await log.updateBloodPressureEntry(entry.key, result.$1, result.$2);
        }
      },
      onDeleteEntry: (entry) => log.deleteBloodPressureEntry(entry.key),
    );
  }
}

class BloodGlucoseHistoryScreen extends StatelessWidget {
  const BloodGlucoseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final log = context.watch<HealthLogStore>();
    final rawEntries = log.glucoseEntries();
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
      entries: [
        for (final e in rawEntries)
          LoggedEntry(
            key: e.key,
            at: e.at,
            display: '${(e.data['value'] as num).toStringAsFixed(1)} mg/dL',
          ),
      ],
      onEditEntry: (entry) async {
        final current = (rawEntries
                .firstWhere((e) => e.key == entry.key)
                .data['value'] as num)
            .toDouble();
        final value = await showLogValueDialog(
          context: context,
          title: 'Edit blood glucose',
          unit: 'mg/dL',
          initialValue: current,
        );
        if (value != null) await log.updateGlucoseEntry(entry.key, value);
      },
      onDeleteEntry: (entry) => log.deleteGlucoseEntry(entry.key),
    );
  }
}

class InsulinHistoryScreen extends StatelessWidget {
  const InsulinHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final log = context.watch<HealthLogStore>();
    final rawEntries = log.insulinEntries();
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
      entries: [
        for (final e in rawEntries)
          LoggedEntry(
            key: e.key,
            at: e.at,
            display: '${(e.data['dose'] as num).toStringAsFixed(1)} units '
                '(${e.data['type']})',
          ),
      ],
      onEditEntry: (entry) async {
        final current = rawEntries.firstWhere((e) => e.key == entry.key).data;
        final result = await showInsulinDialog(
          context: context,
          title: 'Edit insulin dose',
          initialDose: (current['dose'] as num).toDouble(),
          initialType: current['type'] as String?,
        );
        if (result != null) {
          await log.updateInsulinEntry(entry.key, result.$1, result.$2);
        }
      },
      onDeleteEntry: (entry) => log.deleteInsulinEntry(entry.key),
    );
  }
}

class SleepHistoryScreen extends StatelessWidget {
  const SleepHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final log = context.watch<HealthLogStore>();
    final rawEntries = log.sleepEntries();
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
      entries: [
        for (final e in rawEntries)
          LoggedEntry(
            key: e.key,
            at: e.at,
            display: '${(e.data['hours'] as num).toStringAsFixed(1)} hrs',
          ),
      ],
      onEditEntry: (entry) async {
        final current = (rawEntries
                .firstWhere((e) => e.key == entry.key)
                .data['hours'] as num)
            .toDouble();
        final value = await showLogValueDialog(
          context: context,
          title: 'Edit sleep duration',
          unit: 'hrs',
          initialValue: current,
        );
        if (value != null) await log.updateSleepEntry(entry.key, value);
      },
      onDeleteEntry: (entry) => log.deleteSleepEntry(entry.key),
    );
  }
}
