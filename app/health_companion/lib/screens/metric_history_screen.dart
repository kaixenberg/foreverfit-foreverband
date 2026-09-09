import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/metric_point.dart';

enum _Period { week, month, threeMonths, all, custom }

/// One entry ready to show in the editable "Recent entries" list — [key]
/// identifies it back to the store (an opaque Hive box key) for the
/// edit/delete callbacks, [display] is the already-unit-formatted string
/// (e.g. "72.4 kg", "120/80 mmHg").
class LoggedEntry {
  const LoggedEntry(
      {required this.key, required this.at, required this.display});

  final dynamic key;
  final DateTime at;
  final String display;
}

/// Generic timestamped-metric chart + stats screen — one shared
/// implementation reused for every metric (weight, height, body fat,
/// hydration, steps, heart rate) rather than a bespoke screen per
/// metric. Period selector (with a custom date-range picker), an
/// avg/range/change summary, an interactive chart with a linear trend
/// line, and a statistics grid — the layout is the one idea taken from
/// OpenVitals' per-metric chart screens, reimplemented from scratch here
/// (AGPL, see ARCHITECTURE.md — no code copied).
class MetricHistoryScreen extends StatefulWidget {
  const MetricHistoryScreen({
    super.key,
    required this.title,
    required this.unit,
    required this.points,
    this.logAction,
    this.accentColor,
    this.secondaryPoints,
    this.secondaryLabel,
    this.secondaryColor,
    this.entries,
    this.onEditEntry,
    this.onDeleteEntry,
  });

  final String title;
  final String unit;
  final List<MetricPoint> points;

  /// Shown above the period selector when the metric supports adding a
  /// new entry (weight/height/body-fat's "Log" button, hydration's
  /// quick-add chips) — null for read-only metrics like steps or heart
  /// rate.
  final Widget? logAction;

  /// Line/dot color — defaults to the theme's primary color if omitted.
  final Color? accentColor;

  /// A second series plotted alongside the primary one — only used by
  /// blood pressure (systolic as the primary series, diastolic here).
  /// The summary/statistics cards still describe the primary series only
  /// (a genuinely symmetric two-metric layout would roughly double this
  /// screen's size for one caller); the chart legend and a one-line
  /// average note are what represent the second series.
  final List<MetricPoint>? secondaryPoints;
  final String? secondaryLabel;
  final Color? secondaryColor;

  /// Individually editable/deletable entries, newest first — null for
  /// metrics that don't support user input at all (steps, heart rate,
  /// BMI, body fat), which show the chart/stats only, same as before.
  final List<LoggedEntry>? entries;

  /// Opens whatever edit UI the caller wants (typically the same dialog
  /// used to log a new entry, pre-filled) and applies the change to the
  /// store. Required whenever [entries] is given.
  final Future<void> Function(LoggedEntry entry)? onEditEntry;

  /// Deletes the entry from the store. The confirmation prompt itself is
  /// handled here, not by callers, so every metric gets the same "are you
  /// sure" behavior for free. Required whenever [entries] is given.
  final Future<void> Function(LoggedEntry entry)? onDeleteEntry;

  @override
  State<MetricHistoryScreen> createState() => _MetricHistoryScreenState();
}

class _MetricHistoryScreenState extends State<MetricHistoryScreen> {
  _Period _period = _Period.all;
  DateTimeRange? _customRange;

