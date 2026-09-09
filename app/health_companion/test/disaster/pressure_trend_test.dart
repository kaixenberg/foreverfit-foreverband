import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/disaster/pressure_trend.dart';

void main() {
  final now = DateTime(2026, 9, 9, 12, 0, 0);

  test('returns null with no samples', () {
    expect(pressureDropOverWindow(const [], now), isNull);
  });

  test('returns null when history spans less than the minimum coverage', () {
    final samples = [
      PressureSample(now.subtract(const Duration(minutes: 30)), 1008.0),
      PressureSample(now, 1004.0),
    ];
    expect(pressureDropOverWindow(samples, now), isNull);
  });

  test('reports the drop from the oldest in-window sample to the latest', () {
    final samples = [
      PressureSample(now.subtract(const Duration(hours: 3)), 1010.0),
      PressureSample(now.subtract(const Duration(hours: 2)), 1007.0),
      PressureSample(now.subtract(const Duration(hours: 1)), 1004.0),
      PressureSample(now, 1002.0),
    ];
    expect(pressureDropOverWindow(samples, now), closeTo(8.0, 0.001));
  });

  test('ignores samples older than the 3h window', () {
    final samples = [
      PressureSample(now.subtract(const Duration(hours: 5)), 1030.0),
      PressureSample(now.subtract(const Duration(hours: 3)), 1006.0),
      PressureSample(now, 1004.0),
    ];
    expect(pressureDropOverWindow(samples, now), closeTo(2.0, 0.001));
  });

  test('returns null when pressure is flat or rising, not falling', () {
    final samples = [
      PressureSample(now.subtract(const Duration(hours: 3)), 1004.0),
      PressureSample(now, 1006.0),
    ];
    expect(pressureDropOverWindow(samples, now), isNull);
  });

  test('unsorted input is handled the same as sorted input', () {
    final samples = [
      PressureSample(now, 1002.0),
      PressureSample(now.subtract(const Duration(hours: 3)), 1010.0),
    ];
    expect(pressureDropOverWindow(samples, now), closeTo(8.0, 0.001));
  });

  test('prunePressureSamples drops entries older than 6h', () {
    final samples = [
      PressureSample(now.subtract(const Duration(hours: 7)), 1020.0),
      PressureSample(now.subtract(const Duration(hours: 1)), 1005.0),
    ];
    final pruned = prunePressureSamples(samples, now);
    expect(pruned, hasLength(1));
    expect(pruned.single.hPa, 1005.0);
  });
}
