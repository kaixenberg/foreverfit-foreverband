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

  // Matches the 0.5 threshold used when evaluating the trained model
  // (ml/train_fall_model_phone_only.py: 99% accuracy, 94% fall recall,
  // 88% fall precision on held-out subjects).
  static const threshold = 0.5;

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

  void close() => _interpreter?.close();
}
