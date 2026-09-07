import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/emergency_workflow_service.dart';
import '../models/emergency_state.dart';

String _stateLabel(EmergencyWorkflowState state, int attempt) {
  switch (state) {
    case EmergencyWorkflowState.idle:
      return 'Idle';
    case EmergencyWorkflowState.emergencyDetected:
      return 'Emergency detected';
    case EmergencyWorkflowState.collectingData:
      return 'Collecting your recent health data…';
    case EmergencyWorkflowState.gettingLocation:
      return 'Getting your location…';
    case EmergencyWorkflowState.generatingMessage:
      return 'Preparing the emergency summary…';
    case EmergencyWorkflowState.callingEmergencyServices:
      return 'Opening the emergency call — please tap Call when the dialer appears';
    case EmergencyWorkflowState.announcingToEmergencyServices:
      return 'Speaking the summary to emergency services…';
    case EmergencyWorkflowState.waitingForEmergencyCallEnd:
      return 'Emergency call in progress…';
    case EmergencyWorkflowState.callingEmergencyContact:
      return 'Calling your emergency contact…';
    case EmergencyWorkflowState.retryingContact:
      return 'Retrying your emergency contact (attempt $attempt of 5)…';
    case EmergencyWorkflowState.announcingToContact:
      return 'Speaking the summary to your contact…';
    case EmergencyWorkflowState.contactNoAnswer:
      return 'No answer — will retry shortly…';
    case EmergencyWorkflowState.smsFallback:
      return 'Contact unreachable after 5 attempts — sending an emergency SMS…';
    case EmergencyWorkflowState.completed:
      return 'Done';
    case EmergencyWorkflowState.failed:
      return 'The workflow could not continue — see the details below';
    case EmergencyWorkflowState.cancelled:
      return 'Cancelled';
  }
}

/// Full-screen status view for the AI-assisted emergency call workflow —
/// mirrors ImminentWarningScreen's shape (blocked back-gesture while
/// active, one explicit way out). Shows the generated summary/scripts and
/// an operational log for transparency, plus a Cancel action — see
/// EmergencyWorkflowService.cancel() for what "cancel" can and can't stop.
class EmergencyCallScreen extends StatelessWidget {
  const EmergencyCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final workflow = context.watch<EmergencyWorkflowService>();
    final scheme = Theme.of(context).colorScheme;
    final isActive = workflow.isActive;

    return PopScope<Object?>(
      // Always poppable — unlike ImminentWarningScreen, this screen isn't
      // safety guidance the user must read before leaving; it's a status
      // view of a workflow that's mostly happening in Android's own
      // dialer/SMS UI anyway. A back press while still active is treated
      // as the same "stop trying further steps" request as the visible
      // Cancel button, rather than being silently swallowed.
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && isActive) workflow.cancel();
      },
      child: Scaffold(
        backgroundColor: scheme.error,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.emergency_outlined, color: scheme.onError, size: 56),
                const SizedBox(height: 12),
                Text(
                  'Emergency response',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: scheme.onError,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                if (workflow.isUsingMockTelephony)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    decoration: BoxDecoration(
                      color: scheme.onError,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'TEST MODE — no real call or SMS will be placed',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: scheme.error, fontWeight: FontWeight.bold),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  _stateLabel(workflow.state, workflow.attempt),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: scheme.onError),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: [
                      if (workflow.servicesScript != null)
                        _ScriptCard(
                          title: 'Emergency services announcement',
                          text: workflow.servicesScript!,
                          scheme: scheme,
                        ),
                      if (workflow.contactScript != null)
                        _ScriptCard(
                          title: 'Emergency contact announcement',
                          text: workflow.contactScript!,
                          scheme: scheme,
                        ),
                      if (workflow.smsText != null)
                        _ScriptCard(
                          title: 'SMS fallback',
                          text: workflow.smsText!,
                          scheme: scheme,
                        ),
                      if (workflow.log.isNotEmpty)
                        _ScriptCard(
                          title: 'Log',
                          text: workflow.log.join('\n'),
                          scheme: scheme,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (isActive)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onError,
                      side: BorderSide(color: scheme.onError),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    // Disabled once pressed — cancel() takes effect within
                    // a tick, not instantly (there's no platform API to
                    // abort a call already dialing), so this avoids a
                    // still-live button reading as "my tap didn't work."
                    onPressed: workflow.cancelRequested
                        ? null
                        : () => workflow.cancel(),
                    child: Text(
                        workflow.cancelRequested ? 'Cancelling…' : 'Cancel'),
                  ),
                if (!isActive) ...[
                  const SizedBox(height: 4),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.onError,
                      foregroundColor: scheme.error,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScriptCard extends StatelessWidget {
  const _ScriptCard(
      {required this.title, required this.text, required this.scheme});

  final String title;
  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.onError,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold, color: scheme.error)),
            const SizedBox(height: 6),
            Text(text, style: TextStyle(color: scheme.error)),
          ],
        ),
      ),
    );
  }
}
