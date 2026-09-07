import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/metric_point.dart';

enum _Period { week, month, all }

/// Generic timestamped-metric chart + stats screen — one shared
/// implementation reused for weight, height, body fat, hydration, and
/// steps, rather than a bespoke screen per metric. The period selector +
/// stats-grid layout is the one idea taken from OpenVitals' per-metric
/// chart screens, reimplemented from scratch here (AGPL, see
/// ARCHITECTURE.md — no code copied).
class MetricHistoryScreen extends StatefulWidget {
  const MetricHistoryScreen({
    super.key,
    required this.title,
    required this.unit,
    required this.points,
    this.logAction,
  });

  final String title;
  final String unit;
  final List<MetricPoint> points;

  /// Shown above the chart when the metric supports adding a new entry
  /// (weight/height/body-fat's "Log" button, hydration's quick-add
  /// chips) — null for read-only metrics like steps.
  final Widget? logAction;

  @override
  State<MetricHistoryScreen> createState() => _MetricHistoryScreenState();
}

class _MetricHistoryScreenState extends State<MetricHistoryScreen> {
  _Period _period = _Period.month;

  @override
  Widget build(BuildContext context) {
    final cutoff = switch (_period) {
      _Period.week => DateTime.now().subtract(const Duration(days: 7)),
      _Period.month => DateTime.now().subtract(const Duration(days: 30)),
      _Period.all => DateTime.fromMillisecondsSinceEpoch(0),
    };
    final filtered = widget.points.where((p) => p.at.isAfter(cutoff)).toList();

    return Scaffold(
      appBar: AppBar(title: Text('${widget.title} history')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.logAction != null) ...[
            widget.logAction!,
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 8,
            children: [
              for (final period in _Period.values)
                ChoiceChip(
                  label: Text(switch (period) {
                    _Period.week => 'Last 7 days',
                    _Period.month => 'Last 30 days',
                    _Period.all => 'All time',
                  }),
                  selected: _period == period,
                  onSelected: (_) => setState(() => _period = period),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('No entries in this range yet.')),
            )
          else ...[
            _StatsRow(points: filtered, unit: widget.unit),
            const SizedBox(height: 16),
            SizedBox(height: 200, child: _Chart(points: filtered)),
            const SizedBox(height: 8),
            Text(
              '${DateFormat.yMMMd().format(filtered.first.at)} — '
              '${DateFormat.yMMMd().format(filtered.last.at)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.points, required this.unit});

  final List<MetricPoint> points;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final values = points.map((p) => p.value);
    final avg = values.reduce((a, b) => a + b) / values.length;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final change = points.last.value - points.first.value;

    return Row(
      children: [
        Expanded(
            child: _StatTile(
                label: 'Average', value: '${avg.toStringAsFixed(1)} $unit')),
        Expanded(
            child: _StatTile(
                label: 'Min', value: '${min.toStringAsFixed(1)} $unit')),
        Expanded(
            child: _StatTile(
                label: 'Max', value: '${max.toStringAsFixed(1)} $unit')),
        Expanded(
          child: _StatTile(
            label: 'Change',
            value:
                '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)} $unit',
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({required this.points});

  final List<MetricPoint> points;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].value),
    ];

    return LineChart(
      LineChartData(
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            dotData: FlDotData(show: points.length <= 20),
            color: Theme.of(context).colorScheme.primary,
            barWidth: 3,
          ),
        ],
      ),
    );
  }
}
