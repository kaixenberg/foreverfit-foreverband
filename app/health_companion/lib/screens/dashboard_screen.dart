import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/ble_service.dart';
import '../disaster/disaster_service.dart';
import '../domain/body_composition.dart';
import '../domain/emergency_workflow_service.dart';
import '../domain/health_thresholds.dart';
import '../domain/insight_watcher_service.dart';
import '../domain/units.dart';
import '../ml/activity_classifier_service.dart';
import '../ml/fall_detector_service.dart';
import '../models/insight.dart';
import '../models/sensor_reading.dart';
import '../models/wellness_snapshot.dart';
import '../services/baseline_service.dart';
import '../services/step_counter_service.dart';
import '../storage/app_settings_store.dart';
import '../storage/health_log_store.dart';
import '../storage/metrics_store.dart';
import '../storage/user_profile_store.dart';
import '../storage/watch_settings_store.dart';
import '../theme/app_theme.dart';
import '../utils/heat_index.dart';
import '../widgets/ai_chat_bubble.dart';
import '../widgets/metric_card.dart';
import 'health_log_screens.dart';
import 'map_screen.dart';
import 'metric_detail_screens.dart';
import 'scan_connect_screen.dart';
import 'settings/watch_settings_screen.dart';
import 'settings_screen.dart';
import 'wellness_detail_screen.dart';

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

/// Unit/status text under the HR and SpO2 cards: "no finger" without
/// contact, a measuring state while the PPG pipeline is still settling or
/// counting beats (with a fit hint if the LEDs are saturating), otherwise
/// the plain unit.
String _ppgUnit(VitalsReading? vitals, String unit, {required bool ready}) {
  if (vitals == null) return unit;
  if (!vitals.fingerPresent) return 'no finger';
  if (!ready) {
    if (vitals.ppgSaturated) return 'adjust fit';
    return vitals.ppgSettling ? 'settling' : 'measuring';
  }
  return unit;
}

