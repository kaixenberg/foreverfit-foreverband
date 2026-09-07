/// One signal that fed into the composite wellness score, plus enough
/// context to explain itself on the detail screen — e.g. "Heart rate:
/// 132 bpm (ceiling 120 while still)".
class WellnessFactor {
  final String label;
  final bool warn;
  final String detail;

  const WellnessFactor(
      {required this.label, required this.warn, required this.detail});
}

/// Snapshot backing both the Dashboard's Wellness card and its detail
/// screen — built once per build from DashboardScreen's already-computed
/// warning flags, so the two views can never disagree with each other.
class WellnessSnapshot {
  final int? score;
  final List<WellnessFactor> factors;

  const WellnessSnapshot({required this.score, required this.factors});

  String get headline {
    final s = score;
    if (s == null) return 'Connect your wearable';
    if (s >= 90) return 'All clear';
    if (s >= 70) return 'Doing fine';
    if (s >= 50) return 'Take it easy';
    return 'Pay attention';
  }

  String get summary {
    if (score == null) {
      return 'Wellness needs live vitals from the wearable to compute — '
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
