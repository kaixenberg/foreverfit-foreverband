import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'india_hazard_data.dart';

enum DataFreshness { live, cachedStale, staticOnly }

/// Combined disaster-risk snapshot for the user's current location.
class DisasterRisk {
  final String? stateName;
  final StateHazardProfile hazardProfile;

  final double? precipitationProbabilityPercent; // today's max, from Open-Meteo
  final double? windSpeedKmh;
  final DataFreshness weatherFreshness;
  final DateTime? weatherAsOf;

  final int nearbyQuakeCount; // M4.0+ within ~200km, last 30 days
  final double? nearbyMaxQuakeMagnitude;
  final DataFreshness quakeFreshness;
  final DateTime? quakeAsOf;

  DisasterRisk({
    required this.stateName,
    required this.hazardProfile,
    required this.precipitationProbabilityPercent,
    required this.windSpeedKmh,
    required this.weatherFreshness,
    required this.weatherAsOf,
    required this.nearbyQuakeCount,
    required this.nearbyMaxQuakeMagnitude,
    required this.quakeFreshness,
    required this.quakeAsOf,
  });

  bool get hasWarning =>
      (precipitationProbabilityPercent ?? 0) > 70 ||
      (nearbyMaxQuakeMagnitude ?? 0) >= 4.5 ||
      (hazardProfile.cycloneProne && (windSpeedKmh ?? 0) > 40);

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
    if (reasons.isEmpty) return null;
    return 'Elevated risk: ${reasons.join(', ')}.';
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

  Box? _cache;

  Position? _lastGeocodedPosition;
  DateTime? _lastGeocodeAt;

  Position? lastPosition;
  DisasterRisk? risk;
  bool isLoading = false;
  String? lastError;

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

      risk = DisasterRisk(
        stateName: stateName,
        hazardProfile: hazard,
        precipitationProbabilityPercent: weather?.precipProb,
        windSpeedKmh: weather?.windSpeed,
        weatherFreshness: weather != null
            ? (weather.isLive ? DataFreshness.live : DataFreshness.cachedStale)
            : DataFreshness.staticOnly,
        weatherAsOf: weather?.asOf,
        nearbyQuakeCount: quakes?.count ?? 0,
        nearbyMaxQuakeMagnitude: quakes?.maxMagnitude,
        quakeFreshness: quakes != null
            ? (quakes.isLive ? DataFreshness.live : DataFreshness.cachedStale)
            : DataFreshness.staticOnly,
        quakeAsOf: quakes?.asOf,
      );
      lastError = null;
    } catch (e) {
      lastError = 'Could not determine location: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<Position> _getPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are off');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }
    return Geolocator.getCurrentPosition();
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
        'current': 'precipitation,wind_speed_10m',
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

      final now = DateTime.now();
      await _cache?.put('lastPrecipProb', precipProb.toDouble());
      await _cache?.put('lastWindSpeed', windSpeed.toDouble());
      await _cache?.put('lastWeatherAt', now.toIso8601String());

      return _WeatherResult(
        precipProb: precipProb.toDouble(),
        windSpeed: windSpeed.toDouble(),
        asOf: now,
        isLive: true,
      );
    } catch (_) {
      final precipProb = _cache?.get('lastPrecipProb') as double?;
      final windSpeed = _cache?.get('lastWindSpeed') as double?;
      final asOfStr = _cache?.get('lastWeatherAt') as String?;
      if (precipProb == null || asOfStr == null) return null;
      return _WeatherResult(
        precipProb: precipProb,
        windSpeed: windSpeed,
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
      final uri =
          Uri.https('earthquake.usgs.gov', '/fdsnws/event/1/query', {
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
  final DateTime? asOf;
  final bool isLive;

  _WeatherResult({
    required this.precipProb,
    required this.windSpeed,
    required this.asOf,
    required this.isLive,
  });
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
