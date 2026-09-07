import 'dart:ui';

/// User-facing unit system. Storage is always metric everywhere in this
/// app (see MetricsStore/HistoryStore/HealthLogStore) — this only
/// affects how a value is displayed and how typed input is parsed back
/// to metric before it's persisted. `system` defers to the device
/// locale via [resolveEffectiveUnitSystem].
enum UnitSystem { metric, imperial, system }

/// Countries that primarily use imperial/US customary units for
/// everyday measurements (weight/height/temperature) — the standard
/// short list (US, Liberia, Myanmar); every other locale defaults to
/// metric.
const _imperialCountryCodes = {'US', 'LR', 'MM'};

UnitSystem resolveEffectiveUnitSystem(UnitSystem preference) {
  if (preference != UnitSystem.system) return preference;
  final country = PlatformDispatcher.instance.locale.countryCode;
  return _imperialCountryCodes.contains(country)
      ? UnitSystem.imperial
      : UnitSystem.metric;
}

/// One formatted value ready to display, e.g. value=159.8, unit='lb'.
class UnitValue {
  const UnitValue(this.value, this.unit);
  final double value;
  final String unit;

  String toStringAsFixed(int digits) =>
      '${value.toStringAsFixed(digits)} $unit';
}

const _kgToLb = 2.2046226218;
const _cmToIn = 1 / 2.54;
const _mlToFlOz = 1 / 29.5735;
const _kmhToMph = 1 / 1.609344;

UnitValue formatWeightKg(double kg, UnitSystem system) =>
    system == UnitSystem.imperial
        ? UnitValue(kg * _kgToLb, 'lb')
        : UnitValue(kg, 'kg');

double parseWeightToKg(double input, UnitSystem system) =>
    system == UnitSystem.imperial ? input / _kgToLb : input;

UnitValue formatHeightCm(double cm, UnitSystem system) =>
    system == UnitSystem.imperial
        ? UnitValue(cm * _cmToIn, 'in')
        : UnitValue(cm, 'cm');

double parseHeightToCm(double input, UnitSystem system) =>
    system == UnitSystem.imperial ? input / _cmToIn : input;

/// [ml] in, always — matches MetricsStore/HealthLogStore's storage unit.
UnitValue formatHydrationMl(double ml, UnitSystem system) =>
    system == UnitSystem.imperial
        ? UnitValue(ml * _mlToFlOz, 'fl oz')
        : UnitValue(ml / 1000, 'L');

double parseHydrationToMl(double input, UnitSystem system) =>
    system == UnitSystem.imperial ? input / _mlToFlOz : input * 1000;

UnitValue formatTemperatureC(double celsius, UnitSystem system) =>
    system == UnitSystem.imperial
        ? UnitValue(celsius * 9 / 5 + 32, '°F')
        : UnitValue(celsius, '°C');

double parseTemperatureToC(double input, UnitSystem system) =>
    system == UnitSystem.imperial ? (input - 32) * 5 / 9 : input;

UnitValue formatWindSpeedKmh(double kmh, UnitSystem system) =>
    system == UnitSystem.imperial
        ? UnitValue(kmh * _kmhToMph, 'mph')
        : UnitValue(kmh, 'km/h');
