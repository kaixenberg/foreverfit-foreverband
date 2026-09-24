/// One signal that fed into the composite wellness score, plus enough
/// context to explain itself on the detail screen — e.g. "Heart rate:
/// 132 bpm (ceiling 120 while still)".
class WellnessFactor {
  final String label;
  final bool warn;
  final String detail;

  /// Whether this signal currently has a trustworthy reading to judge —
  /// false while e.g. there's no finger/wrist contact yet. `warn` is
  /// always false when this is false (nothing to warn about), so the
  /// detail screen needs this separately to avoid showing a reassuring
  /// checkmark for a signal that isn't actually being measured.
  final bool scored;

  const WellnessFactor({
    required this.label,
    required this.warn,
    required this.detail,
    this.scored = true,
  });
}

/// Snapshot backing both the Dashboard's Wellness card and its detail
/// screen — built once per build from DashboardScreen's already-computed
/// warning flags, so the two views can never disagree with each other.
class WellnessSnapshot {
  final int? score;
  final List<WellnessFactor> factors;

  /// Whether the wearable is currently BLE-connected — used only to pick
  /// the right nudge when [score] is null: "connect it" vs. "wear it".
  final bool connected;

  const WellnessSnapshot({
    required this.score,
    required this.factors,
    this.connected = false,
  });

  String get headline {
    final s = score;
    if (s == null) return connected ? 'Wear your wearable' : 'Connect your wearable';
    if (s >= 90) return 'All clear';
    if (s >= 70) return 'Doing fine';
    if (s >= 50) return 'Take it easy';
    return 'Pay attention';
  }

  String get summary {
    if (score == null) {
      return connected
          ? 'Wellness needs skin contact to read vitals — put the '
              'wearable on your wrist to start scoring.'
          : 'Wellness needs live vitals from the wearable to compute — '
              'connect it from the Dashboard to start scoring.';
    }
    final concerning = factors.where((f) => f.warn).toList();
    if (concerning.isEmpty) {
      return 'Every signal currently being tracked is within its normal '
          'range for you right now.';
    }
    final names = concerning.map((f) => f.label.toLowerCase()).join(', ');
    return 'Score is down mainly because of: $names. See the breakdown '
        'below for specifics.';
  }
}