WellnessSnapshot _buildWellnessSnapshot({
  required int? score,
  required bool connected,
  required bool hasFingerReading,
  required bool hasHeartRate,
  required bool hasSpo2,
  required bool hasBodyTempReading,
  required double heartRate,
  required int heartRateCeiling,
  required bool heartRateWarn,
  required double spo2,
  required bool spo2Warn,
  required double bodyTemp,
  required bool bodyTempWarn,
  required bool ambientDataAvailable,
  required bool ambientWarn,
  required bool heatStressDataAvailable,
  required bool heatStressWarn,
}) {
  final factors = <WellnessFactor>[
    WellnessFactor(
      label: 'Heart rate',
      warn: heartRateWarn,
      scored: hasHeartRate,
      detail: !hasFingerReading
          ? 'No finger detected — not scored right now.'
          : !hasHeartRate
              ? 'Still measuring — hold still for a few seconds.'
              : '${heartRate.toStringAsFixed(0)} bpm (normal range up to '
              '$heartRateCeiling for your current activity).',
    ),
    WellnessFactor(
      label: 'SpO2',
      warn: spo2Warn,
      scored: hasSpo2,
      detail: !hasFingerReading
          ? 'No finger detected — not scored right now.'
          : !hasSpo2
              ? 'Still measuring — hold still for a few seconds.'
              : '${spo2.toStringAsFixed(0)}% (below 92% is flagged).',
    ),
    WellnessFactor(
      label: 'Body temperature',
      warn: bodyTempWarn,
      scored: hasBodyTempReading,
      detail: !hasBodyTempReading
          ? 'No body-temp reading right now.'
          : '${bodyTemp.toStringAsFixed(1)}°C (normal range 35.5–37.8°C).',
    ),
    WellnessFactor(
      label: 'Ambient heat index',
      warn: ambientWarn,
      scored: ambientDataAvailable,
      detail: !ambientDataAvailable
          ? 'No ambient reading right now.'
          : ambientWarn
              ? 'Feels-like temperature has reached NOAA "danger" level.'
              : 'Within a safe range.',
    ),
    WellnessFactor(
      label: 'Heat-stress combination',
      warn: heatStressWarn,
      scored: heatStressDataAvailable,
      detail: !heatStressDataAvailable
          ? 'Not enough data to check right now.'
          : heatStressWarn
              ? 'High heat index together with an elevated body temperature.'
              : 'No combined heat-stress signal right now.',
    ),
  ];
  return WellnessSnapshot(score: score, factors: factors, connected: connected);
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    // Instances for method calls / passing down — `select` below covers
    // the fields this screen's own layout actually depends on, so we
    // don't rebuild the whole dashboard on every fall-probability tick or
    // activity-confidence tick from services with their own fast internal
    // timers (500ms / 1s) that mostly don't change what's on screen.
    final fallDetector = context.read<FallDetectorService>();
    final alertActive =
        context.select<FallDetectorService, bool>((s) => s.alertActive);
    final currentActivity =
        context.select<ActivityClassifierService, Activity?>((s) => s.current);
    final baseline = context.read<BaselineService>();
    final baselineHeartRateMean =
        context.select<BaselineService, double?>((s) => s.heartRateMean);
    final disaster = context.watch<DisasterService>();
    final metrics = context.watch<MetricsStore>();
    final healthLog = context.watch<HealthLogStore>();
    final appSettings = context.watch<AppSettingsStore>();
    final watchSettings = context.watch<WatchSettingsStore>().settings;
    final userProfile = context.watch<UserProfileStore>();
    final isMaleProfile = userProfile.sex == 'Male';
    final cycleStart = healthLog.latestCycleStart;
    final unitSystem = resolveEffectiveUnitSystem(appSettings.unitSystem);
    final bodyFatPercent = computeBodyFatPercent(
      bmi: metrics.bmi,
      dateOfBirth: userProfile.dateOfBirth,
      sex: userProfile.sex,
    );
    final connected = ble.status == ConnectionStatus.connected;

    final vitals = ble.latestVitals;
    final env = ble.latestEnv;

    final heartRate = vitals?.heartRate ?? 0;
    final spo2 = vitals?.spo2 ?? 0;
    final bodyTemp = vitals?.bodyTempC ?? 0;
    // The MAX30102 zeroes heartRate/spo2 when it can't see a finger — the
    // OLED already shows "no finger", so the app needs to too, rather
    // than reading a 0 as a genuine (and alarming) vital sign. Contact
    // (hasFingerReading) and a usable value (hasHeartRate/hasSpo2) are
    // separate: the firmware's PPG pipeline settles for ~2 s and needs 4
    // good beats before it reports anything, and drops back to measuring
    // if beats stop (wrist motion) — see VitalsReading.hrReady.
    final hasFingerReading = vitals != null && vitals.fingerPresent;
    final hasHeartRate = vitals != null && vitals.hasHeartRate;
    final hasSpo2 = vitals != null && vitals.hasSpo2;
    // Body temp comes from the DS18B20 on its own 1-Wire GPIO, independent
    // of the MAX30102's finger contact — it has its own "no reading" gate
    // (0 = sensor unavailable, see readBodyTempC() in health_companion.ino)
    // rather than riding on hasFingerReading.
    final hasBodyTempReading = vitals != null && bodyTemp != 0;
    // Body temp is only trustworthy enough to WARN on (as opposed to just
    // display) when: contact is confirmed (or the developer override below
    // is off) and the DS18B20 has had time to reach thermal equilibrium
    // with the wrist since connecting — see bodyTempEquilibrationWindow.
    // Both gates exist because a watch lying on a table can still report a
    // plausible-looking "body" temperature.
    final bodyTempPastEquilibrium = ble.connectedAt != null &&
        DateTime.now().difference(ble.connectedAt!) >=
            bodyTempEquilibrationWindow;
    final bodyTempWarnEligible = hasBodyTempReading &&
        !watchSettings.ignoreBodyTempContactCheck &&
        bodyTempPastEquilibrium;
    final ceiling = heartRateCeiling(currentActivity);
    final heartRateWarn = hasHeartRate &&
        (heartRate < heartRateFloor ||
            heartRate > ceiling ||
            baseline.isAnomalous(heartRate));
    final spo2Warn = hasSpo2 && spo2 < spo2FloorPercent;
    final bodyTempWarn = bodyTempWarnEligible &&
        (bodyTemp > bodyTempHighC || bodyTemp < bodyTempLowC);

    // Which source wins when both are available is a Settings choice
    // (Sensor precedence) — "--" only when neither is available either way.
    final preferWearable = appSettings.ambientSourcePreference ==
        AmbientSourcePreference.preferWearable;
    final resolvedAmbientTemp = preferWearable
        ? (env?.ambientTempC ?? disaster.risk?.ambientTempC)
        : (disaster.risk?.ambientTempC ?? env?.ambientTempC);
    final resolvedHumidity = preferWearable
        ? (env?.humidity ?? disaster.risk?.humidityPercent)
        : (disaster.risk?.humidityPercent ?? env?.humidity);
    final resolvedPressure = preferWearable
        ? (env?.pressureHPa ?? disaster.risk?.pressureHPa)
        : (disaster.risk?.pressureHPa ?? env?.pressureHPa);
    final ambientIsFromWearable = preferWearable
        ? env != null
        : (disaster.risk?.ambientTempC == null && env != null);

    final ambientWarn = resolvedAmbientTemp != null &&
        resolvedHumidity != null &&
        heatRiskLevel(
                heatIndexCelsius(resolvedAmbientTemp, resolvedHumidity)) ==
            HeatRisk.danger;
    final heatStressWarn = resolvedAmbientTemp != null &&
        resolvedHumidity != null &&
        bodyTempWarnEligible &&
        isHeatStressRisk(
          ambientC: resolvedAmbientTemp,
          humidityPercent: resolvedHumidity,
          bodyTempC: bodyTemp,
        );
    // "Vitals" for scoring purposes requires confirmed skin contact
    // (hasFingerReading), not just any non-zero reading. Body temp alone
    // isn't proof the watch is worn — an off-wrist DS18B20 happily
    // reports a plausible ambient temperature (e.g. 29.6°C sitting on a
    // table), and bodyTempWarnEligible can also be true purely because
    // the developer contact-check override is on. A connected-but-unworn
    // watch also still sends packets at all (heartRate/spo2 zeroed — see
    // notifyVitals() in health_companion.ino), which must not be scored
    // as "100, all clear". Also requires `connected`: latestVitals is
    // deliberately kept around after a disconnect (see
    // BleService.latestVitals) so other parts of the dashboard can show
    // a last-known reading, but the wellness score specifically should
    // disappear rather than keep showing a stale figure once the watch
    // is gone.
    final hasVitals = connected && hasFingerReading;
    final wellnessScore = _wellnessScore(
      hasVitals: hasVitals,
      heartRateWarn: heartRateWarn,
      spo2Warn: spo2Warn,
      bodyTempWarn: bodyTempWarn,
      ambientWarn: ambientWarn,
      heatStressWarn: heatStressWarn,
    );
    final wellnessSnapshot = _buildWellnessSnapshot(
      score: wellnessScore,
      connected: connected,
      hasFingerReading: hasFingerReading,
      hasHeartRate: hasHeartRate,
      hasSpo2: hasSpo2,
      hasBodyTempReading: hasBodyTempReading,
      heartRate: heartRate,
      heartRateCeiling: ceiling,
      heartRateWarn: heartRateWarn,
      spo2: spo2,
      spo2Warn: spo2Warn,
      bodyTemp: bodyTemp,
      bodyTempWarn: bodyTempWarn,
      ambientDataAvailable:
          resolvedAmbientTemp != null && resolvedHumidity != null,
      ambientWarn: ambientWarn,
      heatStressDataAvailable: bodyTempWarnEligible &&
          resolvedAmbientTemp != null &&
          resolvedHumidity != null,
      heatStressWarn: heatStressWarn,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ForeverFit',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sos),
            tooltip: 'Manual SOS',
            color: Theme.of(context).colorScheme.error,
            onPressed:
                alertActive ? null : () => fallDetector.triggerManualSOS(),
          ),
          IconButton(
            icon: Icon(connected
                ? Icons.bluetooth_disabled
                : Icons.bluetooth_searching),
            tooltip: connected ? 'Disconnect' : 'Connect wearable',
            onPressed: connected
                ? () => ble.disconnect()
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const ScanConnectScreen()),
                    ),
          ),
          IconButton(
            icon: const Icon(Icons.watch_outlined),
            tooltip: 'Watch customization',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WatchSettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      // The floating AI chat bubble is stacked on top of the Dashboard's
      // own content, not mounted globally — per explicit user request, it
      // should only ever appear on the main screen (Navigator.push covers
      // it automatically once any other screen is pushed on top, same as
      // any other widget below the active route).
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (alertActive) const _FallAlertBanner(),
              const _RecoveredEmergencyBanner(),
              if (!connected) _ConnectWearableBanner(),
              const _InsightsSection(),
              _DisasterMapNavCard(risk: disaster.risk),
              const SizedBox(height: 12),
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
                    value: hasHeartRate ? heartRate.toStringAsFixed(0) : '--',
                    unit: _ppgUnit(vitals, 'bpm', ready: hasHeartRate),
                    icon: Icons.favorite,
                    warn: heartRateWarn,
                    accentColor: AppTheme.accentPink,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const HeartRateHistoryScreen()),
                    ),
                  ),
                  MetricCard(
                    label: 'SpO2',
                    value: hasSpo2 ? spo2.toStringAsFixed(0) : '--',
                    unit: _ppgUnit(vitals, '%', ready: hasSpo2),
                    icon: Icons.bloodtype,
                    warn: spo2Warn,
                    accentColor: AppTheme.accentBlue,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SpO2HistoryScreen()),
                    ),
                  ),
                  MetricCard(
                    label: 'Body temp',
                    value: hasBodyTempReading
                        ? formatTemperatureC(bodyTemp, unitSystem)
                            .value
                            .toStringAsFixed(1)
                        : '--',
                    unit: vitals != null && !hasBodyTempReading
                        ? 'no reading'
                        : formatTemperatureC(bodyTemp, unitSystem).unit,
                    icon: Icons.thermostat,
                    warn: bodyTempWarn,
                    accentColor: AppTheme.accentCoral,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const BodyTempHistoryScreen()),
                    ),
                  ),
                  MetricCard(
                    label: 'Ambient temp',
                    value: resolvedAmbientTemp == null
                        ? '--'
                        : formatTemperatureC(resolvedAmbientTemp, unitSystem)
                            .value
                            .toStringAsFixed(1),
                    unit: resolvedAmbientTemp == null
                        ? ''
                        : '${formatTemperatureC(resolvedAmbientTemp, unitSystem).unit}'
                            '${ambientIsFromWearable ? '' : ' (online)'}',
                    icon: Icons.wb_sunny_outlined,
                    warn: ambientWarn,
                    accentColor: AppTheme.accentCoral,
                  ),
                  MetricCard(
                    label: 'Humidity',
                    value: resolvedHumidity == null
                        ? '--'
                        : resolvedHumidity.toStringAsFixed(0),
                    unit: resolvedHumidity == null
                        ? ''
                        : (ambientIsFromWearable ? '%' : '% (online)'),
                    icon: Icons.water_drop_outlined,
                    accentColor: AppTheme.accentTeal,
                  ),
                  MetricCard(
                    label: 'Pressure',
                    value: resolvedPressure == null
                        ? '--'
                        : resolvedPressure.toStringAsFixed(0),
                    unit: resolvedPressure == null
                        ? ''
                        : (ambientIsFromWearable ? 'hPa' : 'hPa (online)'),
                    icon: Icons.speed,
                    accentColor: AppTheme.accentPurple,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Wellness overview',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _CardRow(
                cards: [
                  MetricCard(
                    label: 'Wellness',
                    value:
                        wellnessScore == null ? '--' : wellnessScore.toString(),
                    unit: wellnessScore == null ? '' : '/100',
                    icon: Icons.favorite_border,
                    warn: wellnessScore != null && wellnessScore < 70,
                    accentColor: AppTheme.accentPink,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            WellnessDetailScreen(snapshot: wellnessSnapshot),
                      ),
                    ),
                  ),
                  MetricCard(
                    label: 'Activity',
                    value: currentActivity == null
                        ? '--'
                        : _activityLabel(currentActivity),
                    unit: '',
                    icon: Icons.directions_walk,
                    accentColor: AppTheme.accentGreen,
                  ),
                  MetricCard(
                    label: 'Baseline',
                    value: baselineHeartRateMean == null
                        ? '--'
                        : baselineHeartRateMean.toStringAsFixed(0),
                    unit: baselineHeartRateMean == null ? '' : 'bpm',
                    icon: Icons.show_chart,
                    accentColor: AppTheme.accentBlue,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Body & activity',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _PagedCardGrid(
                cards: [
                  const _StepsCard(),
                  MetricCard(
                    label: 'Weight',
                    value: metrics.latestWeightKg == null
                        ? '--'
                        : formatWeightKg(metrics.latestWeightKg!, unitSystem)
                            .value
                            .toStringAsFixed(1),
                    unit: metrics.latestWeightKg == null
                        ? ''
                        : formatWeightKg(metrics.latestWeightKg!, unitSystem)
                            .unit,
                    icon: Icons.monitor_weight_outlined,
                    accentColor: AppTheme.accentCoral,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const WeightHistoryScreen()),
                    ),
                  ),
                  MetricCard(
                    label: 'Height',
                    value: metrics.latestHeightCm == null
                        ? '--'
                        : formatHeightCm(metrics.latestHeightCm!, unitSystem)
                            .value
                            .toStringAsFixed(0),
                    unit: metrics.latestHeightCm == null
                        ? ''
                        : formatHeightCm(metrics.latestHeightCm!, unitSystem)
                            .unit,
                    icon: Icons.height,
                    accentColor: AppTheme.accentPurple,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const HeightHistoryScreen()),
                    ),
                  ),
                  MetricCard(
                    label: 'BMI',
                    value: metrics.bmi?.toStringAsFixed(1) ?? '--',
                    unit: '',
                    icon: Icons.calculate_outlined,
                    accentColor: AppTheme.accentBlue,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const BmiHistoryScreen()),
                    ),
                  ),
                  MetricCard(
                    label: 'Body fat',
                    value: bodyFatPercent?.toStringAsFixed(1) ?? '--',
                    unit: bodyFatPercent == null ? '' : '%',
                    icon: Icons.percent,
                    accentColor: AppTheme.accentTeal,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const BodyFatHistoryScreen()),
                    ),
                  ),
                  MetricCard(
                    label: 'Hydration',
                    value: formatHydrationMl(
                            metrics.todayHydrationMl.toDouble(), unitSystem)
                        .value
                        .toStringAsFixed(2),
                    unit: formatHydrationMl(
                            metrics.todayHydrationMl.toDouble(), unitSystem)
                        .unit,
                    icon: Icons.local_drink_outlined,
                    accentColor: AppTheme.accentBlue,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const HydrationHistoryScreen()),
                    ),
                  ),
                  MetricCard(
                    label: 'Blood pressure',
                    value: healthLog.latestBloodPressure == null
                        ? '--'
                        : '${healthLog.latestBloodPressure!.$1}/${healthLog.latestBloodPressure!.$2}',
                    unit: healthLog.latestBloodPressure == null ? '' : 'mmHg',
                    icon: Icons.favorite_border,
                    accentColor: AppTheme.accentCoral,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const BloodPressureHistoryScreen()),
                    ),
                  ),
                  MetricCard(
                    label: 'Blood glucose',
                    value: healthLog.latestGlucose?.toStringAsFixed(0) ?? '--',
                    unit: healthLog.latestGlucose == null ? '' : 'mg/dL',
                    icon: Icons.water_drop_outlined,
                    accentColor: AppTheme.accentPurple,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const BloodGlucoseHistoryScreen()),
                    ),
                  ),
                  MetricCard(
                    label: 'Insulin',
                    value:
                        healthLog.latestInsulinDose?.toStringAsFixed(1) ?? '--',
                    unit: healthLog.latestInsulinDose == null ? '' : 'units',
                    icon: Icons.vaccines_outlined,
                    accentColor: AppTheme.accentTeal,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const InsulinHistoryScreen()),
                    ),
                  ),
                  MetricCard(
                    label: 'Sleep',
                    value:
                        healthLog.latestSleepHours?.toStringAsFixed(1) ?? '--',
                    unit: healthLog.latestSleepHours == null ? '' : 'hrs',
                    icon: Icons.bedtime_outlined,
                    accentColor: AppTheme.accentBlue,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SleepHistoryScreen()),
                    ),
                  ),
                  MetricCard(
                    label: 'Medications',
                    value: healthLog.medications.isEmpty
                        ? '--'
                        : healthLog.medications.length.toString(),
                    unit: healthLog.medications.isEmpty ? '' : 'tracked',
                    icon: Icons.medication_outlined,
                    accentColor: AppTheme.accentGreen,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const MedicationsScreen()),
                    ),
                  ),
                  MetricCard(
                    label: 'Cycle',
                    // Shown to everyone (not hidden), only greyed out for
                    // a profile explicitly set to "Male" — an unset,
                    // "Other", or "Prefer not to say" profile still gets
                    // the real tile, since a sex field alone isn't a
                    // reliable signal that cycle tracking doesn't apply.
                    value: isMaleProfile || cycleStart == null
                        ? '--'
                        : '${DateTime.now().difference(cycleStart).inDays}',
                    unit: isMaleProfile || cycleStart == null ? '' : 'days ago',
                    icon: Icons.water_drop_outlined,
                    accentColor: AppTheme.accentPink,
                    disabled: isMaleProfile,
                    onTap: () {
                      if (isMaleProfile) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Menstrual cycle tracking is hidden for a '
                                    'profile set to "Male" — change it in '
                                    'Settings > Profile if this is incorrect.'),
                          ),
                        );
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const MenstrualCycleHistoryScreen()),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          const AiChatBubble(),
        ],
      ),
    );
  }
}

