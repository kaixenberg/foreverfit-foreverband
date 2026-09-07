import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/domain/units.dart';

void main() {
  group('metric passthrough', () {
    test('formatters return the input unchanged in metric', () {
      expect(formatWeightKg(70, UnitSystem.metric).value, 70);
      expect(formatWeightKg(70, UnitSystem.metric).unit, 'kg');
      expect(formatHeightCm(175, UnitSystem.metric).value, 175);
      expect(formatTemperatureC(37, UnitSystem.metric).value, 37);
      expect(formatWindSpeedKmh(10, UnitSystem.metric).unit, 'km/h');
    });
  });

  group('imperial conversion round-trips', () {
    test('weight kg <-> lb', () {
      final displayed = formatWeightKg(70, UnitSystem.imperial);
      expect(displayed.unit, 'lb');
      expect(displayed.value, closeTo(154.32, 0.1));
      final backToKg = parseWeightToKg(displayed.value, UnitSystem.imperial);
      expect(backToKg, closeTo(70, 0.001));
    });

    test('height cm <-> in', () {
      final displayed = formatHeightCm(180, UnitSystem.imperial);
      expect(displayed.unit, 'in');
      expect(displayed.value, closeTo(70.87, 0.1));
      final backToCm = parseHeightToCm(displayed.value, UnitSystem.imperial);
      expect(backToCm, closeTo(180, 0.001));
    });

    test('hydration mL <-> fl oz', () {
      final displayed = formatHydrationMl(1000, UnitSystem.imperial);
      expect(displayed.unit, 'fl oz');
      expect(displayed.value, closeTo(33.81, 0.1));
      final backToMl = parseHydrationToMl(displayed.value, UnitSystem.imperial);
      expect(backToMl, closeTo(1000, 0.01));
    });

    test('hydration mL -> L in metric', () {
      final displayed = formatHydrationMl(2500, UnitSystem.metric);
      expect(displayed.unit, 'L');
      expect(displayed.value, closeTo(2.5, 0.001));
    });

    test('temperature C <-> F', () {
      expect(
          formatTemperatureC(0, UnitSystem.imperial).value, closeTo(32, 0.01));
      expect(formatTemperatureC(100, UnitSystem.imperial).value,
          closeTo(212, 0.01));
      expect(parseTemperatureToC(98.6, UnitSystem.imperial), closeTo(37, 0.05));
    });

    test('wind speed km/h <-> mph', () {
      final displayed = formatWindSpeedKmh(100, UnitSystem.imperial);
      expect(displayed.unit, 'mph');
      expect(displayed.value, closeTo(62.14, 0.1));
    });
  });

  group('resolveEffectiveUnitSystem', () {
    test('non-system preferences pass through unchanged', () {
      expect(resolveEffectiveUnitSystem(UnitSystem.metric), UnitSystem.metric);
      expect(
          resolveEffectiveUnitSystem(UnitSystem.imperial), UnitSystem.imperial);
    });
  });
}
