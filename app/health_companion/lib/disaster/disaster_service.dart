import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../ble/ble_service.dart';
import '../storage/app_settings_store.dart';
import 'hazard_type.dart';
import 'india_hazard_data.dart';
import 'pressure_trend.dart';

enum DataFreshness { live, cachedStale, staticOnly }

/// Combined disaster-risk snapshot for the user's current location.
class DisasterRisk {
  final String? stateName;
  final StateHazardProfile hazardProfile;

  final double? precipitationProbabilityPercent; // today's max, from Open-Meteo
  final double? windSpeedKmh;
  final DataFreshness weatherFreshness;
  final DateTime? weatherAsOf;

  // Ambient conditions from the same Open-Meteo call — used by the
  // Dashboard as a fallback when the wearable isn't connected, so those
  // cards show *something* rather than "--" whenever there's network.
  final double? ambientTempC;
  final double? humidityPercent;
  final double? pressureHPa;

  final int nearbyQuakeCount; // M4.0+ within ~200km, last 30 days
  final double? nearbyMaxQuakeMagnitude;
  final DataFreshness quakeFreshness;
  final DateTime? quakeAsOf;

  // US AQI (0-500 scale) + the two pollutants judges/users actually
  // recognize, from Open-Meteo's separate air-quality endpoint. No
  // static offline baseline (unlike seismic zone/cyclone/flood-prone) —
  // AQI swings hour to hour with traffic/weather/season, so a hardcoded
  // "this state is usually X" table would be misleading rather than
  // merely approximate. Live-or-cached only, same as precipitation/wind.
  final double? usAqi;
  final double? pm25;
  final double? pm10;
  final DataFreshness airQualityFreshness;
  final DateTime? airQualityAsOf;

  // Rapid barometric pressure fall — a live, local early-warning signal
  // for an approaching storm (see pressure_trend.dart), fed by the
  // wearable's BME280 when connected (falling back to Open-Meteo's
  // current pressure, per the same sensor-precedence setting used for
  // the Dashboard's ambient cards) rather than a forecast probability.
  final double? pressureDropHPa3h;
  final bool pressureTrendFromWearable;

  DisasterRisk({
    required this.stateName,
    required this.hazardProfile,
    required this.precipitationProbabilityPercent,
    required this.windSpeedKmh,
    required this.weatherFreshness,
    required this.weatherAsOf,
    required this.ambientTempC,
    required this.humidityPercent,
    required this.pressureHPa,
    required this.nearbyQuakeCount,
    required this.nearbyMaxQuakeMagnitude,
    required this.quakeFreshness,
    required this.quakeAsOf,
    required this.usAqi,
    required this.pm25,
    required this.pm10,
    required this.airQualityFreshness,
    required this.airQualityAsOf,
    required this.pressureDropHPa3h,
    required this.pressureTrendFromWearable,
  });

  /// NOAA/AirNow-standard US AQI category labels.
  String? get aqiCategory {
    final aqi = usAqi;
    if (aqi == null) return null;
    if (aqi <= 50) return 'Good';
    if (aqi <= 100) return 'Moderate';
    if (aqi <= 150) return 'Unhealthy for Sensitive Groups';
    if (aqi <= 200) return 'Unhealthy';
    if (aqi <= 300) return 'Very Unhealthy';
    return 'Hazardous';
  }

  bool get hasWarning =>
      (precipitationProbabilityPercent ?? 0) > 70 ||
      (nearbyMaxQuakeMagnitude ?? 0) >= 4.5 ||
      (hazardProfile.cycloneProne && (windSpeedKmh ?? 0) > 40) ||
      (usAqi ?? 0) > 150 ||
      (pressureDropHPa3h ?? 0) >= rapidPressureFallHPa;

  String? get warningMessage {
    final reasons = <String>[];
    if ((precipitationProbabilityPercent ?? 0) > 70) {
      reasons.add('high chance of heavy rain today '
          '(${precipitationProbabilityPercent!.round()}%)');
    }
    if ((nearbyMaxQuakeMagnitude ?? 0) >= 4.5) {
      reasons.add('a recent M${nearbyMaxQuakeMagnitude!.toStringAsFixed(1)} '
          'earthquake nearby');
    }
    if (hazardProfile.cycloneProne && (windSpeedKmh ?? 0) > 40) {
      reasons.add('strong winds (${windSpeedKmh!.round()} km/h) in a '
          'cyclone-prone area');
    }
    if ((usAqi ?? 0) > 150) {
      reasons.add('$aqiCategory air quality (AQI ${usAqi!.round()})');
    }
    if ((pressureDropHPa3h ?? 0) >= rapidPressureFallHPa) {
      reasons.add('barometric pressure fell '
          '${pressureDropHPa3h!.toStringAsFixed(1)} hPa in the last 3 '
          'hours — conditions consistent with a sudden weather change');
    }
    if (reasons.isEmpty) return null;
    return 'Elevated risk: ${reasons.join(', ')}.';
  }

