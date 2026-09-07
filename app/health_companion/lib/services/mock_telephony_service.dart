import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/emergency_state.dart';
import '../storage/emergency_contact_store.dart';
import 'telephony_service.dart';

/// Runtime "test/mock mode" implementation — this is what makes it safe to
/// exercise the entire emergency workflow on a real device without ever
/// dialing a real number or sending a real SMS (see the feature's spec:
/// "For development/testing, DO NOT repeatedly call a real emergency
/// number"). `EmergencyWorkflowService` swaps to this whenever
/// `EmergencyContactStore.mockMode` is true; TTS and location still run
/// for real in mock mode (both are harmless), only telephony is faked.
///
/// Logs step names only — never the dialed number or message text, so
/// this stays safe to leave enabled in a debug-mode demo build (see
/// ARCHITECTURE.md's privacy section: no sensitive health data in logs).
class MockTelephonyService implements TelephonyService {
  MockTelephonyService({required this.contactStore});

  final EmergencyContactStore contactStore;

  final _controller = StreamController<CallState>.broadcast();
  int _contactAttempts = 0;

  static const _answeredHoldDuration = Duration(seconds: 8);
  static const _unansweredHoldDuration = Duration(seconds: 2);

  @override
  Future<List<String>> getEmergencyNumbers() async => const ['112 (mock)'];

  @override
  Future<void> dialEmergencyNumber(String number) async {
    debugPrint('[MockTelephony] Simulating emergency-services dial.');
    _simulateCall(answered: true);
  }

  @override
  Future<void> callContact(String number) async {
    _contactAttempts++;
    final answerOn = contactStore.mockAnswerOnAttempt;
    final answered = answerOn != null && _contactAttempts >= answerOn;
    debugPrint('[MockTelephony] Simulating contact call attempt '
        '$_contactAttempts (answered=$answered).');
    _simulateCall(answered: answered);
  }

  void _simulateCall({required bool answered}) {
    Future.delayed(const Duration(milliseconds: 400), () {
      if (_controller.isClosed) return;
      _controller.add(CallState.offHook);
      final holdFor =
          answered ? _answeredHoldDuration : _unansweredHoldDuration;
      Future.delayed(holdFor, () {
        if (!_controller.isClosed) _controller.add(CallState.idle);
      });
    });
  }

  @override
  Future<void> setSpeakerphoneOn(bool on) async {
    debugPrint('[MockTelephony] speakerphone=$on');
  }

  @override
  Future<void> sendSms(String number, String text) async {
    debugPrint('[MockTelephony] Simulating SMS fallback send.');
  }

  @override
  Stream<CallState> get callStateStream => _controller.stream;

  /// Resets per-run counters — call before each new workflow run so retry
  /// counting doesn't carry over from a previous emergency.
  void reset() => _contactAttempts = 0;

  void dispose() => _controller.close();
}
