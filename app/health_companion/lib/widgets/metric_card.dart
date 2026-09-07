import 'package:flutter/material.dart';

/// A stat tile: circular icon badge, label, bold value, and a thin
/// colored accent strip along the bottom — one visual language reused
/// across every dashboard-style grid in the app (see AppTheme).
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.warn = false,
    this.accentColor,
    this.onTap,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final bool warn;

  /// Color for the icon badge and bottom strip when not in a warn state.
  /// Defaults to the theme's primary color.
  final Color? accentColor;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent =
        warn ? scheme.onErrorContainer : (accentColor ?? scheme.primary);

    return Card(
      color: warn ? scheme.errorContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: warn ? 0.25 : 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, size: 16, color: accent),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.labelLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(value,
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(width: 4),
                          Text(unit,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
                height: 4, color: accent.withValues(alpha: warn ? 0.0 : 0.7)),
          ],
        ),
      ),
    );
  }
}
