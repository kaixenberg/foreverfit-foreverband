import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../ml/fall_detector_service.dart';

/// Listens on the native `escalation` channel (`MainActivity.kt`) for
/// `onEscalationRoute` calls — fired when the app was brought to the
/// foreground by the background fall-detection service's escalation
/// launch (`FlutterForegroundTask.launchApp('escalate_...')` in
/// `lib/background/fall_detection_task_handler.dart`).
///
/// `route == 'escalate_fall'` immediately runs the existing emergency-
/// call workflow, skipping the in-app 10-second countdown since it
/// already elapsed in the background. `route == 'escalate_disaster'`
/// needs no action here — bringing the app forward is enough:
/// `ImminentWarningGate` refreshes `DisasterService` on resume and shows
/// the warning itself once the fresh risk data is in, exactly as it
/// already does for a live in-app detection.
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
    if (route == 'escalate_fall' && mounted) {
      context.read<FallDetectorService>().triggerBackgroundEscalatedCall();
    }
    // 'escalate_disaster' needs no action — see the class doc comment.
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
