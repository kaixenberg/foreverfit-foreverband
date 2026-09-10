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
    // Without an explicit language, the engine has nothing to synthesize
    // with — speak() then completes almost instantly (well under a
    // second, confirmed via logcat: bind → AudioTrack stop →
    // abandonAudioFocus all within ~700ms) with no exception and no
    // audio, since there's no real utterance for it to produce. Falls
    // back to "en" if the device has no "en-US" voice installed.
    if (await _tts.isLanguageAvailable('en-US') == true) {
      await _tts.setLanguage('en-US');
    } else {
      await _tts.setLanguage('en');
    }
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    _initialized = true;
  }

  @override
  Future<void> speak(String text) async {
    await _ensureInit();
    // `focus: true` makes Android request audio focus for this utterance —
    // without it, speak() completes "successfully" at the API level but is
    // never actually audible while something else holds audio focus, which
    // is exactly the situation here: this speaks *during a live phone
    // call*, the most audio-focus-contested moment there is.
    await _tts
        .speak(text, focus: true)
        .timeout(_speakTimeout, onTimeout: () => null);
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
