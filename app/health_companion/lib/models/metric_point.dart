/// A single timestamped value — the shared shape for every chartable
/// metric (weight, height, body fat, hydration, steps), regardless of
/// which store it actually lives in.
class MetricPoint {
  final DateTime at;
  final double value;

  const MetricPoint({required this.at, required this.value});
}
