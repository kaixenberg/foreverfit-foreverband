import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_litert/flutter_litert.dart';

/// A single phone-motion sample fed into the model — the same 6-channel
/// shape `[ax, ay, az, gx, gy, gz]` used by both the foreground
/// `FallDetectorService` and the background fall-detection task handler.
class MotionSample {
  const MotionSample({
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  final double ax, ay, az, gx, gy, gz;
}

/// Shared TFLite windowing/inference for the phone-only fall-detection
/// CNN — extracted out of `FallDetectorService` so the foreground service
/// and the background foreground-service task handler both run the exact
/// same model logic instead of two hand-copied implementations (see
/// ARCHITECTURE.md's background fall-detection section for why a small
/// amount of duplication elsewhere is unavoidable, but not this part).
/// See `FallDetectorService`'s doc comment for the model/training
/// background (UMAFall phone-only retrain, channel order, etc).
class FallInference {
  static const windowLen = 60; // 3s @ 20Hz
  static const modelAsset = 'assets/models/fall_detector_phone_only.tflite';

  // Raised from the model's own eval default of 0.5 to dial down false
  // positives, backed by a real precision/recall sweep over the held-out
  // test set rather than a guess: 0.8 is the sweet spot where precision
  // peaks (88.2% -> 92.0%) at effectively no recall cost (93.8% -> 92.0%)
  // — thresholds above 0.8 start trading real recall for no further
  // precision gain. See ml/README.md's "Threshold tuning" section for the
  // full sweep table and how to regenerate it.
  static const threshold = 0.8;

  // Below this fraction of standard gravity, treat a sample as
  // "in free-fall" — a phone genuinely falling reads close to
  // weightless right up until impact. Nothing else that moves a phone
  // day-to-day does this: walking, being carried, or being picked up
  // all keep the accelerometer reading close to 1g the whole time,
  // since the phone stays supported. ~0.5g is a standard cutoff in
  // published accelerometer-based fall-detection work — not itself
  // swept against this project's own held-out data the way `threshold`
  // above was.
  static const _freefallGThreshold = 0.5;

  // Above this multiple of standard gravity, treat a sample as a hard
  // impact — the phone hitting the ground/floor after a real fall.
  // Added after real on-device testing (see `hasPostFreefallImpact`'s
  // doc comment) proved free-fall *duration* alone is not a usable
  // signal for short falls: a confidently-classified real drop test
  // measured only ~50ms of sub-0.5g readings, while quick pickup jerks
  // separately measured up to ~550ms — duration is backwards for short
  // falls on this device/sampling setup, not just mistuned. 2.0g is a
  // conservative starting point from published phone-based post-fall
  // impact detection (commonly 1.5g-3g) — not yet swept against real
  // on-device impact data the way `threshold` was; `debugPrint` in
  // `FallDetectorService` logs the actual peak so it can be tuned from
  // the next round of real test data instead of guessed again.
  static const _impactGThreshold = 2.0;
  static const _gravityMs2 = 9.81;

  // windowLen samples nominally span 3s (see the field's own comment) —
  // derived, not hardcoded twice, so the two stay consistent if either
  // ever changes. Matches PhoneMotionService's own _samplingPeriod
  // (~20Hz); this calculation is only meaningful because that service
  // now genuinely throttles to that rate rather than emitting whatever
  // rate the OS happens to deliver sensor events at (see its own doc
  // comment for the real-device bug that was).
  static const _nominalSamplePeriodMs = 3000 ~/ windowLen;

  Interpreter? _interpreter;
  final List<MotionSample> _buffer = [];

  @visibleForTesting
  int get bufferLength => _buffer.length;

  Future<void> load() async {
    _interpreter = await Interpreter.fromAsset(modelAsset);
  }

  void addSample(MotionSample sample) {
    _buffer.add(sample);
    if (_buffer.length > windowLen) _buffer.removeAt(0);
  }

  /// Runs inference over the current window, or returns null if the
  /// model isn't loaded yet or there aren't enough samples buffered.
  double? runIfReady() {
    final interpreter = _interpreter;
    if (interpreter == null || _buffer.length < windowLen) return null;

    final input = [
      List.generate(windowLen, (i) {
        final p = _buffer[i];
        return [p.ax, p.ay, p.az, p.gx, p.gy, p.gz];
      }),
    ];
    final output = List.generate(1, (_) => List.filled(1, 0.0));
    interpreter.run(input, output);
    return output[0][0];
  }

  /// The longest continuous run of near-weightless samples currently in
  /// the buffered window, as a [Duration] — a physical proxy for "how far
  /// did this actually fall," since raw accelerometer data alone has no
  /// direct distance/height measurement. Free-fall duration relates to
  /// drop height by simple kinematics (`t = sqrt(2h/g)`): longer runs
  /// mean a taller equivalent drop. Added as corroboration alongside the
  /// CNN's own confidence after real on-device testing showed it
  /// confidently (0.999-1.000) misclassifying two specific non-fall
  /// motions: picking the phone up quickly (never enters free-fall at
  /// all — the phone is being accelerated toward a hand, not dropped)
  /// and short (~1ft) falls (a real but very brief free-fall phase). See
  /// Superseded as the alert gate by `peakImpactGAfterFreefall` /
  /// `hasPostFreefallImpact` below (see that method's doc comment) —
  /// kept around and still logged for visibility, since real falls do
  /// still show a free-fall dip, just not one whose *duration* alone
  /// reliably separates them from handling jerks.
  Duration longestFreefallRun() {
    var longest = 0;
    var current = 0;
    for (final s in _buffer) {
      final magnitude = sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az);
      if (magnitude < _freefallGThreshold * _gravityMs2) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 0;
      }
    }
    return Duration(milliseconds: longest * _nominalSamplePeriodMs);
  }

  /// Peak accelerometer magnitude (in g) seen *after* the end of the
  /// longest free-fall run in the buffered window — i.e. how hard the
  /// phone decelerated once it stopped being (near-)weightless. Real
  /// falls end in a hard impact against the ground/floor; a phone being
  /// caught by a hand or pocket decelerates far more gently. Returns 0
  /// if there's no free-fall run in the buffer at all.
  double peakImpactGAfterFreefall() {
    var longestStart = -1, longestLen = 0;
    var currentStart = -1, currentLen = 0;
    for (var i = 0; i < _buffer.length; i++) {
      final s = _buffer[i];
      final magnitude = sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az);
      if (magnitude < _freefallGThreshold * _gravityMs2) {
        if (currentLen == 0) currentStart = i;
        currentLen++;
        if (currentLen > longestLen) {
          longestLen = currentLen;
          longestStart = currentStart;
        }
      } else {
        currentLen = 0;
      }
    }
    if (longestLen == 0) return 0;

    var peak = 0.0;
    for (var i = longestStart + longestLen; i < _buffer.length; i++) {
      final s = _buffer[i];
      final magnitude = sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az);
      if (magnitude > peak) peak = magnitude;
    }
    return peak / _gravityMs2;
  }

  /// Whether the buffer shows a hard impact shortly after the longest
  /// free-fall run — see `peakImpactGAfterFreefall`'s doc comment for
  /// why this replaced a duration-based gate.
  bool hasPostFreefallImpact() =>
      peakImpactGAfterFreefall() >= _impactGThreshold;

  // Nulls out `_interpreter` after closing so a second `close()` call
  // (e.g. FallDetectorService.stop() followed by its own dispose()) is a
  // safe no-op instead of double-closing the native interpreter.
  void close() {
    _interpreter?.close();
    _interpreter = null;
  }
}
