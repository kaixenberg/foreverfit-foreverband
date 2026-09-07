import 'dart:async';

import 'package:health_companion/domain/emergency_location.dart';
import 'package:health_companion/models/emergency_state.dart';
import 'package:health_companion/services/telephony_service.dart';
import 'package:health_companion/services/tts_service.dart';

/// Fully scriptable fake used to unit-test EmergencyWorkflowService's
/// state machine without touching real telephony. Distinct from
/// MockTelephonyService (the shipped runtime "test mode" feature) — this
/// one is test-only and lets each test dictate exact outcomes.
class FakeTelephonyService implements TelephonyService {
  final _controller = StreamController<CallState>.broadcast();

  List<String> emergencyNumbers = ['112'];
  final List<String> dialedEmergencyNumbers = [];
  final List<String> calledContactNumbers = [];
  final List<String> sentSmsText = [];
  bool speakerphoneOn = false;

  /// If true, an emergency-services dial never goes off-hook (simulates
  /// the user never tapping Call in the dialer, or the call failing
  /// silently) — scenario 2.
  bool emergencyCallConnects = true;

  /// Which contact-call attempt (1-based) "answers" — null means never.
  int? contactAnswersOnAttempt;

  /// How long a simulated off-hook is held once started — must exceed the
  /// workflow's `answerGrace` for "answered", or be shorter for
  /// "not answered". Tests pass a short `answerGrace` to keep this fast.
  Duration answeredHoldDuration = const Duration(milliseconds: 120);
  Duration unansweredHoldDuration = const Duration(milliseconds: 10);
  Duration offHookDelay = const Duration(milliseconds: 5);

  Exception? callContactError;
  Exception? sendSmsError;

  int _contactAttempts = 0;

  @override
  Future<List<String>> getEmergencyNumbers() async => emergencyNumbers;

  @override
  Future<void> dialEmergencyNumber(String number) async {
    dialedEmergencyNumbers.add(number);
    if (!emergencyCallConnects) return;
    _simulateCall(hold: answeredHoldDuration);
  }

  @override
  Future<void> callContact(String number) async {
    if (callContactError != null) throw callContactError!;
    _contactAttempts++;
    calledContactNumbers.add(number);
    final willAnswer = contactAnswersOnAttempt != null &&
        _contactAttempts >= contactAnswersOnAttempt!;
    _simulateCall(
        hold: willAnswer ? answeredHoldDuration : unansweredHoldDuration);
  }

  void _simulateCall({required Duration hold}) {
    Future.delayed(offHookDelay, () {
      if (_controller.isClosed) return;
      _controller.add(CallState.offHook);
      Future.delayed(hold, () {
        if (!_controller.isClosed) _controller.add(CallState.idle);
      });
    });
  }

  @override
  Future<void> setSpeakerphoneOn(bool on) async => speakerphoneOn = on;

  @override
  Future<void> sendSms(String number, String text) async {
    if (sendSmsError != null) throw sendSmsError!;
    sentSmsText.add(text);
  }

  @override
  Stream<CallState> get callStateStream => _controller.stream;

  void dispose() => _controller.close();
}

class FakeTtsService implements TtsService {
  final List<String> spoken = [];
  Exception? speakError;
  int stopCallCount = 0;

  /// If set, `speak()` doesn't resolve on its own — used to simulate a
  /// long/stuck announcement so tests can prove cancellation unblocks it
  /// without needing to actually wait out a real duration.
  bool hangForever = false;

  @override
  Future<void> speak(String text) async {
    if (speakError != null) throw speakError!;
    if (hangForever) return Completer<void>().future;
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
  }
}

class FakeLocationService implements EmergencyLocationService {
  FakeLocationService(
      {this.result = const EmergencyLocation(text: '22.5, 88.3')});

  final EmergencyLocation result;

  @override
  Future<EmergencyLocation> resolve() async => result;
}
