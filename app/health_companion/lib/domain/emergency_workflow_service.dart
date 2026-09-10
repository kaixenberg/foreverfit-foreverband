import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/emergency_state.dart';
import '../services/mock_telephony_service.dart';
import '../services/telephony_service.dart';
import '../services/tts_service.dart';
import '../storage/emergency_contact_store.dart';
import 'emergency_location.dart';
import 'emergency_summary_builder.dart';

/// Builds the emergency summary at the moment it's needed — injected
/// rather than the workflow depending directly on BleService/HistoryStore/
/// HealthLogStore/BaselineService, so the state machine can be unit
/// tested with a trivial fake instead of needing Hive-backed stores.
/// `main.dart` wires the real implementation from `buildEmergencySummary`.
typedef EmergencySummaryBuilder = EmergencySummary Function({
  required EmergencyLocation location,
  required String triggerReason,
});

/// Orchestrates the AI-assisted emergency call: builds a local summary,
/// calls the region's emergency number, speaks it once the call is live,
/// then calls the saved emergency contact (retrying up to 5 times total),
/// falling back to SMS if the contact never answers. An explicit state
/// machine (`EmergencyWorkflowState`) rather than loosely connected
/// callbacks, per the feature's design brief.
///
/// Privacy: health data only ever leaves the device through the three
/// channels this class itself drives (the emergency call, the contact
/// call, the SMS fallback) — nothing is uploaded anywhere, and
/// [_persist] deliberately stores only workflow bookkeeping (state,
/// attempt count, timestamp), never the generated scripts/summary, which
/// contain the actual health values.
class EmergencyWorkflowService extends ChangeNotifier {
  EmergencyWorkflowService({
    required this.telephony,
    required this.tts,
    required this.locationService,
    required this.contactStore,
    required this.summaryBuilder,
    this.retryDelay = const Duration(seconds: 5),
    this.answerGrace = const Duration(seconds: 6),
    this.dialTimeout = const Duration(seconds: 20),
    this.callEndTimeout = const Duration(seconds: 90),
  }) : _mockTelephony = MockTelephonyService(contactStore: contactStore) {
    _active = telephony;
  }

  final TelephonyService telephony;
  final TtsService tts;
  final EmergencyLocationService locationService;
  final EmergencyContactStore contactStore;
  final EmergencySummaryBuilder summaryBuilder;

  static const _maxContactAttempts = 5;

  /// Delay between contact-call retries.
  final Duration retryDelay;

  /// How long off-hook must persist, uninterrupted, before this app treats
  /// a contact call as "answered" — see ARCHITECTURE.md: a normal Android
  /// app has no precise answered signal, only coarse off-hook/idle, so
  /// this is an honestly-documented heuristic, not a claim of certainty.
  /// A call that ends before this elapses is treated as not-answered
  /// (covers rejected/failed/unreachable/no-answer alike, per spec).
  /// Overridable (tests use a much shorter grace period than the 6s
  /// production default so the suite doesn't take real minutes to run).
  final Duration answerGrace;
  final Duration dialTimeout;
  final Duration callEndTimeout;

  static const _boxName = 'emergency_workflow';
  static const _key = 'current';

  // Nullable rather than `late` — this app's DI pattern fires `init()`
  // off without awaiting it (see main.dart), so a trigger arriving in the
  // brief window before the box finishes opening must degrade gracefully
  // (skip persistence for that run) rather than throw.
  Box<Map>? _box;
  final MockTelephonyService _mockTelephony;

  EmergencyWorkflowState state = EmergencyWorkflowState.idle;

  /// Incremented once per [start] call, before any `await` — lets
  /// listeners (see EmergencyCallGate) detect "a new run began" reliably,
  /// unlike watching for the exact transient `emergencyDetected` state
  /// value, which [start] itself overwrites (to `collectingData`) via a
  /// Hive write that typically resolves faster than Flutter's next frame
  /// — a race the state-value check was consistently losing, so the
  /// emergency screen would silently never appear.
  int runId = 0;

  int attempt = 0;
  String? servicesScript;
  String? contactScript;
  String? smsText;
  final List<String> log = [];

  bool recoveredIncompleteRun = false;
  String? recoveredStateLabel;

