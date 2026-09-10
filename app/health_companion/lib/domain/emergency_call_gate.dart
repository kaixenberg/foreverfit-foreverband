import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/emergency_call_screen.dart';
import 'emergency_workflow_service.dart';

/// Wraps the app and watches [EmergencyWorkflowService] — the moment a new
/// run starts, pushes [EmergencyCallScreen] full-screen. Mirrors
/// ImminentWarningGate's `_showing`-guarded addPostFrameCallback pattern.
///
/// Keys off [EmergencyWorkflowService.runId] changing, not off catching
/// `state == emergencyDetected` at the moment this widget happens to
/// rebuild — that state is transient and `start()` itself overwrites it
/// (to `collectingData`) via a Hive write that typically resolves faster
/// than Flutter's next frame, so a check for that exact value was a race
/// this gate would almost always lose, silently never showing the screen.
/// `runId` instead stays at its new value for the whole run, so it's safe
/// to compare against regardless of how far the run has already
/// progressed by the time a frame actually happens.
class EmergencyCallGate extends StatefulWidget {
  const EmergencyCallGate({super.key, required this.child});

  final Widget child;

  @override
  State<EmergencyCallGate> createState() => _EmergencyCallGateState();
}

class _EmergencyCallGateState extends State<EmergencyCallGate> {
  bool _showing = false;
  int _lastHandledRunId = 0;

  @override
  Widget build(BuildContext context) {
    final workflow = context.watch<EmergencyWorkflowService>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow(workflow));
    return widget.child;
  }

  void _maybeShow(EmergencyWorkflowService workflow) {
    if (!mounted || _showing) return;
    if (workflow.runId == _lastHandledRunId) return;

    _lastHandledRunId = workflow.runId;
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
