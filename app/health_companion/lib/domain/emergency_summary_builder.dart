import '../ble/ble_service.dart';
import '../services/baseline_service.dart';
import '../storage/health_log_store.dart';
import '../storage/history_store.dart';
import 'emergency_location.dart';
import 'health_thresholds.dart';

/// One abnormal, directly-measured reading — never a diagnosis. Kept
/// separate from the formatted scripts below so all three announcement
/// variants are built from exactly the same underlying facts and can't
/// drift out of wording sync with each other.
class EmergencyReading {
  const EmergencyReading({required this.label, required this.valueText});
  final String label;
  final String valueText;
}

/// Everything the three announcement formatters need. [readings] is empty
/// when there isn't enough data to point at anything specific — callers
/// must fall back to generic, non-diagnostic wording in that case rather
/// than guessing (see the spec this feature was built against).
class EmergencySummary {
  const EmergencySummary({
    required this.readings,
    required this.durationText,
    required this.location,
    required this.triggerReason,
  });

  final List<EmergencyReading> readings;
  final String?
      durationText; // e.g. "approximately 4 minutes" — null if unknown
  final EmergencyLocation location;
  final String triggerReason; // e.g. "a possible fall was detected"

  bool get hasSpecificData => readings.isNotEmpty;
}

/// Builds an [EmergencySummary] from data already recorded on-device —
/// current wearable vitals, recent vitals history (for how long a reading
/// has been abnormal), and logged blood pressure/glucose. Deliberately a
/// pure read of existing app state, not a new detector: it reuses the
/// same thresholds (`health_thresholds.dart`) the Dashboard and insight
/// engine already use, so "abnormal" means the same thing everywhere in
/// the app.
EmergencySummary buildEmergencySummary({
  required BleService ble,
  required HistoryStore historyStore,
  required HealthLogStore healthLog,
  required BaselineService baseline,
  required EmergencyLocation location,
  required String triggerReason,
}) {
  final vitals = ble.latestVitals;
  final hasFingerReading = vitals != null && vitals.fingerPresent;
  final readings = <EmergencyReading>[];

  if (hasFingerReading) {
    final hr = vitals.heartRate;
    // No live activity context available at emergency-summary time — the
    // resting/"still" ceiling is the neutral default here, not a claim
    // about what the user was doing.
    final ceiling = heartRateCeiling(null);
    if (hr < heartRateFloor || hr > ceiling || baseline.isAnomalous(hr)) {
      readings.add(EmergencyReading(
        label: 'heart rate',
        valueText: '${hr.toStringAsFixed(0)} beats per minute',
      ));
    }
    if (vitals.spo2 > 0 && vitals.spo2 < spo2FloorPercent) {
      readings.add(EmergencyReading(
        label: 'oxygen saturation',
        valueText: '${vitals.spo2.toStringAsFixed(0)} percent',
      ));
    }
  }

  if (vitals != null &&
      (vitals.bodyTempC > bodyTempHighC || vitals.bodyTempC < bodyTempLowC)) {
    readings.add(EmergencyReading(
      label: 'body temperature',
      valueText: '${vitals.bodyTempC.toStringAsFixed(1)} degrees Celsius',
    ));
  }

  final bp = healthLog.latestBloodPressure;
  if (bp != null) {
    final (systolic, diastolic) = bp;
    if (systolic >= bpSystolicHighMmHg || diastolic >= bpDiastolicHighMmHg) {
      readings.add(EmergencyReading(
        label: 'blood pressure',
        valueText: '$systolic over $diastolic',
      ));
    }
  }

  final glucose = healthLog.latestGlucose;
  if (glucose != null &&
      (glucose < glucoseLowMgDl || glucose > glucoseHighMgDl)) {
    readings.add(EmergencyReading(
      label: 'blood glucose',
      valueText: '${glucose.toStringAsFixed(0)} milligrams per deciliter',
    ));
  }

  return EmergencySummary(
    readings: readings,
    durationText: readings.isEmpty
        ? null
        : _abnormalDurationText(historyStore.recentVitals(limit: 500)),
    location: location,
    triggerReason: triggerReason,
  );
}

