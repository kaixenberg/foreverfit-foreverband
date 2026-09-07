import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/emergency_state.dart';

/// Thrown when a required runtime permission (CALL_PHONE/READ_PHONE_STATE
/// via `Permission.phone`, SEND_SMS via `Permission.sms`) isn't granted.
/// The emergency workflow catches this and moves to its `failed` state
/// rather than crashing.
class TelephonyPermissionException implements Exception {
  TelephonyPermissionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// All telephony primitives the emergency workflow needs — see
/// ARCHITECTURE.md for why this is one small interface backed by a
/// hand-rolled native Kotlin channel rather than several third-party
/// call/SMS plugins. `EmergencyWorkflowService` depends on this
/// abstraction, not the concrete implementation, so mock mode can swap in
/// `MockTelephonyService` without touching the state machine.
abstract class TelephonyService {
  /// The device's actual regional emergency number(s) (API 29+), falling
  /// back to a sane default — never hardcoded to one country.
  Future<List<String>> getEmergencyNumbers();

  /// Opens the dialer pre-filled with [number] — the only compliant way
  /// for a normal app to initiate an emergency-services call; the OS
  /// always redirects a direct-dial attempt for an emergency number to
  /// this pre-filled/manual-tap flow regardless of permissions held.
  Future<void> dialEmergencyNumber(String number);

  /// Directly places a call to a *non-emergency* number (the saved
  /// contact) — a normal, permitted use of ACTION_CALL. Throws
  /// [TelephonyPermissionException] if CALL_PHONE isn't granted.
  Future<void> callContact(String number);

  Future<void> setSpeakerphoneOn(bool on);

  /// Throws [TelephonyPermissionException] if SEND_SMS isn't granted.
  Future<void> sendSms(String number, String text);

  /// Coarse IDLE/OFFHOOK call-state stream — the only granularity a
  /// normal app can read (see ARCHITECTURE.md).
  Stream<CallState> get callStateStream;
}

class PlatformTelephonyService implements TelephonyService {
  static const _method =
      MethodChannel('com.example.health_companion/telephony');
  static const _events =
      EventChannel('com.example.health_companion/telephony_events');

  @override
  Future<List<String>> getEmergencyNumbers() async {
    try {
      final result =
          await _method.invokeMethod<List<Object?>>('getEmergencyNumbers');
      final numbers = result?.whereType<String>().toList() ?? const [];
      return numbers.isEmpty ? const ['112'] : numbers;
    } catch (_) {
      return const ['112'];
    }
  }

  @override
  Future<void> dialEmergencyNumber(String number) async {
    // ACTION_DIAL itself needs no permission, but the call-state watch
    // that follows immediately after (to detect the call going live)
    // needs READ_PHONE_STATE — request it now, best-effort, so that
    // watch isn't silently blind on its very first use. Not fatal if
    // denied: the workflow's own timeouts still make forward progress.
    await Permission.phone.request();
    await _method.invokeMethod('dialEmergencyNumber', {'number': number});
  }

  @override
  Future<void> callContact(String number) async {
    final status = await Permission.phone.request();
    if (!status.isGranted) {
      throw TelephonyPermissionException(
          'Call permission is required to reach the emergency contact.');
    }
    try {
      await _method.invokeMethod('callContact', {'number': number});
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        throw TelephonyPermissionException(
            e.message ?? 'Call permission denied.');
      }
      rethrow;
    }
  }

  @override
  Future<void> setSpeakerphoneOn(bool on) async {
    try {
      await _method.invokeMethod('setSpeakerphoneOn', {'on': on});
    } catch (_) {
      // Best-effort — the announcement still plays over whatever route is
      // currently active if this fails.
    }
  }

  @override
  Future<void> sendSms(String number, String text) async {
    final status = await Permission.sms.request();
    if (!status.isGranted) {
      throw TelephonyPermissionException(
          'SMS permission is required to send the emergency fallback text.');
    }
    try {
      await _method.invokeMethod('sendSms', {'number': number, 'text': text});
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        throw TelephonyPermissionException(
            e.message ?? 'SMS permission denied.');
      }
      rethrow;
    }
  }

  // Cached rather than rebuilt on every access — receiveBroadcastStream()
  // registers its own native message handler per call, and two live ones
  // on the same channel would silently clobber each other. A single
  // shared broadcast stream lets multiple sequential (or, safely,
  // concurrent) listeners share one underlying subscription.
  Stream<CallState>? _callStateStream;

  @override
  Stream<CallState> get callStateStream =>
      _callStateStream ??= _events.receiveBroadcastStream().map((event) {
        return event == 'offhook' ? CallState.offHook : CallState.idle;
      }).asBroadcastStream();
}
