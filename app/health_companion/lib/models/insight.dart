import 'package:flutter/material.dart';

enum InsightSeverity { info, warning, critical }

enum InsightCategory { vitals, hazard, reminder }

/// One rule-based suggestion or warning — the output of
/// `lib/domain/insight_engine.dart`. Deliberately not ML-generated: see
/// ARCHITECTURE.md for why a transparent rule engine fits this app's
/// existing "formula over black box" pattern (the wellness score,
/// personalized baseline, and heat index are all the same choice).
class Insight {
  /// Stable across recomputations for the same underlying condition —
  /// used both as a Flutter list key and to decide whether a
  /// notification for this exact condition already fired.
  final String id;
  final String title;
  final String message;
  final InsightSeverity severity;
  final InsightCategory category;
  final IconData icon;

  const Insight({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.category,
    required this.icon,
  });
}