/// Walks the vitals history backward from the most recent sample while it
/// stays outside its own threshold, and reports how long that streak has
/// lasted. Returns null (never a guessed number) when the streak is too
/// short to state with any confidence, or there's no history to check —
/// callers then simply omit a duration claim rather than fabricate one.
String? _abnormalDurationText(List<Map> vitalsRecords) {
  if (vitalsRecords.isEmpty) return null;
  DateTime? earliestAbnormal;
  for (var i = vitalsRecords.length - 1; i >= 0; i--) {
    final record = vitalsRecords[i];
    final at = DateTime.tryParse(record['receivedAt'] as String? ?? '');
    if (at == null) break;
    final hr = (record['heartRate'] as num?)?.toDouble() ?? 0;
    final spo2 = (record['spo2'] as num?)?.toDouble() ?? 0;
    final bodyTemp = (record['bodyTempC'] as num?)?.toDouble() ?? 0;
    final abnormal = hr < heartRateFloor ||
        hr > heartRateCeiling(null) ||
        (spo2 > 0 && spo2 < spo2FloorPercent) ||
        bodyTemp > bodyTempHighC ||
        bodyTemp < bodyTempLowC;
    if (!abnormal) break;
    earliestAbnormal = at;
  }
  if (earliestAbnormal == null) return null;
  final minutes = DateTime.now().difference(earliestAbnormal).inMinutes;
  if (minutes < 1) return null;
  return 'approximately $minutes minute${minutes == 1 ? '' : 's'}';
}

String _readingSentences(List<EmergencyReading> readings) => readings
    .map((r) => 'Their ${r.label} is currently ${r.valueText}.')
    .join(' ');

/// Spoken to the emergency-services dispatcher (once, over the device
/// speaker — see ARCHITECTURE.md on why TTS can't be injected into the
/// call's own audio path).
String buildEmergencyServicesScript(EmergencySummary s) {
  final parts = <String>[
    'This is an automated medical emergency alert from a health monitoring application.',
    'The user may require immediate medical assistance — ${s.triggerReason}.',
  ];
  if (s.hasSpecificData) {
    parts.add(_readingSentences(s.readings));
    if (s.durationText != null) {
      parts.add('These readings have remained abnormal for ${s.durationText}.');
    }
  } else {
    parts.add('Specific vital sign data is not currently available.');
  }
  parts.add("The user's current location is ${s.location.text}.");
  parts.add('Please send emergency medical assistance.');
  return parts.join(' ');
}

/// Spoken to the emergency contact after the emergency-services call ends.
String buildContactScript(EmergencySummary s) {
  final parts = <String>[
    'This is an automated emergency alert.',
    'A medical emergency was detected for the user — ${s.triggerReason}.',
  ];
  if (s.hasSpecificData) {
    parts.add(_readingSentences(s.readings));
  } else {
    parts.add('Specific vital sign data is not currently available.');
  }
  parts.add("Their location is ${s.location.text}.");
  parts.add('Emergency services have already been contacted.');
  parts.add('Please check on the user immediately.');
  return parts.join(' ');
}

/// SMS fallback sent only if the contact never answers after 5 attempts.
String buildEmergencySms(EmergencySummary s) {
  final lines = <String>[
    'EMERGENCY ALERT: Possible medical emergency detected.'
  ];
  if (s.hasSpecificData) {
    for (final r in s.readings) {
      lines.add('${_capitalize(r.label)}: ${r.valueText}');
    }
    if (s.durationText != null) {
      lines.add('Duration: ${s.durationText}');
    }
  } else {
    lines.add('Specific vital sign data was not available.');
  }
  lines.add('Location: ${s.location.text}');
  lines.add('Emergency services were contacted. The emergency contact could '
      'not be reached after 5 call attempts.');
  return lines.join('\n');
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
