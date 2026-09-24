import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_litert/flutter_litert.dart';

/// A single phone-motion sample — the 6-channel shape `[ax, ay, az, gx,
/// gy, gz]` used by the phone-only model. Still used by both the
/// foreground `FallDetectorService` (phone mode) and the background
/// fall-detection task handler, which only ever runs phone-only (see
/// that file's doc comment for why).
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

  List<double> get channels => [ax, ay, az, gx, gy, gz];
}

/// A single fused wrist+phone motion sample — the 9-channel shape
/// `[wrist_ax, wrist_ay, wrist_az, wrist_gx, wrist_gy, wrist_gz,
/// phone_ax, phone_ay, phone_az]` the wrist+phone model was trained on
/// (see ml/prepare_windows.py) — used by `FallDetectorService`'s watch
/// mode, fusing `BleService.latestMotion` (wrist) with
/// `PhoneMotionService.latest` (phone) at the wrist sensor's ~20Hz rate.
/// No phone gyro channel — the training dataset's period-correct phone
/// hardware had none (see ml/README.md).
class WristPhoneMotionSample {
  const WristPhoneMotionSample({
    required this.wristAx,
    required this.wristAy,
    required this.wristAz,
    required this.wristGx,
    required this.wristGy,
    required this.wristGz,
    required this.phoneAx,
    required this.phoneAy,
    required this.phoneAz,
  });

  final double wristAx, wristAy, wristAz;
  final double wristGx, wristGy, wristGz;
  final double phoneAx, phoneAy, phoneAz;

  List<double> get channels => [
        wristAx, wristAy, wristAz, //
        wristGx, wristGy, wristGz,
        phoneAx, phoneAy, phoneAz,
      ];
}

/// Shared TFLite windowing/inference for the fall-detection CNN —
/// extracted out of `FallDetectorService` so the foreground service and
/// the background foreground-service task handler both run the exact
/// same model logic instead of two hand-copied implementations (see
/// ARCHITECTURE.md's background fall-detection section for why a small
/// amount of duplication elsewhere is unavoidable, but not this part).
///
/// Configurable for either trained model — phone-only (6 channels,
/// default) or wrist+phone (9 channels) — rather than one hardcoded
/// asset/channel-count/threshold, since `FallDetectorService`'s watch
/// mode needs the same windowing/corroboration logic against a
/// differently-shaped input. `windowLen` (3s @ 20Hz) doesn't vary
/// between them — both models share that architecture, just with a
/// different channel count on the input layer — so it stays a `static
/// const`, only `modelAsset`/`channelCount`/`threshold` are per-instance.
/// See `FallDetectorService`'s doc comment for the model/training
/// background (channel order, accuracy figures, etc).
class FallInference {
  FallInference({
    this.modelAsset = phoneOnlyModelAsset,
    this.channelCount = 6,
    this.threshold = phoneOnlyThreshold,
  });

  static const windowLen = 60; // 3s @ 20Hz

  static const phoneOnlyModelAsset =
      'assets/models/fall_detector_phone_only.tflite';
  static const wristPhoneModelAsset = 'assets/models/fall_detector.tflite';

  // Raised from the model's own eval default of 0.5 to dial down false
  // positives, backed by a real precision/recall sweep over the held-out
  // test set rather than a guess: 0.8 is the sweet spot where precision
  // peaks (88.2% -> 92.0%) at effectively no recall cost (93.8% -> 92.0%)
  // — thresholds above 0.8 start trading real recall for no further
  // precision gain. See ml/README.md's "Threshold tuning" section for the
  // full sweep table and how to regenerate it.
  static const phoneOnlyThreshold = 0.8;

