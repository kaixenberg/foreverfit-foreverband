import 'package:flutter/material.dart';

import '../disaster/hazard_type.dart';
import '../services/alarm_sound_service.dart';

/// Full-screen, explicit-acknowledgment-only warning for imminent hazards —
/// distinct from the Map screen's dismissible "elevated risk" banner. This
/// is meant to be hard to miss and hard to swipe away by accident; it also
/// loops a siren through the alarm audio stream so it's audible even with
/// the phone silenced.
class ImminentWarningScreen extends StatefulWidget {
  const ImminentWarningScreen({
    super.key,
    required this.hazards,
    this.reason,
  });

  final List<HazardType> hazards;

  /// Human-readable explanation of why this fired (e.g. "M5.8 earthquake
  /// 42km away"), or null when shown as a manual preview.
  final String? reason;

  @override
  State<ImminentWarningScreen> createState() => _ImminentWarningScreenState();
}

class _ImminentWarningScreenState extends State<ImminentWarningScreen> {
  final _alarm = AlarmSoundService();

  @override
  void initState() {
    super.initState();
    _alarm.start();
  }

  @override
  void dispose() {
    _alarm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hazards = widget.hazards;
    final reason = widget.reason;
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: scheme.error,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.warning_amber_rounded, color: scheme.onError, size: 56),
                const SizedBox(height: 12),
                Text(
                  hazards.length == 1
                      ? '${hazardGuidance[hazards.first]!.title} warning'
                      : 'Multiple hazard warning',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: scheme.onError,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (reason != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    reason,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: scheme.onError),
                  ),
                ],
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    children: [
                      for (final hazard in hazards) _HazardCard(hazard: hazard),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.onError,
                    foregroundColor: scheme.error,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'I understand',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HazardCard extends StatelessWidget {
  const _HazardCard({required this.hazard});

  final HazardType hazard;

  @override
  Widget build(BuildContext context) {
    final guidance = hazardGuidance[hazard]!;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.onError,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(guidance.icon, color: scheme.error),
                const SizedBox(width: 8),
                Text(
                  guidance.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold, color: scheme.error),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final action in guidance.actions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 6, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(action)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
