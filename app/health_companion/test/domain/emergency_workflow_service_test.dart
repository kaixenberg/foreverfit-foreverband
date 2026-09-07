import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/domain/emergency_location.dart';
import 'package:health_companion/domain/emergency_summary_builder.dart';
import 'package:health_companion/domain/emergency_workflow_service.dart';
import 'package:health_companion/models/emergency_state.dart';
import 'package:health_companion/services/telephony_service.dart';
import 'package:health_companion/storage/emergency_contact_store.dart';

import '../support/fakes.dart';

/// Short, deterministic timing so the suite runs in well under a second —
/// see EmergencyWorkflowService's constructor params. `answerGrace` must
/// sit strictly between the fakes' unanswered and answered hold durations.
const _answerGrace = Duration(milliseconds: 50);
const _dialTimeout = Duration(milliseconds: 300);
const _callEndTimeout = Duration(milliseconds: 300);
const _retryDelay = Duration(milliseconds: 20);

EmergencySummary _fixedSummary({
  required EmergencyLocation location,
  required String triggerReason,
}) {
  return EmergencySummary(
    readings: const [
      EmergencyReading(label: 'heart rate', valueText: '145 beats per minute'),
    ],
    durationText: 'approximately 4 minutes',
    location: location,
    triggerReason: triggerReason,
  );
}

class _ThrowingLocationService implements EmergencyLocationService {
  @override
  Future<EmergencyLocation> resolve() async =>
      throw Exception('GPS unavailable');
}