/// A horizontally scrollable row of fixed-size, rectangular cards — used
/// for the Wellness overview section (just 3 cards, no paging needed).
/// Body & activity uses `_PagedCardGrid` instead — see below.
class _CardRow extends StatelessWidget {
  const _CardRow({required this.cards});

  final List<Widget> cards;

  static const _cardWidth = 168.0;
  static const _cardHeight = 136.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _cardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => SizedBox(width: _cardWidth, child: cards[i]),
      ),
    );
  }
}

/// A swipeable, paged 2-column x 3-row grid with a dot-page indicator —
/// the OpenVitals dashboard-carousel pattern, reimplemented from scratch
/// here (AGPL, see ARCHITECTURE.md — no code copied). Used for Body &
/// activity now that it's grown past what a single row or a wrapping
/// GridView comfortably shows.
class _PagedCardGrid extends StatefulWidget {
  const _PagedCardGrid({required this.cards});

  final List<Widget> cards;

  static const _perPage = 6; // 2 columns x 3 rows
  static const _pageHeight = 420.0;

  @override
  State<_PagedCardGrid> createState() => _PagedCardGridState();
}

class _PagedCardGridState extends State<_PagedCardGrid> {
  final _controller = PageController();
  int _page = 0;

  List<List<Widget>> get _pages {
    final pages = <List<Widget>>[];
    for (var i = 0; i < widget.cards.length; i += _PagedCardGrid._perPage) {
      pages.add(widget.cards.sublist(
        i,
        (i + _PagedCardGrid._perPage).clamp(0, widget.cards.length),
      ));
    }
    return pages;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return Column(
      children: [
        SizedBox(
          height: _PagedCardGrid._pageHeight,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: pages.length,
            itemBuilder: (_, i) => _CardGridPage(cards: pages[i]),
          ),
        ),
        if (pages.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pages.length; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _page
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One page of up to 6 cards, laid out as 3 rows of 2 — plain Rows +
/// Expanded rather than GridView, so each row's height is a simple even
/// share of the fixed page height instead of depending on an
/// aspect-ratio guess that would vary with screen width.
class _CardGridPage extends StatelessWidget {
  const _CardGridPage({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      final second = i + 1 < cards.length ? cards[i + 1] : null;
      rows.add(Expanded(
        child: Row(
          children: [
            Expanded(child: cards[i]),
            const SizedBox(width: 8),
            Expanded(child: second ?? const SizedBox()),
          ],
        ),
      ));
    }
    return Column(children: rows);
  }
}

/// Isolated so a step-count update (every stride while walking) only
/// rebuilds this one card, not the whole dashboard.
class _StepsCard extends StatelessWidget {
  const _StepsCard();

  @override
  Widget build(BuildContext context) {
    final steps = context.watch<StepCounterService>();
    return MetricCard(
      label: 'Steps today',
      value: steps.todaySteps.toString(),
      unit: '',
      icon: Icons.directions_walk,
      accentColor: AppTheme.accentGreen,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const StepsHistoryScreen()),
      ),
    );
  }
}

/// Shows the current rule-based suggestions/warnings from
/// InsightWatcherService — the same conditions that also trigger a local
/// notification, surfaced here too so they're visible without leaving the
/// app. Self-watches its own provider so an insight recompute only rebuilds
/// this card, not the whole dashboard.
class _InsightsSection extends StatelessWidget {
  const _InsightsSection();

  Color _severityColor(BuildContext context, InsightSeverity severity) {
    final scheme = Theme.of(context).colorScheme;
    switch (severity) {
      case InsightSeverity.critical:
        return scheme.error;
      case InsightSeverity.warning:
        return scheme.tertiary;
      case InsightSeverity.info:
        return scheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final insights =
        context.select<InsightWatcherService, List<Insight>>((s) => s.insights);
    if (insights.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Insights',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final insight in insights)
              ListTile(
                leading: Icon(insight.icon,
                    color: _severityColor(context, insight.severity)),
                title: Text(insight.title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(insight.message),
              ),
          ],
        ),
      ),
    );
  }
}

/// Entry point to the disaster/GPS map — a button on the dashboard rather
/// than a tab, since single-dashboard navigation replaced the old bottom
/// nav bar. Shows the current warning inline when there is one, so it's
/// not just a generic link.
class _DisasterMapNavCard extends StatelessWidget {
  const _DisasterMapNavCard({required this.risk});

