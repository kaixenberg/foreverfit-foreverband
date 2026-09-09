/// One raw, editable Hive entry — the box's own key plus its timestamp
/// and whatever fields it stores (a single 'value', or 'systolic'/
/// 'diastolic', or 'dose'/'type', etc., depending on the metric). Used by
/// MetricsStore/HealthLogStore to expose entries that can be individually
/// edited or deleted, as opposed to MetricPoint's chart-only (at, value)
/// pairs which don't carry enough identity for that.
class StoredEntry {
  final dynamic key;
  final DateTime at;
  final Map<String, dynamic> data;

  const StoredEntry({required this.key, required this.at, required this.data});
}
