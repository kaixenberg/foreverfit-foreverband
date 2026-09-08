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
}