  DateTime get _rangeStart {
    final now = DateTime.now();
    switch (_period) {
      case _Period.week:
        return now.subtract(const Duration(days: 7));
      case _Period.month:
        return now.subtract(const Duration(days: 30));
      case _Period.threeMonths:
        return now.subtract(const Duration(days: 90));
      case _Period.all:
        return DateTime.fromMillisecondsSinceEpoch(0);
      case _Period.custom:
        return _customRange?.start ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  DateTime get _rangeEnd {
    if (_period == _Period.custom && _customRange != null) {
      // Include the whole end day.
      return _customRange!.end.add(const Duration(days: 1));
    }
    return DateTime.now().add(const Duration(minutes: 1));
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final earliest = widget.points.isEmpty
        ? now.subtract(const Duration(days: 365))
        : widget.points.first.at;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: earliest.isBefore(now)
          ? earliest
          : now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: _customRange,
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _period = _Period.custom;
      });
    }
  }

  Future<void> _confirmDelete(LoggedEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text('This removes the ${widget.title.toLowerCase()} entry '
            'from ${DateFormat.yMMMd().add_jm().format(entry.at)}. '
            'This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onDeleteEntry!(entry);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.points
        .where((p) => !p.at.isBefore(_rangeStart) && p.at.isBefore(_rangeEnd))
        .toList();
    final secondaryFiltered = widget.secondaryPoints
        ?.where((p) => !p.at.isBefore(_rangeStart) && p.at.isBefore(_rangeEnd))
        .toList();
    final filteredEntries = widget.entries
        ?.where((e) => !e.at.isBefore(_rangeStart) && e.at.isBefore(_rangeEnd))
        .toList();
    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;
    final secondaryAccent = widget.secondaryColor ?? Colors.blueGrey;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.title} history')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.logAction != null) ...[
            widget.logAction!,
            const SizedBox(height: 16),
          ],
          _TimePeriodCard(
            period: _period,
            customRange: _customRange,
            onSelect: (p) => setState(() => _period = p),
            onCustomRange: _pickCustomRange,
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text('No entries in this range yet.')),
            )
          else ...[
            _SummaryRow(points: filtered, unit: widget.unit),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                child: Column(
                  children: [
                    if (widget.secondaryLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _LegendDot(color: accent, label: widget.title),
                            const SizedBox(width: 16),
                            _LegendDot(
                              color: secondaryAccent,
                              label: widget.secondaryLabel!,
                            ),
                          ],
                        ),
                      ),
                    SizedBox(
                      height: 220,
                      child: _Chart(
                        points: filtered,
                        unit: widget.unit,
                        color: accent,
                        secondaryPoints: secondaryFiltered,
                        secondaryColor: secondaryAccent,
                      ),
                    ),
                    if (secondaryFiltered != null &&
                        secondaryFiltered.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${widget.secondaryLabel} avg: '
                          '${(secondaryFiltered.map((p) => p.value).reduce((a, b) => a + b) / secondaryFiltered.length).toStringAsFixed(1)} ${widget.unit}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _StatisticsCard(points: filtered, unit: widget.unit),
          ],
          if (filteredEntries != null && filteredEntries.isNotEmpty) ...[
            const SizedBox(height: 16),
            _EntriesCard(
              entries: filteredEntries,
              onEdit: widget.onEditEntry!,
              onDelete: _confirmDelete,
            ),
          ],
        ],
      ),
    );
  }
}

class _EntriesCard extends StatelessWidget {
  const _EntriesCard({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
  });

  final List<LoggedEntry> entries;
  final Future<void> Function(LoggedEntry entry) onEdit;
  final Future<void> Function(LoggedEntry entry) onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.list_alt,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Entries',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            for (final entry in entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.display),
                subtitle: Text(DateFormat.yMMMd().add_jm().format(entry.at)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit',
                      onPressed: () => onEdit(entry),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () => onDelete(entry),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TimePeriodCard extends StatelessWidget {
  const _TimePeriodCard({
    required this.period,
    required this.customRange,
    required this.onSelect,
    required this.onCustomRange,
  });

  final _Period period;
  final DateTimeRange? customRange;
  final ValueChanged<_Period> onSelect;
  final VoidCallback onCustomRange;

  static const _presets = {
    _Period.week: 'Last 7 Days',
    _Period.month: 'Last Month',
    _Period.threeMonths: 'Last 3 Months',
    _Period.all: 'All Time',
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Time Period',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in _presets.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: period == entry.key,
                    onSelected: (_) => onSelect(entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range_outlined),
              label: Text(
                period == _Period.custom && customRange != null
                    ? '${DateFormat.MMMd().format(customRange!.start)} – '
                        '${DateFormat.MMMd().format(customRange!.end)}'
                    : 'Custom Range',
              ),
              onPressed: onCustomRange,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.points, required this.unit});

  final List<MetricPoint> points;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final values = points.map((p) => p.value);
    final avg = values.reduce((a, b) => a + b) / values.length;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final change = points.last.value - points.first.value;
    final changeColor = change == 0
        ? null
        : (change > 0 ? Colors.green.shade600 : Colors.red.shade600);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  icon: Icons.arrow_forward,
                  label: 'Avg',
                  value: '${avg.toStringAsFixed(1)} $unit',
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _SummaryTile(
                  icon: Icons.straighten,
                  label: 'Range',
                  value:
                      '${min.toStringAsFixed(1)} – ${max.toStringAsFixed(1)}',
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _SummaryTile(
                  icon: change >= 0 ? Icons.trending_up : Icons.trending_down,
                  label: 'Change',
                  value:
                      '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)} $unit',
                  color: changeColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon,
            size: 16, color: color ?? Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          value,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800, color: color),
        ),
      ],
    );
  }
}