  final DisasterRisk? risk;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasWarning = risk?.hasWarning ?? false;
    return Card(
      color: hasWarning ? scheme.errorContainer : scheme.primaryContainer,
      child: ListTile(
        leading: Icon(
          hasWarning ? Icons.warning_amber_rounded : Icons.map_outlined,
          color:
              hasWarning ? scheme.onErrorContainer : scheme.onPrimaryContainer,
        ),
        title: Text(
          'Disaster & safety map',
          style: TextStyle(
            color: hasWarning
                ? scheme.onErrorContainer
                : scheme.onPrimaryContainer,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          hasWarning
              ? (risk?.warningMessage ?? 'Elevated risk in your area')
              : 'GPS-based earthquake, flood, and cyclone risk for your area',
          style: TextStyle(
            color: hasWarning
                ? scheme.onErrorContainer
                : scheme.onPrimaryContainer,
          ),
        ),
        trailing: Icon(Icons.chevron_right,
            color: hasWarning
                ? scheme.onErrorContainer
                : scheme.onPrimaryContainer),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MapScreen()),
        ),
      ),
    );
  }
}

/// Surfaces a prior emergency workflow that didn't finish because the app
/// process was killed mid-run — deliberately shown rather than silently
/// resumed (re-placing real calls after a silent relaunch would be more
/// dangerous than informative). See EmergencyWorkflowService.init().
class _RecoveredEmergencyBanner extends StatelessWidget {
  const _RecoveredEmergencyBanner();

  @override
  Widget build(BuildContext context) {
    final workflow = context.watch<EmergencyWorkflowService>();
    if (!workflow.recoveredIncompleteRun) return const SizedBox.shrink();
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(Icons.warning_amber,
            color: Theme.of(context).colorScheme.onErrorContainer),
        title: Text(
          'An emergency workflow didn\'t finish',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          'It was interrupted at "${workflow.recoveredStateLabel}" — the app '
          'was likely closed mid-emergency. If you still need help, use the '
          'SOS button above.',
          style:
              TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
        ),
        trailing: IconButton(
          icon: Icon(Icons.close,
              color: Theme.of(context).colorScheme.onErrorContainer),
          onPressed: () => workflow.acknowledgeRecoveredRun(),
        ),
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
        subtitle:
            const Text('Vitals and environment readings need the wearable.'),
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
/// clears it. Watches FallDetectorService itself (rather than taking it
/// as a constructor param from a parent that no longer rebuilds on every
/// tick) so the countdown text still updates every second while it's
/// showing, without forcing the whole dashboard to rebuild that often.
class _FallAlertBanner extends StatelessWidget {
  const _FallAlertBanner();

  @override
  Widget build(BuildContext context) {
    final fallDetector = context.watch<FallDetectorService>();
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
