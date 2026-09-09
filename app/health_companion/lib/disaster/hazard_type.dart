import 'package:flutter/material.dart';

/// Hazard types the full-screen imminent-warning flow knows how to explain.
/// See ARCHITECTURE.md — the guidance text is static and bundled (no data
/// source needed), matching the "get under a table" style safety checklist
/// the roadmap called for.
enum HazardType { earthquake, flood, cyclone, heatWave, stormApproaching }

class HazardGuidance {
  final String title;
  final IconData icon;
  final List<String> actions;

  const HazardGuidance({
    required this.title,
    required this.icon,
    required this.actions,
  });
}

const Map<HazardType, HazardGuidance> hazardGuidance = {
  HazardType.earthquake: HazardGuidance(
    title: 'Earthquake',
    icon: Icons.vibration,
    actions: [
      'Drop, Cover, and Hold On — get under a sturdy table or desk',
      'Stay away from windows, mirrors, and furniture that could fall',
      'If outdoors, move to open ground away from buildings and power lines',
      'Do not use elevators',
    ],
  ),
  HazardType.flood: HazardGuidance(
    title: 'Flood',
    icon: Icons.flood,
    actions: [
      'Move to higher ground immediately',
      'Avoid walking or driving through flood water',
      'Turn off electrical appliances if water is rising indoors',
      'Keep emergency supplies (water, medicines, documents) ready to grab',
    ],
  ),
  HazardType.cyclone: HazardGuidance(
    title: 'Cyclone / storm',
    icon: Icons.cyclone,
    actions: [
      'Stay indoors, away from windows and glass doors',
      'Secure loose outdoor objects only if you can do so safely',
      'Keep a battery-powered light and a charged phone ready',
      'Avoid travel until the storm passes',
    ],
  ),
  HazardType.heatWave: HazardGuidance(
    title: 'Heat wave',
    icon: Icons.wb_sunny,
    actions: [
      'Stay hydrated — drink water even if not thirsty',
      'Avoid outdoor activity during peak heat hours (12pm-4pm)',
      'Wear light-colored, loose-fitting clothing',
      'Watch for dizziness, nausea, or cramps — signs of heat exhaustion',
    ],
  ),
  HazardType.stormApproaching: HazardGuidance(
    title: 'Sudden weather change approaching',
    icon: Icons.thunderstorm,
    actions: [
      'A rapid drop in barometric pressure usually means a storm is '
          'moving in within a few hours',
      'Move indoors and stay away from windows and glass doors',
      'Secure or bring in loose outdoor objects only if you can do so safely',
      'Postpone travel until conditions stabilize',
      'Keep a charged phone and a light source ready',
    ],
  ),
};
