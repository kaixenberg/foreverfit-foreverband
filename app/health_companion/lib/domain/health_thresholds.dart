/// Shared clinical/reference thresholds — the single source of truth for
/// both DashboardScreen's card-level warn flags and
/// domain/insight_engine.dart's suggestions, so the two can't quietly
/// drift out of sync with each other.
library;

import '../ml/activity_classifier_service.dart';

/// Body temp is suppressed as a WARNING signal (though still shown as a
/// value) for this long after the wearable connects — the DS18B20 needs
/// time to reach thermal equilibrium with the wrist, so a reading taken
/// right at connect time tends to still be closer to ambient/room temp
/// than a genuine skin-temperature reading, which would otherwise read as
/// a false "low body temperature" warning. See dashboard_screen.dart,
/// insight_engine.dart, emergency_summary_builder.dart.
const bodyTempEquilibrationWindow = Duration(minutes: 1);

/// Heart-rate ceiling above which a reading is flagged, conditioned on
/// what the user is currently doing — a fixed threshold can't tell
/// "elevated HR because you're running" from "elevated HR while sitting
/// still," so it either misses real anomalies at rest or false-alarms
/// during exercise. See ARCHITECTURE.md's AI/ML roadmap item 1.
int heartRateCeiling(Activity? activity) {
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

const heartRateFloor = 50;
const spo2FloorPercent = 92;
const bodyTempHighC = 37.8;
const bodyTempLowC = 35.5;

// Standard AHA hypertension thresholds (mmHg).
const bpSystolicHighMmHg = 140;
const bpDiastolicHighMmHg = 90;
const bpSystolicCrisisMmHg = 180;
const bpDiastolicCrisisMmHg = 120;

// Standard ADA glucose range (mg/dL, non-fasting reference).
const glucoseLowMgDl = 70;
const glucoseHighMgDl = 180;

const sleepLowHours = 6.0;

// NOAA/AirNow US AQI category boundary already used by DisasterRisk —
// duplicated here as a named constant since disaster_service.dart's
// version is a private getter, not something to import from a UI layer.
const aqiUnhealthy = 150;
const aqiVeryUnhealthy = 300;