  /// Stricter tier than [hasWarning] — reserved for the full-screen,
  /// explicit-acknowledgment warning. Scoped to genuine **incoming
  /// disasters** only (earthquake, cyclone) — weather *conditions*
  /// (heavy rain, poor air quality, a rapid pressure fall) stay at the
  /// low-key Map/Dashboard banner tier plus a notification
  /// ([hasWarning]/[warningMessage], and the matching entries in
  /// `insight_engine.dart`) no matter how "live" the signal is. This
  /// used to also fire full-screen for a rapid pressure fall — real user
  /// feedback ("I just received a big red alarm for 'sudden weather
  /// change'") made clear the full-screen tier should be reserved for
  /// things you'd actually evacuate or take shelter for, not a weather
  /// change you'd just want to be aware of.
  List<HazardType> get imminentHazards {
    final hazards = <HazardType>[];
    if ((nearbyMaxQuakeMagnitude ?? 0) >= 5.5) {
      hazards.add(HazardType.earthquake);
    }
    if (hazardProfile.cycloneProne && (windSpeedKmh ?? 0) > 60) {
      hazards.add(HazardType.cyclone);
    }
    return hazards;
  }

  String? get imminentReason {
    final parts = <String>[];
    if (imminentHazards.contains(HazardType.earthquake)) {
      parts.add('M${nearbyMaxQuakeMagnitude!.toStringAsFixed(1)} earthquake '
          'detected nearby in the last 30 days');
    }
    if (imminentHazards.contains(HazardType.cyclone)) {
      parts.add('${windSpeedKmh!.round()} km/h winds in a cyclone-prone area');
    }
    if (parts.isEmpty) return null;
    return parts.join('; ');
  }
}

/// Fetches live disaster-risk signals when online (Open-Meteo for
/// rain/wind, USGS for nearby earthquakes), falls back to the last
/// successfully cached values when offline, and falls back further to
/// the fully-static state-level baseline (india_hazard_data.dart) when
/// there's no cache at all. See ARCHITECTURE.md for why each data source
/// was chosen and how each was verified before use.
class DisasterService extends ChangeNotifier {
  static const _userAgent = 'HealthCompanionApp/0.1 (SIH26 hackathon project)';
  static const _geocodeCooldown = Duration(minutes: 10);
  static const _geocodeMinMoveMeters = 2000.0;
  static const _fetchTimeout = Duration(seconds: 8);

  /// Both optional: the background fall-detection isolate constructs this
  /// with neither (see fall_detection_task_handler.dart) — there's no BLE
  /// connection or Provider tree in that isolate — and gets the online-
  /// only pressure trend automatically as a result.
  DisasterService({BleService? ble, AppSettingsStore? appSettings})
      : _ble = ble,
        _appSettings = appSettings;

  final BleService? _ble;
  final AppSettingsStore? _appSettings;

  Box? _cache;

  Position? _lastGeocodedPosition;
  DateTime? _lastGeocodeAt;

  Position? lastPosition;
  DisasterRisk? risk;
  bool isLoading = false;
  String? lastError;

  /// Whether the device's location toggle is on — checked fresh on every
  /// refresh so MapScreen can show an "enable location" prompt instead of
  /// a bare error when it's off.
  bool locationServiceEnabled = true;

  /// True when [lastPosition] came from a fallback (OS last-known fix or
  /// this app's own cache) rather than a fresh GPS read — so the UI can
  /// show it's approximate.
  bool positionIsStale = false;

  Future<void> init() async {
    _cache = await Hive.openBox('disaster_cache');
    await refresh();
  }

