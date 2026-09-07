import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

/// Thin wrapper over `flutter_tts` — on-device speech synthesis only, no
/// network/cloud speech API involved. Used to speak the emergency
/// announcement scripts out loud (see ARCHITECTURE.md: TTS cannot be
/// injected into an actual phone call's voice-audio path on a normal
/// Android app — it plays acoustically over the device speaker, which is
/// why the emergency workflow also requests speakerphone).
abstract class TtsService {
  Future<void> speak(String text);

  /// Interrupts speech in progress — used when the emergency workflow is
  /// cancelled mid-announcement so the audio actually stops, not just the
  /// workflow's own bookkeeping.
  Future<void> stop();
}

class FlutterTtsService implements TtsService {
  final _tts = FlutterTts();
  bool _initialized = false;

  // Safety net: if the platform never fires the completion callback
  // flutter_tts's awaitSpeakCompletion relies on (seen on some OEM TTS
  // engines), don't hang the emergency workflow forever.
  static const _speakTimeout = Duration(seconds: 30);

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    _initialized = true;
  }

  @override
  Future<void> speak(String text) async {
    await _ensureInit();
    await _tts.speak(text).timeout(_speakTimeout, onTimeout: () => null);
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Best-effort — if this fails, _speakSafely's own race against the
      // cancel signal still unblocks the workflow regardless.
    }
  }
}