  /// Clears the recovered-run notice once the user has seen it.
  void acknowledgeRecoveredRun() {
    recoveredIncompleteRun = false;
    notifyListeners();
  }

  bool _cancelRequested = false;

  /// Completed once per run when [cancel] is called — every blocking wait
  /// below races against this so a cancel takes effect within a tick,
  /// not only at the next coarse checkpoint (which, without this, could
  /// be up to [callEndTimeout]/[dialTimeout] — i.e. up to 90s — away).
  Completer<void>? _cancelSignal;

  bool get cancelRequested => _cancelRequested;

  bool get isActive =>
      state != EmergencyWorkflowState.idle &&
      state != EmergencyWorkflowState.completed &&
      state != EmergencyWorkflowState.failed &&
      state != EmergencyWorkflowState.cancelled;

  // Snapshotted once per run in `start()` — reading `contactStore.mockMode`
  // fresh on every telephony call would let a mid-run Settings toggle mix
  // real and mock telephony within the same emergency, which is exactly
  // the kind of surprise a safety feature must not have.
  late TelephonyService _active;

  /// Whether the run currently in progress (or most recently run) used
  /// mock telephony — driven by [start]'s `forceMock` param as well as
  /// the persisted setting, so the UI can show an accurate "TEST MODE"
  /// indicator even during a forced-mock Settings preview.
  bool get isUsingMockTelephony => identical(_active, _mockTelephony);

  Future<void> init() async {
    final box = await Hive.openBox<Map>(_boxName);
    _box = box;

    final saved = box.get(_key);
    if (saved != null) {
      final savedState = EmergencyWorkflowState.values.firstWhere(
        (s) => s.name == saved['state'],
        orElse: () => EmergencyWorkflowState.idle,
      );
      final terminal = savedState == EmergencyWorkflowState.idle ||
          savedState == EmergencyWorkflowState.completed ||
          savedState == EmergencyWorkflowState.failed ||
          savedState == EmergencyWorkflowState.cancelled;
      if (!terminal) {
        // Deliberately NOT auto-resumed — silently re-placing real calls
        // after an app relaunch would be more dangerous than helpful. The
        // UI surfaces this instead so the user knows what happened.
        recoveredIncompleteRun = true;
        recoveredStateLabel = savedState.name;
      }
      await box.delete(_key); // nothing left to store once surfaced.
    }
  }

  /// Starts a new run. A no-op while one is already active — the
  /// synchronous state check-and-set below (before any `await`) is what
  /// makes two near-simultaneous triggers collapse into a single run.
  /// [forceMock] is for Settings' "Preview emergency workflow" button — it
  /// runs the full flow in mock mode regardless of the persisted setting,
  /// without touching that setting (so a real-mode user previewing the
  /// feature doesn't have to remember to flip it back).
  Future<void> start(
      {required String triggerReason, bool forceMock = false}) async {
    if (isActive) {
      _appendLog(
          'Ignored duplicate emergency trigger — a run is already active.');
      return;
    }
    runId++;
    _cancelRequested = false;
    _cancelSignal = Completer<void>();
    attempt = 0;
    servicesScript = null;
    contactScript = null;
    smsText = null;
    log.clear();
    _mockTelephony.reset();
    _active = (forceMock || contactStore.mockMode) ? _mockTelephony : telephony;
    _setState(EmergencyWorkflowState.emergencyDetected);
    await _persist();

    try {
      await _run(triggerReason);
    } catch (e) {
      _appendLog('Emergency workflow failed unexpectedly: $e');
      _setState(EmergencyWorkflowState.failed);
    }
    await _clearPersisted();
  }

  /// Best-effort cancel — can only stop *future* steps (there is no
  /// platform API for a normal app to end a call it didn't place itself
  /// via its own in-call UI). Safe to call at any time, including when
  /// nothing is running (a no-op then) or more than once (only the first
  /// call has an effect).
  void cancel() {
    if (!isActive || _cancelRequested) return;
    _cancelRequested = true;
    _cancelSignal?.complete();
    // Best-effort — actually silences an in-progress announcement rather
    // than leaving it playing while the workflow itself has moved on.
    unawaited(tts.stop());
    _appendLog('Cancellation requested — stopping after the current step.');
  }