void main() {
  late FakeTelephonyService telephony;
  late FakeTtsService tts;

  EmergencyWorkflowService buildWorkflow({
    EmergencyLocationService? locationService,
    EmergencyContactStore? contactStore,
    EmergencySummaryBuilder? summaryBuilder,
  }) {
    return EmergencyWorkflowService(
      telephony: telephony,
      tts: tts,
      locationService: locationService ?? FakeLocationService(),
      contactStore: contactStore ??
          EmergencyContactStore.forTesting(
            contactPhone: '+15550001111',
            mockMode:
                false, // route through the injected fake, not MockTelephonyService
          ),
      summaryBuilder: summaryBuilder ?? _fixedSummary,
      answerGrace: _answerGrace,
      dialTimeout: _dialTimeout,
      callEndTimeout: _callEndTimeout,
      retryDelay: _retryDelay,
    );
  }

  setUp(() {
    telephony = FakeTelephonyService()
      ..answeredHoldDuration = const Duration(milliseconds: 150)
      ..unansweredHoldDuration = const Duration(milliseconds: 10)
      ..offHookDelay = const Duration(milliseconds: 5);
    tts = FakeTtsService();
  });

  tearDown(() => telephony.dispose());

  test('1. happy path: emergency call connects, contact answers on attempt 1',
      () async {
    telephony.contactAnswersOnAttempt = 1;
    final workflow = buildWorkflow();

    await workflow.start(triggerReason: 'a possible fall was detected');

    expect(workflow.state, EmergencyWorkflowState.completed);
    expect(telephony.dialedEmergencyNumbers, ['112']);
    expect(telephony.calledContactNumbers, ['+15550001111']);
    expect(telephony.sentSmsText, isEmpty);
    expect(
        tts.spoken.length, 2); // services announcement + contact announcement
  });

  test(
      '2. emergency call never goes off-hook — workflow still proceeds to contact',
      () async {
    telephony.emergencyCallConnects = false;
    telephony.contactAnswersOnAttempt = 1;
    final workflow = buildWorkflow();

    await workflow.start(triggerReason: 'a possible fall was detected');

    expect(workflow.state, EmergencyWorkflowState.completed);
    expect(telephony.dialedEmergencyNumbers, ['112']);
    // No services-call announcement (never went live), only the contact one.
    expect(tts.spoken.length, 1);
    expect(telephony.calledContactNumbers, ['+15550001111']);
  });

  test(
      '3 & 4. contact does not answer, retries, answers on attempt 3 — then stops',
      () async {
    telephony.contactAnswersOnAttempt = 3;
    final workflow = buildWorkflow();

    await workflow.start(triggerReason: 'the user manually requested help');

    expect(workflow.state, EmergencyWorkflowState.completed);
    expect(telephony.calledContactNumbers.length, 3);
    expect(telephony.sentSmsText, isEmpty);
    // Contact script spoken exactly once even though it "ended" after
    // being answered — answering must not trigger another retry.
    expect(tts.spoken.where((s) => s.contains('check on the user')).length, 1);
  });

  test('5. contact never answers — exactly 5 attempts, then SMS, then stops',
      () async {
    telephony.contactAnswersOnAttempt = null;
    final workflow = buildWorkflow();

    await workflow.start(triggerReason: 'a possible fall was detected');

    expect(workflow.state, EmergencyWorkflowState.completed);
    expect(telephony.calledContactNumbers.length, 5);
    expect(telephony.sentSmsText.length, 1);
    expect(telephony.sentSmsText.single, contains('EMERGENCY ALERT'));
    expect(telephony.sentSmsText.single, contains('5 call attempts'));
  });

  test('6 & 8. location unavailable — falls back gracefully, no crash',
      () async {
    telephony.contactAnswersOnAttempt = 1;
    EmergencyLocation? capturedLocation;
    final workflow = buildWorkflow(
      locationService: _ThrowingLocationService(),
      summaryBuilder: ({required location, required triggerReason}) {
        capturedLocation = location;
        return _fixedSummary(location: location, triggerReason: triggerReason);
      },
    );

    await workflow.start(triggerReason: 'a possible fall was detected');

    expect(workflow.state, EmergencyWorkflowState.completed);
    expect(capturedLocation?.text, 'Location unavailable');
    expect(capturedLocation?.isAvailable, false);
  });

  test('7. missing CALL_PHONE permission — reaches failed, does not crash',
      () async {
    telephony.callContactError =
        TelephonyPermissionException('CALL_PHONE denied');
    final workflow = buildWorkflow();

    await workflow.start(triggerReason: 'a possible fall was detected');

    expect(workflow.state, EmergencyWorkflowState.failed);
    expect(telephony.calledContactNumbers, isEmpty);
    expect(telephony.sentSmsText, isEmpty);
  });

  test(
      '9. missing SEND_SMS permission — SMS failure logged, workflow still completes',
      () async {
    telephony.contactAnswersOnAttempt = null; // forces the SMS fallback path
    telephony.sendSmsError = TelephonyPermissionException('SEND_SMS denied');
    final workflow = buildWorkflow();

    await workflow.start(triggerReason: 'a possible fall was detected');

    expect(workflow.state, EmergencyWorkflowState.completed);
    expect(telephony.sentSmsText, isEmpty); // send was attempted but failed
    expect(
        workflow.log.any((line) => line.contains('SMS fallback failed')), true);
  });

  test('10. TTS fails — logged, workflow continues rather than hanging',
      () async {
    telephony.contactAnswersOnAttempt = 1;
    tts.speakError = Exception('TTS engine unavailable');
    final workflow = buildWorkflow();

    await workflow.start(triggerReason: 'a possible fall was detected');

    expect(workflow.state, EmergencyWorkflowState.completed);
    expect(tts.spoken, isEmpty);
    expect(
        workflow.log.where((l) => l.contains('Text-to-speech failed')).length,
        2);
  });

  test('11. triggered twice simultaneously — second call is a no-op', () async {
    telephony.contactAnswersOnAttempt = 1;
    final workflow = buildWorkflow();

    final first = workflow.start(triggerReason: 'a possible fall was detected');
    final second =
        workflow.start(triggerReason: 'the user manually requested help');
    await Future.wait([first, second]);

    expect(telephony.dialedEmergencyNumbers.length, 1);
    expect(telephony.calledContactNumbers.length, 1);
    expect(
        workflow.log
            .any((l) => l.contains('Ignored duplicate emergency trigger')),
        true);
  });

  test(
      'cancel() while TTS is speaking unblocks the workflow instead of hanging',
      () async {
    // Regression test — reproduces the reported bug where the Cancel
    // button got stuck on "Cancelling…" during
    // announcingToEmergencyServices because _speakSafely awaited
    // tts.speak() with no way out.
    tts.hangForever = true;
    final workflow = buildWorkflow();

    final future =
        workflow.start(triggerReason: 'a possible fall was detected');
    // Let it reach the "speaking to emergency services" step, which is
    // stuck on speak() forever until cancelled.
    await Future.delayed(const Duration(milliseconds: 30));
    expect(
        workflow.state, EmergencyWorkflowState.announcingToEmergencyServices);

    final sw = Stopwatch()..start();
    workflow.cancel();
    await future.timeout(const Duration(seconds: 2));
    sw.stop();

    expect(workflow.state, EmergencyWorkflowState.cancelled);
    expect(sw.elapsedMilliseconds, lessThan(1000));
    expect(tts.stopCallCount, greaterThan(0));
  });

  test('cancel() takes effect within a tick, not only after the full timeout',
      () async {
    telephony.contactAnswersOnAttempt =
        null; // would otherwise wait out the full timeout
    // A much longer timeout than the cancel should ever need to wait for —
    // proves cancellation isn't just "wait it out and land on cancelled".
    final slowWorkflow = EmergencyWorkflowService(
      telephony: telephony,
      tts: tts,
      locationService: FakeLocationService(),
      contactStore: EmergencyContactStore.forTesting(
        contactPhone: '+15550001111',
        mockMode: false,
      ),
      summaryBuilder: _fixedSummary,
      answerGrace: _answerGrace,
      dialTimeout: const Duration(seconds: 5),
      callEndTimeout: const Duration(seconds: 5),
      retryDelay: const Duration(seconds: 2),
    );

    final future =
        slowWorkflow.start(triggerReason: 'a possible fall was detected');
    // Let the workflow get into the contact-retry loop, then cancel.
    await Future.delayed(const Duration(milliseconds: 60));
    final sw = Stopwatch()..start();
    slowWorkflow.cancel();
    await future;
    sw.stop();

    expect(slowWorkflow.state, EmergencyWorkflowState.cancelled);
    expect(sw.elapsedMilliseconds,
        lessThan(1000)); // nowhere near the 5s/2s timeouts
    expect(
        telephony.sentSmsText, isEmpty); // must not have reached SMS fallback
    expect(telephony.calledContactNumbers.length, lessThan(5));
  });

  test(
      'cancel() while the contact call is answered lands on cancelled, not completed',
      () async {
    telephony.contactAnswersOnAttempt = 1;
    telephony.answeredHoldDuration = const Duration(seconds: 5); // long "call"
    final workflow = buildWorkflow(
      summaryBuilder: _fixedSummary,
    );

    final future =
        workflow.start(triggerReason: 'a possible fall was detected');
    // Wait long enough for the contact to "answer" (past answerGrace) but
    // well before the simulated call would naturally end.
    await Future.delayed(const Duration(milliseconds: 150));
    workflow.cancel();
    await future;

    expect(workflow.state, EmergencyWorkflowState.cancelled);
  });

  test(
      'no contact configured — fails cleanly instead of crashing or SMS-ing nothing',
      () async {
    final workflow = buildWorkflow(
      contactStore:
          EmergencyContactStore.forTesting(contactPhone: '', mockMode: false),
    );

    await workflow.start(triggerReason: 'a possible fall was detected');

    expect(workflow.state, EmergencyWorkflowState.failed);
    expect(telephony.calledContactNumbers, isEmpty);
    expect(telephony.sentSmsText, isEmpty);
  });
}
