import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/ml/fall_inference.dart';

void main() {
  // Doesn't call load() — actually loading the TFLite asset needs a real
  // platform channel/interpreter, which isn't meaningfully testable in
  // `flutter test` (matches this project's precedent of not unit-testing
  // native-integration-heavy pieces). This only verifies the pure
  // windowing/buffering logic that was extracted out of
  // FallDetectorService — the one piece of the background fall-detection
  // work that's actually unit-testable, per the plan.
  test(
      'runIfReady returns null before the model is loaded, regardless of buffer size',
      () {
    final inference = FallInference();
    for (var i = 0; i < FallInference.windowLen + 10; i++) {
      inference.addSample(
          const MotionSample(ax: 1, ay: 1, az: 1, gx: 0, gy: 0, gz: 0));
    }
    expect(inference.runIfReady(), isNull);
  });

  test('buffer never grows past windowLen', () {
    final inference = FallInference();
    for (var i = 0; i < FallInference.windowLen * 3; i++) {
      inference.addSample(
          MotionSample(ax: i.toDouble(), ay: 0, az: 0, gx: 0, gy: 0, gz: 0));
    }
    expect(inference.bufferLength, FallInference.windowLen);
  });

  group('longestFreefallRun', () {
    // windowLen=60 spans a nominal 3s, so each sample represents 50ms
    // (3000ms / 60) — matches PhoneMotionService's own ~20Hz throttle.
    const atRest = MotionSample(ax: 0, ay: 0, az: 9.81, gx: 0, gy: 0, gz: 0);
    const weightless = MotionSample(ax: 0, ay: 0, az: 0, gx: 0, gy: 0, gz: 0);

    test('empty buffer has no free-fall run', () {
      expect(FallInference().longestFreefallRun(), Duration.zero);
    });

    test('a buffer that never drops below 1g has no free-fall run', () {
      final inference = FallInference();
      for (var i = 0; i < FallInference.windowLen; i++) {
        inference.addSample(atRest);
      }
      expect(inference.longestFreefallRun(), Duration.zero);
    });

    test('a contiguous near-weightless run is measured in wall-clock time', () {
      final inference = FallInference();
      for (var i = 0; i < 10; i++) {
        inference.addSample(atRest);
      }
      for (var i = 0; i < 14; i++) {
        inference.addSample(weightless);
      }
      for (var i = 0; i < 10; i++) {
        inference.addSample(atRest);
      }
      // 14 samples @ 50ms/sample = 700ms — an arbitrary round number
      // here now that duration is no longer the alert gate (see
      // hasPostFreefallImpact below for what is), just exercising the
      // windowing math.
      expect(inference.longestFreefallRun(), const Duration(milliseconds: 700));
    });

    test('reports the longest run, not the total weightless sample count', () {
      final inference = FallInference();
      for (var i = 0; i < 3; i++) {
        inference.addSample(weightless);
      }
      for (var i = 0; i < 5; i++) {
        inference.addSample(atRest);
      }
      for (var i = 0; i < 8; i++) {
        inference.addSample(weightless);
      }
      // Two separate weightless runs (3 and 8 samples) — the longer one
      // wins, they don't sum to 11.
      expect(inference.longestFreefallRun(), const Duration(milliseconds: 400));
    });
  });

  group('peakImpactGAfterFreefall / hasPostFreefallImpact', () {
    const atRest = MotionSample(ax: 0, ay: 0, az: 9.81, gx: 0, gy: 0, gz: 0);
    const weightless = MotionSample(ax: 0, ay: 0, az: 0, gx: 0, gy: 0, gz: 0);
    const hardImpact =
        MotionSample(ax: 0, ay: 0, az: 30, gx: 0, gy: 0, gz: 0); // ~3.06g
    const gentleCatch =
        MotionSample(ax: 0, ay: 0, az: 12, gx: 0, gy: 0, gz: 0); // ~1.22g

    test('no free-fall run in the buffer means no impact either', () {
      final inference = FallInference();
      for (var i = 0; i < FallInference.windowLen; i++) {
        inference.addSample(atRest);
      }
      expect(inference.peakImpactGAfterFreefall(), 0);
      expect(inference.hasPostFreefallImpact(), isFalse);
    });

    test('a hard spike right after a free-fall dip counts as an impact', () {
      final inference = FallInference();
      for (var i = 0; i < 10; i++) {
        inference.addSample(weightless);
      }
      inference.addSample(hardImpact);
      for (var i = 0; i < 10; i++) {
        inference.addSample(atRest);
      }
      expect(inference.peakImpactGAfterFreefall(), closeTo(3.06, 0.01));
      expect(inference.hasPostFreefallImpact(), isTrue);
    });

    test('a free-fall dip followed only by a gentle catch is not an impact',
        () {
      final inference = FallInference();
      for (var i = 0; i < 10; i++) {
        inference.addSample(weightless);
      }
      inference.addSample(gentleCatch);
      for (var i = 0; i < 10; i++) {
        inference.addSample(atRest);
      }
      expect(inference.peakImpactGAfterFreefall(), closeTo(1.22, 0.01));
      expect(inference.hasPostFreefallImpact(), isFalse);
    });
  });
}