  Future<void> refresh() async {
    isLoading = true;
    notifyListeners();

    try {
      final position = await _getPosition();
      lastPosition = position;
      final stateName = await _resolveState(position);
      final hazard = hazardProfileForState(stateName);

      final weather = await _fetchWeather(position);
      final quakes = await _fetchQuakes(position);
      final airQuality = await _fetchAirQuality(position);
      final pressureTrend = await _recordPressureSample(weather);

      risk = DisasterRisk(
        stateName: stateName,
        hazardProfile: hazard,
        precipitationProbabilityPercent: weather?.precipProb,
        windSpeedKmh: weather?.windSpeed,
        weatherFreshness: weather != null
            ? (weather.isLive ? DataFreshness.live : DataFreshness.cachedStale)
            : DataFreshness.staticOnly,
        weatherAsOf: weather?.asOf,
        ambientTempC: weather?.ambientTempC,
        humidityPercent: weather?.humidityPercent,
        pressureHPa: weather?.pressureHPa,
        nearbyQuakeCount: quakes?.count ?? 0,
        nearbyMaxQuakeMagnitude: quakes?.maxMagnitude,
        quakeFreshness: quakes != null
            ? (quakes.isLive ? DataFreshness.live : DataFreshness.cachedStale)
            : DataFreshness.staticOnly,
        quakeAsOf: quakes?.asOf,
        usAqi: airQuality?.usAqi,
        pm25: airQuality?.pm25,
        pm10: airQuality?.pm10,
        airQualityFreshness: airQuality != null
            ? (airQuality.isLive
                ? DataFreshness.live
                : DataFreshness.cachedStale)
            : DataFreshness.staticOnly,
        airQualityAsOf: airQuality?.asOf,
        pressureDropHPa3h: pressureTrend?.dropHPa,
        pressureTrendFromWearable: pressureTrend?.fromWearable ?? false,
      );
      lastError = null;
    } catch (e) {
      lastError = 'Could not determine location: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Feeds the current pressure reading into the rolling trend history
  /// and returns the resulting 3h drop (if any). Prefers the wearable's
  /// live BME280 reading over Open-Meteo's, per the same ambient-source
  /// precedence setting used for the Dashboard's ambient cards — falling
  /// back the other way if the preferred source isn't currently
  /// available. Kept separate from [DisasterRisk.pressureHPa] (which
  /// stays online-only, unchanged, for its existing Dashboard-fallback
  /// role) since this is a rolling series, not a single snapshot.
  Future<_PressureTrendResult?> _recordPressureSample(
    _WeatherResult? weather,
  ) async {
    final env = _ble?.latestEnv;
    final preferWearable = (_appSettings?.ambientSourcePreference ??
            AmbientSourcePreference.preferWearable) ==
        AmbientSourcePreference.preferWearable;

    double? hPa;
    var fromWearable = false;
    if (preferWearable && env != null) {
      hPa = env.pressureHPa;
      fromWearable = true;
    } else if (weather?.pressureHPa != null) {
      hPa = weather!.pressureHPa;
    } else if (env != null) {
      hPa = env.pressureHPa;
      fromWearable = true;
    }
    if (hPa == null) return null;

    final now = DateTime.now();
    final stored = (_cache?.get('pressureTrend') as List?) ?? const [];
    final samples = [
      for (final entry in stored)
        if (entry is Map)
          if (PressureSample.fromMap(entry) case final sample?) sample,
      PressureSample(now, hPa),
    ];
    final pruned = prunePressureSamples(samples, now);
    await _cache?.put(
      'pressureTrend',
      [for (final s in pruned) s.toMap()],
    );

    final drop = pressureDropOverWindow(pruned, now);
    return _PressureTrendResult(dropHPa: drop, fromWearable: fromWearable);
  }

  /// Live GPS fix when possible; falls back to the OS's last-known fix
  /// (works even with location services currently off, if one was cached
  /// before), then to this app's own last successfully-used position, so
  /// the map/risk view still shows *something* rather than erroring out
  /// the moment location is toggled off.
  Future<Position> _getPosition() async {
    locationServiceEnabled = await Geolocator.isLocationServiceEnabled();

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }

    if (locationServiceEnabled) {
      try {
        final position =
            await Geolocator.getCurrentPosition().timeout(_fetchTimeout);
        await _cache?.put('lastLat', position.latitude);
        await _cache?.put('lastLon', position.longitude);
        positionIsStale = false;
        return position;
      } catch (_) {
        // Fall through to the fallbacks below.
      }
    }

    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) {
      positionIsStale = true;
      return lastKnown;
    }

    final lat = _cache?.get('lastLat') as double?;
    final lon = _cache?.get('lastLon') as double?;
    if (lat != null && lon != null) {
      positionIsStale = true;
      return Position(
        latitude: lat,
        longitude: lon,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    }

    throw Exception(locationServiceEnabled
        ? 'Could not get a GPS fix'
        : 'Location services are off and no cached position is available');
  }

  Future<String?> _resolveState(Position position) async {
    final now = DateTime.now();
    final movedEnough = _lastGeocodedPosition == null ||
        Geolocator.distanceBetween(
              _lastGeocodedPosition!.latitude,
              _lastGeocodedPosition!.longitude,
              position.latitude,
              position.longitude,
            ) >
            _geocodeMinMoveMeters;
    final cooledDown = _lastGeocodeAt == null ||
        now.difference(_lastGeocodeAt!) > _geocodeCooldown;

    final cachedState = _cache?.get('lastState') as String?;

    if (!(movedEnough && cooledDown)) {
      return cachedState;
    }

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': position.latitude.toString(),
        'lon': position.longitude.toString(),
        'format': 'jsonv2',
      });
      final resp = await http
          .get(uri, headers: {'User-Agent': _userAgent}).timeout(_fetchTimeout);
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final address = body['address'] as Map<String, dynamic>?;
      final state = address?['state'] as String?;

