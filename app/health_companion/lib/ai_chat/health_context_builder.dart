import '../ble/ble_service.dart';
import '../services/baseline_service.dart';
import '../services/step_counter_service.dart';
import '../storage/health_log_store.dart';
import '../storage/metrics_store.dart';
import '../storage/user_profile_store.dart';

/// Builds a compact, natural-language snapshot of the user's own data —
/// live wearable vitals, environment, body metrics, activity, and health
/// log — so the on-device AI assistant can answer grounded in the
/// person's actual state ("is my heart rate normal right now?") instead
/// of only generic knowledge. Deliberately a pure read of existing app
/// state (same "reuse, don't re-derive" approach as
/// emergency_summary_builder.dart), not a new tracker of its own.
///
/// Kept short on purpose: this gets prepended to the model's already
/// small (4096-token) context budget, so it reports current *values*,
/// not a history dump — the equivalent of what a person would say out
/// loud summarizing their own stats, not a spreadsheet.
String buildHealthContext({
  required BleService ble,
  required MetricsStore metrics,
  required HealthLogStore healthLog,
  required BaselineService baseline,
  required UserProfileStore userProfile,
  required StepCounterService stepCounter,
}) {
  final lines = <String>[];

  if (userProfile.name.isNotEmpty || userProfile.dateOfBirth != null) {
    final parts = <String>[];
    if (userProfile.name.isNotEmpty) parts.add(userProfile.name);
    final dob = userProfile.dateOfBirth;
    if (dob != null) {
      final age = _ageFrom(dob);
      parts.add('age $age');
    }
    if (userProfile.sex.isNotEmpty) parts.add(userProfile.sex);
    lines.add('User: ${parts.join(', ')}.');
  }

  final vitals = ble.latestVitals;
  final hasFingerReading = vitals != null && vitals.fingerPresent;
  if (hasFingerReading) {
    final baselineText = baseline.heartRateMean != null
        ? ' (personal baseline avg ${baseline.heartRateMean!.toStringAsFixed(0)} bpm)'
        : '';
    lines.add(
      'Live vitals right now: heart rate ${vitals.heartRate.toStringAsFixed(0)} bpm$baselineText, '
      'SpO2 ${vitals.spo2.toStringAsFixed(0)}%, '
      'body temperature ${vitals.bodyTempC.toStringAsFixed(1)}°C.',
    );
  } else if (ble.status == ConnectionStatus.connected) {
    lines.add(
      'Wearable connected but no finger/skin contact detected right now — no live vitals reading.',
    );
  } else {
    lines.add('No wearable connected right now — no live vitals reading.');
  }

  final env = ble.latestEnv;
  if (env != null) {
    lines.add(
      'Environment: ambient ${env.ambientTempC.toStringAsFixed(1)}°C, '
      'humidity ${env.humidity.toStringAsFixed(0)}%, '
      'pressure ${env.pressureHPa.toStringAsFixed(0)} hPa.',
    );
  }

  final bodyParts = <String>[];
  if (metrics.latestWeightKg != null) {
    bodyParts.add('weight ${metrics.latestWeightKg!.toStringAsFixed(1)} kg');
  }
  if (metrics.latestHeightCm != null) {
    bodyParts.add('height ${metrics.latestHeightCm!.toStringAsFixed(0)} cm');
  }
  if (metrics.bmi != null) {
    bodyParts.add('BMI ${metrics.bmi!.toStringAsFixed(1)}');
  }
  if (bodyParts.isNotEmpty) lines.add('Body: ${bodyParts.join(', ')}.');

  if (stepCounter.todaySteps > 0) {
    lines.add('Activity: ${stepCounter.todaySteps} steps today.');
  }

  final logParts = <String>[];
  final bp = healthLog.latestBloodPressure;
  if (bp != null) logParts.add('blood pressure ${bp.$1}/${bp.$2} mmHg');
  if (healthLog.latestGlucose != null) {
    logParts.add(
        'blood glucose ${healthLog.latestGlucose!.toStringAsFixed(0)} mg/dL');
  }
  if (healthLog.latestSleepHours != null) {
    logParts.add(
        'last logged sleep ${healthLog.latestSleepHours!.toStringAsFixed(1)}h');
  }
  if (healthLog.medications.isNotEmpty) {
    logParts.add(
        '${healthLog.medications.length} medication(s) logged, ${healthLog.dosesTakenToday} dose(s) taken today');
  }
  final medicalId = healthLog.medicalId;
  if (medicalId != null && !medicalId.isEmpty) {
    if (medicalId.bloodType.isNotEmpty) {
      logParts.add('blood type ${medicalId.bloodType}');
    }
    if (medicalId.allergies.isNotEmpty) {
      logParts.add('allergies: ${medicalId.allergies}');
    }
    if (medicalId.conditions.isNotEmpty) {
      logParts.add('known conditions: ${medicalId.conditions}');
    }
  }
  if (logParts.isNotEmpty) lines.add('Health log: ${logParts.join('; ')}.');

  return lines.join('\n');
}

int _ageFrom(DateTime dateOfBirth) {
  final now = DateTime.now();
  var age = now.year - dateOfBirth.year;
  if (now.month < dateOfBirth.month ||
      (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
    age--;
  }
  return age;
}