class _StatisticsCard extends StatelessWidget {
  const _StatisticsCard({required this.points, required this.unit});

  final List<MetricPoint> points;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final values = points.map((p) => p.value);
    final avg = values.reduce((a, b) => a + b) / values.length;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Statistics',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatBox(
                    icon: Icons.arrow_forward,
                    label: 'Average',
                    value: '${avg.toStringAsFixed(1)} $unit',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatBox(
                    icon: Icons.donut_large_outlined,
                    label: 'Total Entries',
                    value: '${points.length}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatBox(
                    icon: Icons.arrow_downward,
                    iconColor: Colors.blue.shade400,
                    label: 'Minimum',
                    value: '${min.toStringAsFixed(1)} $unit',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatBox(
                    icon: Icons.arrow_upward,
                    iconColor: Colors.orange.shade400,
                    label: 'Maximum',
                    value: '${max.toStringAsFixed(1)} $unit',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 16,
              color: iconColor ?? Theme.of(context).colorScheme.primary),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({
    required this.points,
    required this.unit,
    required this.color,
    this.secondaryPoints,
    this.secondaryColor,
  });

  final List<MetricPoint> points;
  final String unit;
  final Color color;
  final List<MetricPoint>? secondaryPoints;
  final Color? secondaryColor;

  /// Simple least-squares linear regression, endpoints only — the
  /// dashed "overall direction" line behind the real data line.
  List<FlSpot> _trendSpots(List<FlSpot> spots) {
    if (spots.length < 2) return const [];
    final n = spots.length;
    final sumX = spots.fold(0.0, (s, p) => s + p.x);
    final sumY = spots.fold(0.0, (s, p) => s + p.y);
    final sumXY = spots.fold(0.0, (s, p) => s + p.x * p.y);
    final sumXX = spots.fold(0.0, (s, p) => s + p.x * p.x);
    final denom = n * sumXX - sumX * sumX;
    if (denom == 0) return const [];
    final slope = (n * sumXY - sumX * sumY) / denom;
    final intercept = (sumY - slope * sumX) / n;
    return [
      FlSpot(spots.first.x, slope * spots.first.x + intercept),
      FlSpot(spots.last.x, slope * spots.last.x + intercept),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].value),
    ];
    final secondarySpots = secondaryPoints == null
        ? null
        : [
            for (var i = 0; i < secondaryPoints!.length; i++)
              FlSpot(i.toDouble(), secondaryPoints![i].value),
          ];
    final trend = _trendSpots(spots);
    final scheme = Theme.of(context).colorScheme;
    final maxIndex = (points.length - 1).clamp(1, 1 << 30);

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          horizontalInterval: null,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: scheme.outline.withValues(alpha: 0.15)),
          drawVerticalLine: false,
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(0),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: (maxIndex / 3).clamp(1, double.infinity),
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= points.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat.Md().format(points[i].at),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
              if (spot.bar.dashArray != null) return null; // the trend line
              final isSecondary =
                  secondarySpots != null && spot.bar.color == secondaryColor;
              final point = isSecondary
                  ? secondaryPoints![spot.spotIndex]
                  : points[spot.spotIndex];
              return LineTooltipItem(
                '${point.value.toStringAsFixed(1)} $unit\n'
                '${DateFormat.yMMMd().format(point.at)}',
                TextStyle(
                    color: scheme.onInverseSurface,
                    fontWeight: FontWeight.bold),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: color,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(radius: 3, color: color, strokeWidth: 0),
            ),
            belowBarData:
                BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
          ),
          if (trend.isNotEmpty)
            LineChartBarData(
              spots: trend,
              isCurved: false,
              color: scheme.outline,
              barWidth: 1.5,
              dashArray: const [6, 4],
              dotData: const FlDotData(show: false),
            ),
          if (secondarySpots != null && secondarySpots.isNotEmpty)
            LineChartBarData(
              spots: secondarySpots,
              isCurved: true,
              curveSmoothness: 0.25,
              color: secondaryColor,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                  radius: 3,
                  color: secondaryColor ?? scheme.secondary,
                  strokeWidth: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