  // Swept the same way as phoneOnlyThreshold above (subjects 18-19
  // held-out, ml/data/fall_model.keras) once the wrist+phone model was
  // put back into the app — unlike the phone-only sweep, precision stays
  // flat (~55-61%) across the whole 0.3-0.8 range with no cheap-recall
  // "knee" to trade into, so this keeps the model's own natural 0.5
  // decision boundary rather than picking an arbitrary point on an
  // otherwise-flat curve: 57.6% precision / 89.8% recall (15/122 falls
  // missed) — consistent with this project's stated priority (a missed
  // fall has no recovery; a false alarm costs one "I'm OK" tap via the
  // 10s countdown). See ml/README.md's "Wrist+phone model" section for
  // the full sweep table.
  static const wristPhoneThreshold = 0.5;

  final String modelAsset;
  final int channelCount;
  final double threshold;

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
  // separately measured up to ~550ms. 2.0g is a conservative starting
  // point from published phone-based post-fall impact detection
  // (commonly 1.5g-3g) — not yet swept against real on-device impact
  // data the way `threshold` was.
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
  final List<List<double>> _buffer = [];

  @visibleForTesting
  int get bufferLength => _buffer.length;

  Future<void> load() async {
    _interpreter = await Interpreter.fromAsset(modelAsset);
  }

  /// [channels] must have exactly `channelCount` values, in the trained
  /// model's channel order (see `MotionSample.channels`/
  /// `WristPhoneMotionSample.channels`) — the first 3 must always be an
  /// accelerometer x/y/z (phone for the 6-channel model, wrist for the
  /// 9-channel one), since `longestFreefallRun`/`peakImpactGAfterFreefall`
  /// below read indices 0-2 as "the" accelerometer regardless of mode.
  void addSample(List<double> channels) {
    assert(channels.length == channelCount,
        'expected $channelCount channels, got ${channels.length}');
    _buffer.add(channels);
    if (_buffer.length > windowLen) _buffer.removeAt(0);
  }

  /// Runs inference over the current window, or returns null if the
  /// model isn't loaded yet or there aren't enough samples buffered.
  double? runIfReady() {
    final interpreter = _interpreter;
    if (interpreter == null || _buffer.length < windowLen) return null;

    final input = [List.generate(windowLen, (i) => _buffer[i])];
    final output = List.generate(1, (_) => List.filled(1, 0.0));
    interpreter.run(input, output);
    return output[0][0];
  }

  double _accelMagnitude(List<double> sample) => sqrt(
      sample[0] * sample[0] + sample[1] * sample[1] + sample[2] * sample[2]);

  /// The longest continuous run of near-weightless samples currently in
  /// the buffered window, as a [Duration] — a physical proxy for "how far
  /// did this actually fall," since raw accelerometer data alone has no
  /// direct distance/height measurement. Free-fall duration relates to
  /// drop height by simple kinematics (`t = sqrt(2h/g)`): longer runs
  /// mean a taller equivalent drop. Superseded as the alert gate by
  /// `peakImpactGAfterFreefall`/`hasPostFreefallImpact` below (see that
  /// method's doc comment) — kept around and still logged for
  /// visibility, since real falls do still show a free-fall dip, just
  /// not one whose *duration* alone reliably separates them from
  /// handling jerks. See `FallDetectorService`'s doc comment for the
  /// full evidence trail (phone-only mode); not yet re-validated against
  /// real wrist-worn drop-test data for watch mode.
  Duration longestFreefallRun() {
    var longest = 0;
    var current = 0;
    for (final s in _buffer) {
      if (_accelMagnitude(s) < _freefallGThreshold * _gravityMs2) {
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
  /// sensor decelerated once it stopped being (near-)weightless. Real
  /// falls end in a hard impact against the ground/floor; a phone being
  /// caught by a hand or pocket (or a wrist coming to rest) decelerates
  /// far more gently. Returns 0 if there's no free-fall run in the
  /// buffer at all.
  double peakImpactGAfterFreefall() {
    var longestStart = -1, longestLen = 0;
    var currentStart = -1, currentLen = 0;
    for (var i = 0; i < _buffer.length; i++) {
      if (_accelMagnitude(_buffer[i]) < _freefallGThreshold * _gravityMs2) {
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
      final magnitude = _accelMagnitude(_buffer[i]);
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
