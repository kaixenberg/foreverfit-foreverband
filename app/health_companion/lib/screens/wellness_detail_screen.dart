import 'package:flutter/material.dart';

import '../models/wellness_snapshot.dart';

/// Explains the Dashboard's Wellness score — what it is, why it's what it
/// is right now, and which specific signals are driving it. The
/// score-plus-reasoning layout is the one idea deliberately borrowed from
/// OpenVitals' Daily Readiness screen (reimplemented here in Dart from
/// scratch, no code copied — OpenVitals is AGPL-3.0).
class WellnessDetailScreen extends StatelessWidget {
  const WellnessDetailScreen({super.key, required this.snapshot});

  final WellnessSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final score = snapshot.score;

    return Scaffold(
      appBar: AppBar(title: const Text('Wellness')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          snapshot.headline,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      if (score != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Wellness',
                                style: Theme.of(context).textTheme.bodySmall),
                            Text(
                              '$score/100',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(snapshot.summary,
                      style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (snapshot.factors.isNotEmpty) ...[
            Text('Signals', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final factor in snapshot.factors) _FactorRow(factor: factor),
          ],
          const SizedBox(height: 8),
          Text(
            'A transparent formula, not a trained model — starts at 100 and '
            'deducts per signal currently out of range. See ARCHITECTURE.md '
            'for the exact weights.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _FactorRow extends StatelessWidget {
  const _FactorRow({required this.factor});

  final WellnessFactor factor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = factor.warn ? scheme.error : scheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              factor.warn ? Icons.priority_high_rounded : Icons.check_rounded,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    factor.label,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(factor.detail,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
