import 'package:flutter/material.dart';

import '../ble/ble_service.dart';
import '../disaster/disaster_service.dart';
import '../disaster/pressure_trend.dart';
import '../ml/activity_classifier_service.dart';
import '../models/insight.dart';
import '../services/baseline_service.dart';
import '../storage/health_log_store.dart';
import '../storage/metrics_store.dart';
import '../storage/watch_settings_store.dart';
import 'health_thresholds.dart';

/// Computes the current set of rule-based suggestions/warnings from live
/// provider state. Deliberately a pure function of its inputs (no state of
/// its own) — [InsightWatcherService] owns when to recompute and what to do
/// with the result (display vs. notify vs. both).
List<Insight> computeInsights({
  required BleService ble,
  required DisasterService disaster,
  required BaselineService baseline,
  required Activity? currentActivity,
  required HealthLogStore healthLog,
  required MetricsStore metrics,
  required WatchSettingsStore watchSettings,
}) {
  final insights = <Insight>[];

  final vitals = ble.latestVitals;
  final hasFingerReading = vitals != null && vitals.fingerPresent;
  // Body temp comes from the DS18B20 on its own 1-Wire GPIO, independent of
  // the MAX30101's finger contact — its own "no reading" gate is 0°C
  // (sensor unavailable, see readBodyTempC() in health_companion.ino)
  // rather than hasFingerReading.
  final hasBodyTempReading = vitals != null && vitals.bodyTempC != 0;
  // Only warn on body temp when contact is confirmed (or the developer
  // override is off) and the DS18B20 has had time to reach thermal
  // equilibrium since connecting — see dashboard_screen.dart for the same
  // gate, kept in sync so the Dashboard card and this Insight never
  // disagree about whether a given reading is warn-worthy.
  final bodyTempPastEquilibrium = ble.connectedAt != null &&
      DateTime.now().difference(ble.connectedAt!) >=
          bodyTempEquilibrationWindow;
  final bodyTempWarnEligible = hasBodyTempReading &&
      !watchSettings.settings.ignoreBodyTempContactCheck &&
      bodyTempPastEquilibrium;

  // --- Vitals / wellness -------------------------------------------------
  if (hasFingerReading) {
    final heartRate = vitals.heartRate;
    final ceiling = heartRateCeiling(currentActivity);
    if (heartRate < heartRateFloor || heartRate > ceiling) {
      insights.add(Insight(
        id: 'vitals.heartRate.range',
        title:
            heartRate < heartRateFloor ? 'Low heart rate' : 'High heart rate',
        message: '${heartRate.toStringAsFixed(0)} bpm is outside the normal '
            'range ($heartRateFloor–$ceiling bpm for your current activity).',
        severity: InsightSeverity.warning,
        category: InsightCategory.vitals,
        icon: Icons.favorite,
      ));
    } else if (baseline.isAnomalous(heartRate)) {
      insights.add(Insight(
        id: 'vitals.heartRate.baseline',
        title: 'Heart rate unusual for you',
        message: '${heartRate.toStringAsFixed(0)} bpm is more than 2 standard '
            'deviations from your personal baseline '
            '(${baseline.heartRateMean?.toStringAsFixed(0)} bpm).',
        severity: InsightSeverity.info,
        category: InsightCategory.vitals,
        icon: Icons.show_chart,
      ));
    }

    if (vitals.spo2 > 0 && vitals.spo2 < spo2FloorPercent) {
      insights.add(Insight(
        id: 'vitals.spo2.low',
        title: 'Low SpO2',
        message: '${vitals.spo2.toStringAsFixed(0)}% is below the healthy '
            'floor of $spo2FloorPercent%.',
        severity: InsightSeverity.critical,
        category: InsightCategory.vitals,
        icon: Icons.bloodtype,
      ));
    }
  }

  if (bodyTempWarnEligible &&
      (vitals.bodyTempC > bodyTempHighC || vitals.bodyTempC < bodyTempLowC)) {
    insights.add(Insight(
      id: 'vitals.bodyTemp.range',
      title: vitals.bodyTempC > bodyTempHighC
          ? 'Elevated body temperature'
          : 'Low body temperature',
      message: '${vitals.bodyTempC.toStringAsFixed(1)}°C is outside the '
          'normal range ($bodyTempLowC–$bodyTempHighC°C).',
      severity: InsightSeverity.warning,
      category: InsightCategory.vitals,
      icon: Icons.thermostat,
    ));
  }

  final bp = healthLog.latestBloodPressure;
  if (bp != null) {
    final (systolic, diastolic) = bp;
    if (systolic >= bpSystolicCrisisMmHg ||
        diastolic >= bpDiastolicCrisisMmHg) {
      insights.add(Insight(
        id: 'vitals.bp.crisis',
        title: 'Hypertensive crisis range',
        message: 'Your last reading, $systolic/$diastolic mmHg, is in the '
            'hypertensive crisis range. Consider seeking medical attention.',
        severity: InsightSeverity.critical,
        category: InsightCategory.vitals,
        icon: Icons.favorite_border,
      ));
    } else if (systolic >= bpSystolicHighMmHg ||
        diastolic >= bpDiastolicHighMmHg) {
      insights.add(Insight(
        id: 'vitals.bp.high',
        title: 'Elevated blood pressure',
        message: 'Your last reading, $systolic/$diastolic mmHg, is above '
            'the normal range ($bpSystolicHighMmHg/$bpDiastolicHighMmHg mmHg).',
        severity: InsightSeverity.warning,
        category: InsightCategory.vitals,
        icon: Icons.favorite_border,
      ));
    }
  }

  final glucose = healthLog.latestGlucose;
  if (glucose != null &&
      (glucose < glucoseLowMgDl || glucose > glucoseHighMgDl)) {
    insights.add(Insight(
      id: 'vitals.glucose.range',
      title:
          glucose < glucoseLowMgDl ? 'Low blood glucose' : 'High blood glucose',
      message: '${glucose.toStringAsFixed(0)} mg/dL is outside the reference '
          'range ($glucoseLowMgDl–$glucoseHighMgDl mg/dL).',
      severity: InsightSeverity.warning,
      category: InsightCategory.vitals,
      icon: Icons.water_drop_outlined,
    ));
  }

  final sleepHours = healthLog.latestSleepHours;
  if (sleepHours != null && sleepHours < sleepLowHours) {
    insights.add(Insight(
      id: 'vitals.sleep.low',
      title: 'Short sleep last night',
      message: '${sleepHours.toStringAsFixed(1)} hours logged is below the '
          '$sleepLowHours-hour reference floor.',
      severity: InsightSeverity.info,
      category: InsightCategory.vitals,
      icon: Icons.bedtime_outlined,
    ));
  }

  // --- Map / disaster hazards --------------------------------------------
  final risk = disaster.risk;
  if (risk != null) {
    final aqi = risk.usAqi;
    if (aqi != null && aqi >= aqiVeryUnhealthy) {
      insights.add(Insight(
        id: 'hazard.aqi.veryUnhealthy',
        title: 'Very unhealthy air quality',
        message: 'AQI ${aqi.round()} (${risk.aqiCategory}) in your area. '
            'Avoid outdoor activity if possible.',
        severity: InsightSeverity.critical,
        category: InsightCategory.hazard,
        icon: Icons.air,
      ));
    } else if (aqi != null && aqi >= aqiUnhealthy) {
      insights.add(Insight(
        id: 'hazard.aqi.unhealthy',
        title: 'Unhealthy air quality',
        message: 'AQI ${aqi.round()} (${risk.aqiCategory}) in your area. '
            'Consider limiting prolonged outdoor exertion.',
        severity: InsightSeverity.warning,
        category: InsightCategory.hazard,
        icon: Icons.air,
      ));
    }

    if (risk.hazardProfile.floodProne &&
        (risk.precipitationProbabilityPercent ?? 0) > 70) {
      insights.add(Insight(
        id: 'hazard.flood.risk',
        title: 'Flood risk today',
        message: 'High rain probability '
            '(${risk.precipitationProbabilityPercent!.round()}%) in your '
            'flood-prone area.',
        severity: InsightSeverity.warning,
        category: InsightCategory.hazard,
        icon: Icons.water,
      ));
    }

    if (risk.hazardProfile.cycloneProne && (risk.windSpeedKmh ?? 0) > 40) {
      insights.add(Insight(
        id: 'hazard.cyclone.risk',
        title: 'Strong winds in a cyclone-prone area',
        message: '${risk.windSpeedKmh!.round()} km/h winds in your area.',
        severity: InsightSeverity.warning,
        category: InsightCategory.hazard,
        icon: Icons.cyclone,
      ));
    }

    if (risk.nearbyQuakeCount > 0 &&
        (risk.nearbyMaxQuakeMagnitude ?? 0) >= 4.0) {
      insights.add(Insight(
        id: 'hazard.quake.nearby',
        title: 'Recent nearby earthquake activity',
        message: '${risk.nearbyQuakeCount} quake(s) M4.0+ within ~200km in '
            'the last 30 days (max M${risk.nearbyMaxQuakeMagnitude!.toStringAsFixed(1)}).',
        severity: InsightSeverity.info,
        category: InsightCategory.hazard,
        icon: Icons.public,
      ));
    }

    // A rapid pressure fall is a live weather-*condition* signal, not an
    // incoming disaster — it gets a notification + this Insights-card
    // entry, not the full-screen alarm (see DisasterRisk.imminentHazards
    // for why that distinction exists).
    if ((risk.pressureDropHPa3h ?? 0) >= rapidPressureFallHPa) {
      insights.add(Insight(
        id: 'hazard.pressure.rapidFall',
        title: 'Sudden weather change likely',
        message: 'Barometric pressure fell '
            '${risk.pressureDropHPa3h!.toStringAsFixed(1)} hPa in the last '
            '3 hours — conditions consistent with a storm moving in.',
        severity: InsightSeverity.warning,
        category: InsightCategory.hazard,
        icon: Icons.thunderstorm,
      ));
    }
  }

  // --- Tracking reminders --------------------------------------------------
  final now = DateTime.now();
  // Simple proportional-to-time-of-day target: ~2000mL spread evenly across
  // a 7am-11pm waking day, so the reminder doesn't fire at 8am for not
  // already having drunk a full day's water.
  const dailyTargetMl = 2000;
  const wakeHour = 7;
  const sleepHour = 23;
  if (now.hour >= wakeHour && now.hour < sleepHour) {
    final expectedByNowMl = dailyTargetMl *
        (now.hour + now.minute / 60 - wakeHour) /
        (sleepHour - wakeHour);
    if (metrics.todayHydrationMl < expectedByNowMl - 300) {
      insights.add(Insight(
        id: 'reminder.hydration',
        title: 'Hydration reminder',
        message:
            'Only ${(metrics.todayHydrationMl / 1000).toStringAsFixed(2)}L '
            'logged today — behind pace for a $dailyTargetMl mL daily target.',
        severity: InsightSeverity.info,
        category: InsightCategory.reminder,
        icon: Icons.local_drink_outlined,
      ));
    }
  }

  if (healthLog.medications.isNotEmpty && healthLog.dosesTakenToday == 0) {
    insights.add(Insight(
      id: 'reminder.medication',
      title: 'Medication reminder',
      message: 'No doses logged today for '
          '${healthLog.medications.length} tracked medication'
          '${healthLog.medications.length > 1 ? 's' : ''}.',
      severity: InsightSeverity.info,
      category: InsightCategory.reminder,
      icon: Icons.medication_outlined,
    ));
  }

  return insights;
}
