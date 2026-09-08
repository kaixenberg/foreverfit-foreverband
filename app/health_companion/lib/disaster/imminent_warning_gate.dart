import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/imminent_warning_screen.dart';
import 'disaster_service.dart';
import 'hazard_type.dart';

/// Wraps the app and watches [DisasterService] for hazards crossing the
/// imminent-warning threshold, pushing [ImminentWarningScreen] full-screen
/// the moment they appear. Dedupes so the same hazard set doesn't
/// re-trigger on every refresh — only a *new* imminent hazard reopens it.
class ImminentWarningGate extends StatefulWidget {
  const ImminentWarningGate({super.key, required this.child});

  final Widget child;

  @override
  State<ImminentWarningGate> createState() => _ImminentWarningGateState();
}

class _ImminentWarningGateState extends State<ImminentWarningGate>
    with WidgetsBindingObserver {
  Set<HazardType> _lastShown = {};
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-checks risk on resume — including when the app was brought
    // forward by the background service's disaster-escalation launch
    // (see BackgroundEscalationGate/fall_detection_task_handler.dart),
    // so this gate sees fresh imminentHazards immediately rather than
    // waiting for whatever periodic refresh would otherwise run next.
    if (state == AppLifecycleState.resumed) {
      context.read<DisasterService>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final disaster = context.watch<DisasterService>();
    final hazards = disaster.risk?.imminentHazards ?? const <HazardType>[];

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeShow(hazards, disaster));

    return widget.child;
  }

  void _maybeShow(List<HazardType> hazards, DisasterService disaster) {
    if (!mounted || _showing || hazards.isEmpty) return;
    final hazardSet = hazards.toSet();
    if (hazardSet.difference(_lastShown).isEmpty) return;

    _lastShown = hazardSet;
    _showing = true;
    Navigator.of(context, rootNavigator: true)
        .push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => ImminentWarningScreen(
              hazards: hazards,
              reason: disaster.risk?.imminentReason,
            ),
          ),
        )
        .then((_) => _showing = false);
  }
}
