import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/ble_service.dart';
import '../ml/activity_classifier_service.dart';
import '../ml/fall_detector_service.dart';
import '../services/baseline_service.dart';
import '../storage/history_store.dart';
import '../utils/heat_index.dart';
import '../widgets/metric_card.dart';
import 'scan_connect_screen.dart';

/// Heart-rate ceiling above which a reading is flagged, conditioned on
/// what the user is currently doing — a fixed threshold can't tell
/// "elevated HR because you're running" from "elevated HR while sitting
/// still," so it either misses real anomalies at rest or false-alarms
/// during exercise. See ARCHITECTURE.md's AI/ML roadmap item 1.
int _heartRateCeiling(Activity? activity) {
  switch (activity) {
    case Activity.running:
      return 180;
    case Activity.walking:
      return 140;
    case Activity.still:
    case null:
      return 120;
  }
}

String _activityLabel(Activity activity) {
  switch (activity) {
    case Activity.still:
      return 'Still';
    case Activity.walking:
      return 'Walking';
    case Activity.running:
      return 'Running';
  }
}

/// Transparent, calibrated formula rather than a trained model — explainable
/// to judges, and there's no labeled "wellness score" training data anyway.
/// Deducts points per concerning signal currently showing; null (not 0)
/// when there's nothing to score yet. See ARCHITECTURE.md's AI/ML roadmap
/// item 4.
int? _wellnessScore({
  required bool hasVitals,
  required bool heartRateWarn,
  required bool spo2Warn,
  required bool bodyTempWarn,
  required bool ambientWarn,
  required bool heatStressWarn,
}) {
  if (!hasVitals) return null;
  var score = 100;
  if (heartRateWarn) score -= 25;
  if (spo2Warn) score -= 30;
  if (bodyTempWarn) score -= 20;
  if (ambientWarn) score -= 10;
  if (heatStressWarn) score -= 15;
  return score.clamp(0, 100);
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    final fallDetector = context.watch<FallDetectorService>();
    final activityClassifier = context.watch<ActivityClassifierService>();
    final baseline = context.watch<BaselineService>();
    final history = context.read<HistoryStore>();
    final connected = ble.status == ConnectionStatus.connected;

    final vitals = ble.latestVitals;
    final env = ble.latestEnv;

    final heartRate = vitals?.heartRate ?? 0;
    final spo2 = vitals?.spo2 ?? 0;
    final bodyTemp = vitals?.bodyTempC ?? 0;
    // The MAX30101 zeroes heartRate/spo2 when it can't see a finger — the
    // OLED already shows "no finger", so the app needs to too, rather
    // than reading a 0 as a genuine (and alarming) vital sign.
    final hasFingerReading = vitals != null && vitals.fingerPresent;
    final heartRateCeiling = _heartRateCeiling(activityClassifier.current);
    final heartRateWarn = hasFingerReading &&
        (heartRate < 50 ||
            heartRate > heartRateCeiling ||
            baseline.isAnomalous(heartRate));
    final spo2Warn = hasFingerReading && spo2 < 92 && spo2 > 0;
    final bodyTempWarn = vitals != null && (bodyTemp > 37.8 || bodyTemp < 35.5);
    final ambientWarn = env != null &&
        heatRiskLevel(heatIndexCelsius(env.ambientTempC, env.humidity)) == HeatRisk.danger;
    final heatStressWarn = env != null &&
        vitals != null &&
        isHeatStressRisk(
          ambientC: env.ambientTempC,
          humidityPercent: env.humidity,
          bodyTempC: bodyTemp,
        );
    final wellnessScore = _wellnessScore(
      hasVitals: vitals != null,
      heartRateWarn: heartRateWarn,
      spo2Warn: spo2Warn,
      bodyTempWarn: bodyTempWarn,
      ambientWarn: ambientWarn,
      heatStressWarn: heatStressWarn,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sos),
            tooltip: 'Manual SOS',
            color: Theme.of(context).colorScheme.error,
            onPressed: fallDetector.alertActive
                ? null
                : () => fallDetector.triggerManualSOS(),
          ),
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
                value: hasFingerReading ? heartRate.toStringAsFixed(0) : '--',
                unit: vitals != null && !hasFingerReading ? 'no finger' : 'bpm',
                icon: Icons.favorite,
                warn: heartRateWarn,
              ),
              MetricCard(
                label: 'SpO2',
                value: hasFingerReading ? spo2.toStringAsFixed(0) : '--',
                unit: vitals != null && !hasFingerReading ? 'no finger' : '%',
                icon: Icons.bloodtype,
                warn: spo2Warn,
              ),
              MetricCard(
                label: 'Body temp',
                value: vitals == null ? '--' : bodyTemp.toStringAsFixed(1),
                unit: '°C',
                icon: Icons.thermostat,
                warn: bodyTempWarn,
              ),
              MetricCard(
                label: 'Ambient temp',
                value: env == null ? '--' : env.ambientTempC.toStringAsFixed(1),
                unit: '°C',
                icon: Icons.wb_sunny_outlined,
                warn: ambientWarn,
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
          Text('Wellness overview', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.1,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              MetricCard(
                label: 'Wellness',
                value: wellnessScore == null ? '--' : wellnessScore.toString(),
                unit: wellnessScore == null ? '' : '/100',
                icon: Icons.favorite_border,
                warn: wellnessScore != null && wellnessScore < 70,
              ),
              MetricCard(
                label: 'Activity',
                value: activityClassifier.current == null
                    ? '--'
                    : _activityLabel(activityClassifier.current!),
                unit: '',
                icon: Icons.directions_walk,
              ),
              MetricCard(
                label: 'Baseline',
                value: baseline.heartRateMean == null
                    ? '--'
                    : baseline.heartRateMean!.toStringAsFixed(0),
                unit: baseline.heartRateMean == null ? '' : 'bpm',
                icon: Icons.show_chart,
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
    final situation = fallDetector.alertSource == AlertSource.manual
        ? 'Manual SOS activated'
        : 'Possible fall detected';
    final message = fallDetector.isCalling
        ? '🚨 Calling emergency contact...'
        : '$situation'
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
