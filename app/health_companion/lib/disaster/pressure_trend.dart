/// Pure math for detecting a rapid barometric pressure fall — a genuine,
/// live early-warning signal for an approaching storm, independent of any
/// forecast probability or static "prone area" flag. A sustained fall of
/// >=3 hPa within 3 hours is a widely used marine/aviation "rapid pressure
/// fall" warning threshold (e.g. the UK Met Office and Australian BoM both
/// use a comparable "sudden/rapid fall of barometer" trigger in small-craft
/// warnings) that reliably precedes deteriorating weather, regardless of
/// what a longer-range forecast predicts. Kept dependency-free (no Hive/
/// http) so it's unit-testable, matching this project's "formula over
/// black box" pattern (see body_composition.dart, fall_inference.dart).
library;

const pressureTrendWindow = Duration(hours: 3);
const pressureTrendMaxHistory = Duration(hours: 6);

/// Minimum span of history required before a drop is reported — otherwise
/// a fresh install/reconnect with only a couple of samples a few minutes
/// apart could read as a "3 hPa fall" from ordinary sensor noise.
const pressureTrendMinCoverage = Duration(hours: 2);

const rapidPressureFallHPa = 3.0;

class PressureSample {
  final DateTime at;
  final double hPa;

  const PressureSample(this.at, this.hPa);

  Map<String, dynamic> toMap() => {'t': at.toIso8601String(), 'p': hPa};

  static PressureSample? fromMap(Map map) {
    final at = DateTime.tryParse(map['t'] as String? ?? '');
    final hPa = (map['p'] as num?)?.toDouble();
    if (at == null || hPa == null) return null;
    return PressureSample(at, hPa);
  }
}

/// Drops samples older than [pressureTrendMaxHistory] relative to [now].
List<PressureSample> prunePressureSamples(
  List<PressureSample> samples,
  DateTime now,
) =>
    samples
        .where((s) => now.difference(s.at) <= pressureTrendMaxHistory)
        .toList();

/// The pressure drop from the oldest sample within [pressureTrendWindow] of
/// [now] to the most recent sample, or null if there isn't at least
/// [pressureTrendMinCoverage] worth of history yet, or pressure isn't
/// actually falling.
double? pressureDropOverWindow(List<PressureSample> samples, DateTime now) {
  if (samples.isEmpty) return null;
  final sorted = [...samples]..sort((a, b) => a.at.compareTo(b.at));

  final cutoff = now.subtract(pressureTrendWindow);
  final inWindow = sorted.where((s) => !s.at.isBefore(cutoff)).toList();
  if (inWindow.isEmpty) return null;

  final oldest = inWindow.first;
  if (now.difference(oldest.at) < pressureTrendMinCoverage) return null;

  final drop = oldest.hPa - sorted.last.hPa;
  return drop > 0 ? drop : null;
}