      _lastGeocodedPosition = position;
      _lastGeocodeAt = now;
      if (state != null) await _cache?.put('lastState', state);
      return state ?? cachedState;
    } catch (_) {
      return cachedState; // offline or geocoding failed — use last known
    }
  }

  Future<_WeatherResult?> _fetchWeather(Position position) async {
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': position.latitude.toString(),
        'longitude': position.longitude.toString(),
        'current':
            'precipitation,wind_speed_10m,temperature_2m,relative_humidity_2m,pressure_msl',
        'daily': 'precipitation_probability_max',
        'timezone': 'auto',
      });
      final resp = await http.get(uri).timeout(_fetchTimeout);
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final current = body['current'] as Map<String, dynamic>;
      final daily = body['daily'] as Map<String, dynamic>;
      final precipProb =
          (daily['precipitation_probability_max'] as List).first as num;
      final windSpeed = current['wind_speed_10m'] as num;
      final ambientTemp = current['temperature_2m'] as num;
      final humidity = current['relative_humidity_2m'] as num;
      final pressure = current['pressure_msl'] as num;

      final now = DateTime.now();
      await _cache?.put('lastPrecipProb', precipProb.toDouble());
      await _cache?.put('lastWindSpeed', windSpeed.toDouble());
      await _cache?.put('lastAmbientTemp', ambientTemp.toDouble());
      await _cache?.put('lastHumidity', humidity.toDouble());
      await _cache?.put('lastPressure', pressure.toDouble());
      await _cache?.put('lastWeatherAt', now.toIso8601String());

      return _WeatherResult(
        precipProb: precipProb.toDouble(),
        windSpeed: windSpeed.toDouble(),
        ambientTempC: ambientTemp.toDouble(),
        humidityPercent: humidity.toDouble(),
        pressureHPa: pressure.toDouble(),
        asOf: now,
        isLive: true,
      );
    } catch (_) {
      final precipProb = _cache?.get('lastPrecipProb') as double?;
      final windSpeed = _cache?.get('lastWindSpeed') as double?;
      final ambientTemp = _cache?.get('lastAmbientTemp') as double?;
      final humidity = _cache?.get('lastHumidity') as double?;
      final pressure = _cache?.get('lastPressure') as double?;
      final asOfStr = _cache?.get('lastWeatherAt') as String?;
      if (precipProb == null || asOfStr == null) return null;
      return _WeatherResult(
        precipProb: precipProb,
        windSpeed: windSpeed,
        ambientTempC: ambientTemp,
        humidityPercent: humidity,
        pressureHPa: pressure,
        asOf: DateTime.tryParse(asOfStr),
        isLive: false,
      );
    }
  }

  Future<_AirQualityResult?> _fetchAirQuality(Position position) async {
    try {
      // Open-Meteo's dedicated air-quality endpoint (separate host from
      // the weather forecast one), same no-key/no-signup deal, verified
      // with a live test call before use — see ARCHITECTURE.md.
      final uri =
          Uri.https('air-quality-api.open-meteo.com', '/v1/air-quality', {
        'latitude': position.latitude.toString(),
        'longitude': position.longitude.toString(),
        'current': 'pm2_5,pm10,us_aqi',
        'timezone': 'auto',
      });
      final resp = await http.get(uri).timeout(_fetchTimeout);
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final current = body['current'] as Map<String, dynamic>;
      final usAqi = (current['us_aqi'] as num?)?.toDouble();
      final pm25 = (current['pm2_5'] as num?)?.toDouble();
      final pm10 = (current['pm10'] as num?)?.toDouble();
      if (usAqi == null) throw Exception('No AQI in response');

      final now = DateTime.now();
      await _cache?.put('lastUsAqi', usAqi);
      if (pm25 != null) await _cache?.put('lastPm25', pm25);
      if (pm10 != null) await _cache?.put('lastPm10', pm10);
      await _cache?.put('lastAirQualityAt', now.toIso8601String());

      return _AirQualityResult(
          usAqi: usAqi, pm25: pm25, pm10: pm10, asOf: now, isLive: true);
    } catch (_) {
      final usAqi = _cache?.get('lastUsAqi') as double?;
      final pm25 = _cache?.get('lastPm25') as double?;
      final pm10 = _cache?.get('lastPm10') as double?;
      final asOfStr = _cache?.get('lastAirQualityAt') as String?;
      if (usAqi == null || asOfStr == null) return null;
      return _AirQualityResult(
        usAqi: usAqi,
        pm25: pm25,
        pm10: pm10,
        asOf: DateTime.tryParse(asOfStr),
        isLive: false,
      );
    }
  }

  Future<_QuakeResult?> _fetchQuakes(Position position) async {
    try {
      final startTime = DateTime.now()
          .subtract(const Duration(days: 30))
          .toIso8601String()
          .split('.')
          .first;
      final uri = Uri.https('earthquake.usgs.gov', '/fdsnws/event/1/query', {
        'format': 'geojson',
        'latitude': position.latitude.toString(),
        'longitude': position.longitude.toString(),
        'maxradiuskm': '200',
        'minmagnitude': '4.0',
        'starttime': startTime,
        'orderby': 'magnitude',
      });
      final resp = await http.get(uri).timeout(_fetchTimeout);
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final features = body['features'] as List;
      final count = features.length;
      final maxMag = features.isEmpty
          ? null
          : (features.first['properties']['mag'] as num).toDouble();

      final now = DateTime.now();
      await _cache?.put('lastQuakeCount', count);
      if (maxMag != null) await _cache?.put('lastQuakeMaxMag', maxMag);
      await _cache?.put('lastQuakeAt', now.toIso8601String());

      return _QuakeResult(
          count: count, maxMagnitude: maxMag, asOf: now, isLive: true);
    } catch (_) {
      final count = _cache?.get('lastQuakeCount') as int?;
      final maxMag = _cache?.get('lastQuakeMaxMag') as double?;
      final asOfStr = _cache?.get('lastQuakeAt') as String?;
      if (count == null || asOfStr == null) return null;
      return _QuakeResult(
        count: count,
        maxMagnitude: maxMag,
        asOf: DateTime.tryParse(asOfStr),
        isLive: false,
      );
    }
  }
}

class _WeatherResult {
  final double precipProb;
  final double? windSpeed;
  final double? ambientTempC;
  final double? humidityPercent;
  final double? pressureHPa;
  final DateTime? asOf;
  final bool isLive;

  _WeatherResult({
    required this.precipProb,
    required this.windSpeed,
    required this.ambientTempC,
    required this.humidityPercent,
    required this.pressureHPa,
    required this.asOf,
    required this.isLive,
  });
}

class _AirQualityResult {
  final double usAqi;
  final double? pm25;
  final double? pm10;
  final DateTime? asOf;
  final bool isLive;

  _AirQualityResult({
    required this.usAqi,
    required this.pm25,
    required this.pm10,
    required this.asOf,
    required this.isLive,
  });
}

class _PressureTrendResult {
  final double? dropHPa;
  final bool fromWearable;

  _PressureTrendResult({required this.dropHPa, required this.fromWearable});
}

class _QuakeResult {
  final int count;
  final double? maxMagnitude;
  final DateTime? asOf;
  final bool isLive;

  _QuakeResult({
    required this.count,
    required this.maxMagnitude,
    required this.asOf,
    required this.isLive,
  });
}
