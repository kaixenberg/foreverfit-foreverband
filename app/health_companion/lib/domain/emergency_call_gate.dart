import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/emergency_state.dart';
import '../screens/emergency_call_screen.dart';
import 'emergency_workflow_service.dart';

/// Wraps the app and watches [EmergencyWorkflowService] — the moment a new
/// run starts (`emergencyDetected`, set exactly once at the top of
/// `start()`), pushes [EmergencyCallScreen] full-screen. Mirrors
/// ImminentWarningGate's `_showing`-guarded addPostFrameCallback pattern.
///
/// Deliberately keys off that one specific transition rather than "state
/// != idle" — a terminal state (`completed`/`failed`/`cancelled`) is also
/// non-idle and persists until the *next* run starts, so triggering on
/// "non-idle" would re-push the screen on every later rebuild after the
/// user closed it (the app doesn't reset the workflow back to `idle`
/// after finishing — only `start()` does, for the next run).
class EmergencyCallGate extends StatefulWidget {
  const EmergencyCallGate({super.key, required this.child});

  final Widget child;

  @override
  State<EmergencyCallGate> createState() => _EmergencyCallGateState();
}

class _EmergencyCallGateState extends State<EmergencyCallGate> {
  bool _showing = false;

  @override
  Widget build(BuildContext context) {
    final workflow = context.watch<EmergencyWorkflowService>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow(workflow));
    return widget.child;
  }

  void _maybeShow(EmergencyWorkflowService workflow) {
    if (!mounted || _showing) return;
    if (workflow.state != EmergencyWorkflowState.emergencyDetected) return;

    _showing = true;
    Navigator.of(context, rootNavigator: true)
        .push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const EmergencyCallScreen(),
          ),
        )
        .then((_) => _showing = false);
  }
}
