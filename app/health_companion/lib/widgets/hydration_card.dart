import 'package:flutter/material.dart';

import '../storage/metrics_store.dart';
import '../theme/app_theme.dart';

/// Today's water intake with one-tap quick-add chips — logging hydration
/// shouldn't need a whole form.
class HydrationCard extends StatelessWidget {
  const HydrationCard({super.key, required this.metrics});

  final MetricsStore metrics;

  static const _quickAddMl = [100, 250, 500];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalMl = metrics.todayHydrationMl;
    final liters = totalMl / 1000;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.accentBlue.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.local_drink_outlined,
                  size: 20, color: AppTheme.accentBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hydration today',
                      style: Theme.of(context).textTheme.labelLarge),
                  Text(
                    '${liters.toStringAsFixed(2)} L',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final ml in _quickAddMl)
                  ActionChip(
                    backgroundColor: scheme.primaryContainer,
                    label: Text('+${ml}ml'),
                    onPressed: () => metrics.addHydrationMl(ml),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
