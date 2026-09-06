import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/ble_service.dart';
import '../storage/history_store.dart';
import '../widgets/metric_card.dart';
import 'scan_connect_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    final history = context.read<HistoryStore>();

    if (ble.status != ConnectionStatus.connected) {
      // Wearable dropped the connection — bounce back to the scan screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ScanConnectScreen()),
        );
      });
    }

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
            icon: const Icon(Icons.bluetooth_disabled),
            tooltip: 'Disconnect',
            onPressed: () => ble.disconnect(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
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