  Future<void> _run(String triggerReason) async {
    if (_bail()) return;
    _setState(EmergencyWorkflowState.collectingData);

    _setState(EmergencyWorkflowState.gettingLocation);
    EmergencyLocation location;
    try {
      location = await locationService.resolve();
    } catch (e) {
      _appendLog('Location lookup failed: $e');
      location = const EmergencyLocation(text: 'Location unavailable');
    }
    if (_bail()) return;

    _setState(EmergencyWorkflowState.generatingMessage);
    final summary =
        summaryBuilder(location: location, triggerReason: triggerReason);
    servicesScript = buildEmergencyServicesScript(summary);
    contactScript = buildContactScript(summary);
    smsText = buildEmergencySms(summary);
    notifyListeners();
    if (_bail()) return;

    await _runEmergencyServicesCall();
    if (_bail()) return;

    await _runContactFlow();
    if (state != EmergencyWorkflowState.failed &&
        state != EmergencyWorkflowState.cancelled) {
      _setState(EmergencyWorkflowState.completed);
    }
  }

  Future<void> _runEmergencyServicesCall() async {
    _setState(EmergencyWorkflowState.callingEmergencyServices);
    try {
      final numbers = contactStore.customEmergencyNumber.isNotEmpty
          ? [contactStore.customEmergencyNumber]
          : await _active.getEmergencyNumbers();
      final number = numbers.isNotEmpty ? numbers.first : '112';
      await _active.dialEmergencyNumber(number);

      final wentLive = await _waitForOffHook(dialTimeout);
      if (!wentLive) {
        _appendLog(
            'Emergency call never went off-hook within ${dialTimeout.inSeconds}s '
            '— the dialer was opened pre-filled; proceeding to the contact '
            'call regardless.');
        return;
      }

      _setState(EmergencyWorkflowState.announcingToEmergencyServices);
      await _active.setSpeakerphoneOn(true);
      await _speakSafely(servicesScript!);

      _setState(EmergencyWorkflowState.waitingForEmergencyCallEnd);
      await _waitForIdle(callEndTimeout);
    } catch (e) {
      _appendLog('Emergency-services call step failed: $e');
    }
  }

  Future<void> _runContactFlow() async {
    if (!contactStore.hasContact) {
      _appendLog('No emergency contact configured — cannot call or SMS.');
      _setState(EmergencyWorkflowState.failed);
      return;
    }

    for (var i = 1; i <= _maxContactAttempts; i++) {
      if (_cancelRequested) {
        _setState(EmergencyWorkflowState.cancelled);
        return;
      }
      attempt = i;
      _setState(i == 1
          ? EmergencyWorkflowState.callingEmergencyContact
          : EmergencyWorkflowState.retryingContact);

      CallOutcome outcome;
      try {
        await _active.callContact(contactStore.contactPhone);
        outcome = await _observeContactCall();
      } on TelephonyPermissionException catch (e) {
        _appendLog('Contact call permission missing: $e');
        _setState(EmergencyWorkflowState.failed);
        return;
      } catch (e) {
        _appendLog('Contact call attempt $i failed: $e');
        outcome = CallOutcome.error;
      }

      if (outcome == CallOutcome.answered) {
        _setState(EmergencyWorkflowState.announcingToContact);
        await _active.setSpeakerphoneOn(true);
        await _speakSafely(contactScript!);
        await _waitForIdle(callEndTimeout);
        _bail(); // cancelled during that wait → land on `cancelled`, not `completed`
        return; // Answered — do not retry just because the call later ends.
      }

      _setState(EmergencyWorkflowState.contactNoAnswer);
      if (i < _maxContactAttempts) {
        await _delayUnlessCancelled(retryDelay);
      }
    }

    if (_cancelRequested) {
      _setState(EmergencyWorkflowState.cancelled);
      return;
    }

    _setState(EmergencyWorkflowState.smsFallback);
    try {
      await _active.sendSms(contactStore.contactPhone, smsText!);
    } catch (e) {
      // Logged locally only, per spec — this is the one place a failure
      // needs to be visible to the user even though nothing more can be
      // automatically retried.
      _appendLog('SMS fallback failed: $e');
    }
  }

