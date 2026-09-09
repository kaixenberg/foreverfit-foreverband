import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../ml/fall_detector_service.dart';
import 'emergency_workflow_service.dart';

/// Listens on the native `escalation` channel (`MainActivity.kt`) for
/// `onEscalationRoute` calls — fired when the app was brought to the
/// foreground by an escalation launch
/// (`FlutterForegroundTask.launchApp('escalate_...')`, from either the
/// background fall-detection service in
/// `lib/background/fall_detection_task_handler.dart` or the developer/demo
/// trigger in `lib/domain/demo_escalation_trigger.dart`).
///
/// `route == 'escalate_fall'` immediately runs the existing emergency-
/// call workflow, skipping the in-app 10-second countdown since it
/// already elapsed in the background. `route == 'escalate_disaster'`
/// needs no action here — bringing the app forward is enough:
/// `ImminentWarningGate` refreshes `DisasterService` on resume and shows
/// the warning itself once the fresh risk data is in, exactly as it
/// already does for a live in-app detection. `route == 'escalate_demo'`
/// starts the same emergency-call workflow forced into mock mode, so the
/// developer/demo lock-screen preview can never place a real call.
class BackgroundEscalationGate extends StatefulWidget {
  const BackgroundEscalationGate({super.key, required this.child});

  final Widget child;

  @override
  State<BackgroundEscalationGate> createState() =>
      _BackgroundEscalationGateState();
}

class _BackgroundEscalationGateState extends State<BackgroundEscalationGate> {
  static const _channel =
      MethodChannel('com.example.health_companion/escalation');

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_onMethodCall);
  }

  Future<void> _onMethodCall(MethodCall call) async {
    if (call.method != 'onEscalationRoute') return;
    final route = call.arguments as String?;
    if (!mounted) return;
    if (route == 'escalate_fall') {
      context.read<FallDetectorService>().triggerBackgroundEscalatedCall();
    } else if (route == 'escalate_demo') {
      context.read<EmergencyWorkflowService>().start(
            triggerReason: 'developer demo — lock-screen SOS escalation '
                'preview, no real emergency',
            forceMock: true,
          );
    }
    // 'escalate_disaster' needs no action — see the class doc comment.
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
