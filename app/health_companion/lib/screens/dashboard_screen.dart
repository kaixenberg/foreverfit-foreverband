import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/ble_service.dart';
import '../ml/fall_detector_service.dart';
import '../storage/history_store.dart';
import '../widgets/metric_card.dart';
import 'scan_connect_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    final fallDetector = context.watch<FallDetectorService>();
    final history = context.read<HistoryStore>();
    final connected = ble.status == ConnectionStatus.connected;

    final vitals = ble.latestVitals;
    final env = ble.latestEnv;

    final heartRate = vitals?.heartRate ?? 0;
    final spo2 = vitals?.spo2 ?? 0;
    final bodyTemp = vitals?.bodyTempC ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Dashboard'),
        actions: [
          IconButton(
            icon: Icon(connected ? Icons.bluetooth_disabled : Icons.bluetooth_searching),
            tooltip: connected ? 'Disconnect' : 'Connect wearable',
            onPressed: connected
                ? () => ble.disconnect()
                : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ScanConnectScreen()),
                    ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (fallDetector.alertActive) _FallAlertBanner(fallDetector: fallDetector),
          if (!connected) _ConnectWearableBanner(),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.6,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              MetricCard(
                label: 'Heart rate',
                value: vitals == null ? '--' : heartRate.toStringAsFixed(0),
                unit: 'bpm',
                icon: Icons.favorite,
                warn: vitals != null && (heartRate < 50 || heartRate > 120),
              ),
              MetricCard(
                label: 'SpO2',
                value: vitals == null ? '--' : spo2.toStringAsFixed(0),
                unit: '%',
                icon: Icons.bloodtype,
                warn: vitals != null && spo2 < 92 && spo2 > 0,
              ),
              MetricCard(
                label: 'Body temp',
                value: vitals == null ? '--' : bodyTemp.toStringAsFixed(1),
                unit: '°C',
                icon: Icons.thermostat,
                warn: vitals != null && (bodyTemp > 37.8 || bodyTemp < 35.5),
              ),
              MetricCard(
                label: 'Ambient temp',
                value: env == null ? '--' : env.ambientTempC.toStringAsFixed(1),
                unit: '°C',
                icon: Icons.wb_sunny_outlined,
                warn: env != null && env.ambientTempC > 40,
              ),
              MetricCard(
                label: 'Humidity',
                value: env == null ? '--' : env.humidity.toStringAsFixed(0),
                unit: '%',
                icon: Icons.water_drop_outlined,
              ),
              MetricCard(
                label: 'Pressure',
                value: env == null ? '--' : env.pressureHPa.toStringAsFixed(0),
                unit: 'hPa',
                icon: Icons.speed,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Heart rate — recent', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: _HeartRateSparkline(history: history),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of bouncing the user to the scan screen when no wearable
/// is connected — Dashboard, Map, and Health Log should all stay reachable
/// without one (fall detection already works phone-only).
class _ConnectWearableBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.watch_outlined),
        title: const Text('Wearable not connected'),
        subtitle: const Text('Vitals and environment readings need the wearable.'),
        trailing: FilledButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ScanConnectScreen()),
          ),
          child: const Text('Connect'),
        ),
      ),
    );
  }
}

/// Stays open once a fall is detected regardless of what the live model
/// output does afterward — only "I'm OK" or the emergency-call timeout
/// clears it. See FallDetectorService for the latching logic.
class _FallAlertBanner extends StatelessWidget {
  const _FallAlertBanner({required this.fallDetector});

  final FallDetectorService fallDetector;

  @override
  Widget build(BuildContext context) {
    final onError = Theme.of(context).colorScheme.onErrorContainer;
    final message = fallDetector.isCalling
        ? '🚨 Calling emergency contact...'
        : 'Possible fall detected'
            '${fallDetector.secondsUntilCall != null ? ' — calling emergency contact in ${fallDetector.secondsUntilCall}s' : ''}';

    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: onError),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: onError, fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton(
              onPressed: () => fallDetector.dismissAlert(),
              child: const Text("I'm OK"),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeartRateSparkline extends StatelessWidget {
  const _HeartRateSparkline({required this.history});

  final HistoryStore history;

  @override
  Widget build(BuildContext context) {
    final recent = history.recentVitals(limit: 60);
    if (recent.isEmpty) {
      return const Center(child: Text('Waiting for data...'));
    }

    final spots = <FlSpot>[
      for (var i = 0; i < recent.length; i++)
        FlSpot(i.toDouble(), (recent[i]['heartRate'] as num).toDouble()),
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
            dotData: const FlDotData(show: false),
            color: Theme.of(context).colorScheme.primary,
            barWidth: 3,
          ),
        ],
      ),
    );
  }
}