  /// Races "off-hook held for [answerGrace]" (→ answered) against
  /// "returned to idle first" (→ not answered) — see the class doc for
  /// why this is a heuristic, not a precise signal. Also races against
  /// [_cancelSignal] so a cancel takes effect immediately rather than only
  /// once [dialTimeout] elapses.
  Future<CallOutcome> _observeContactCall() async {
    final completer = Completer<CallOutcome>();
    Timer? graceTimer;
    final sub = _active.callStateStream.listen((event) {
      if (event == CallState.offHook) {
        graceTimer ??= Timer(answerGrace, () {
          if (!completer.isCompleted) completer.complete(CallOutcome.answered);
        });
      } else if (event == CallState.idle) {
        graceTimer?.cancel();
        if (!completer.isCompleted) completer.complete(CallOutcome.notAnswered);
      }
    });
    final dialTimeoutTimer = Timer(dialTimeout, () {
      if (!completer.isCompleted) completer.complete(CallOutcome.notAnswered);
    });
    unawaited(_cancelSignal?.future.then((_) {
      if (!completer.isCompleted) completer.complete(CallOutcome.notAnswered);
    }));

    final result = await completer.future;
    graceTimer?.cancel();
    dialTimeoutTimer.cancel();
    await sub.cancel();
    return result;
  }

  Future<bool> _waitForOffHook(Duration timeout) async {
    final completer = Completer<bool>();
    final sub = _active.callStateStream.listen((event) {
      if (event == CallState.offHook && !completer.isCompleted) {
        completer.complete(true);
      }
    });
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    unawaited(_cancelSignal?.future.then((_) {
      if (!completer.isCompleted) completer.complete(false);
    }));
    final result = await completer.future;
    timer.cancel();
    await sub.cancel();
    return result;
  }

  Future<void> _waitForIdle(Duration timeout) async {
    final completer = Completer<void>();
    final sub = _active.callStateStream.listen((event) {
      if (event == CallState.idle && !completer.isCompleted) {
        completer.complete();
      }
    });
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete();
    });
    unawaited(_cancelSignal?.future.then((_) {
      if (!completer.isCompleted) completer.complete();
    }));
    await completer.future;
    timer.cancel();
    await sub.cancel();
  }

  /// Like `Future.delayed`, but resolves immediately if cancelled instead
  /// of always waiting the full [duration] — used for the between-retries
  /// pause so a cancel mid-pause doesn't sit there doing nothing.
  Future<void> _delayUnlessCancelled(Duration duration) async {
    final completer = Completer<void>();
    final timer = Timer(duration, () {
      if (!completer.isCompleted) completer.complete();
    });
    unawaited(_cancelSignal?.future.then((_) {
      if (!completer.isCompleted) completer.complete();
    }));
    await completer.future;
    timer.cancel();
  }

  /// Races the speak call against [_cancelSignal] so a cancel mid-speech
  /// unblocks the workflow immediately rather than waiting out however
  /// long the announcement takes (or `tts`'s own internal timeout,
  /// e.g. 30s) — `cancel()` also calls `tts.stop()` to actually silence
  /// the audio, but this doesn't *depend* on that working.
  Future<void> _speakSafely(String text) async {
    try {
      final cancelFuture = _cancelSignal?.future;
      if (cancelFuture != null) {
        await Future.any([tts.speak(text), cancelFuture]);
      } else {
        await tts.speak(text);
      }
    } catch (e) {
      _appendLog('Text-to-speech failed: $e');
    }
  }

  bool _bail() {
    if (_cancelRequested) {
      _setState(EmergencyWorkflowState.cancelled);
      return true;
    }
    return false;
  }

  void _setState(EmergencyWorkflowState s) {
    state = s;
    notifyListeners();
    unawaited(_persist());
  }

  /// Non-sensitive operational log only (step names, error types) — never
  /// the generated scripts or raw vital values. Visible in the workflow
  /// screen for transparency; not written to any persistent store.
  void _appendLog(String message) {
    debugPrint('[EmergencyWorkflow] $message');
    log.add(message);
    notifyListeners();
  }

  Future<void> _persist() async {
    await _box?.put(_key, {
      'state': state.name,
      'attempt': attempt,
      'triggeredAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _clearPersisted() async => _box?.delete(_key);

  @override
  void dispose() {
    _mockTelephony.dispose();
    super.dispose();
  }
}
