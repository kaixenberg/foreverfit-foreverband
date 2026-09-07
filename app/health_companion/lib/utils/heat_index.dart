/// Heat index (how hot it "feels", combining temperature + humidity) via
/// the NOAA/Rothfusz regression — a well-established closed-form formula,
/// not a trained model. See ARCHITECTURE.md's AI/ML roadmap item 3: the
/// originally-scoped heat-stress CNN (WESAD dataset) was dropped after
/// direct verification found the same kind of dead end as the flood
/// dataset earlier (both known mirrors 404, and its chest/wrist
/// ECG/EMG/EDA signals don't map onto what this app's wearable actually
/// streams — no ECG/EDA, no SpO2 in WESAD). This heuristic uses sensors
/// this app genuinely has (BME280 ambient temp + humidity) and, per the
/// composite-wellness-score philosophy, only reaches for a trained model
/// if a formula demonstrably underperforms.
///
/// Rothfusz regression is calibrated in Fahrenheit and only valid above
/// ~80°F (26.7°C); below that the "feels like" temperature is just the
/// air temperature itself, so this returns [ambientC] unchanged there.
double heatIndexCelsius(double ambientC, double humidityPercent) {
  if (ambientC < 26.7) return ambientC;

  final t = ambientC * 9 / 5 + 32; // to Fahrenheit
  final r = humidityPercent;

  final hiF = -42.379 +
      2.04901523 * t +
      10.14333127 * r -
      0.22475541 * t * r -
      0.00683783 * t * t -
      0.05481717 * r * r +
      0.00122874 * t * t * r +
      0.00085282 * t * r * r -
      0.00000199 * t * t * r * r;

  return (hiF - 32) * 5 / 9; // back to Celsius
}

enum HeatRisk { normal, caution, extremeCaution, danger }

/// Thresholds per NOAA's heat index chart (80/90/103°F -> °C).
HeatRisk heatRiskLevel(double heatIndexC) {
  if (heatIndexC >= 39.4) return HeatRisk.danger; // 103°F
  if (heatIndexC >= 32.2) return HeatRisk.extremeCaution; // 90°F
  if (heatIndexC >= 26.7) return HeatRisk.caution; // 80°F
  return HeatRisk.normal;
}

/// Elevated heat-stress concern: a dangerous heat index AND a body
/// temperature already trending up — either signal alone is common and
/// often benign (hot weather, or a slightly warm reading), but together
/// they're a more specific signal worth flagging.
bool isHeatStressRisk({
  required double ambientC,
  required double humidityPercent,
  required double bodyTempC,
}) {
  final risk = heatRiskLevel(heatIndexCelsius(ambientC, humidityPercent));
  return risk == HeatRisk.danger ||
      (risk == HeatRisk.extremeCaution && bodyTempC > 37.5);
}
