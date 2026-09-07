import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// A resolved location for the emergency announcement — [text] is always
/// populated (falling back to "Location unavailable" in the worst case)
/// so callers never need a null check; [latitude]/[longitude] are the raw
/// coordinates when available, for callers that want them separately.
class EmergencyLocation {
  const EmergencyLocation({required this.text, this.latitude, this.longitude});

  final String text;
  final double? latitude;
  final double? longitude;

  bool get isAvailable => latitude != null && longitude != null;
}

/// Resolves the user's current location for the emergency workflow — a
/// fresh, unthrottled call, deliberately separate from
/// DisasterService's private/cooldown-gated `_resolveState()` (that one
/// only extracts a state name for hazard lookups and is rate-limited in a
/// way that's wrong for a one-shot emergency request). Never sends
/// location anywhere except the on-device text this produces, which only
/// leaves the device via the emergency call/SMS the user's own workflow
/// triggers — see ARCHITECTURE.md's privacy section.
abstract class EmergencyLocationService {
  Future<EmergencyLocation> resolve();
}

class GeolocatorEmergencyLocationService implements EmergencyLocationService {
  static const _userAgent = 'HealthCompanionApp/0.1 (SIH26 hackathon project)';
  static const _fetchTimeout = Duration(seconds: 8);

  @override
  Future<EmergencyLocation> resolve() async {
    final position = await _getPosition();
    if (position == null) {
      return const EmergencyLocation(text: 'Location unavailable');
    }
    return _withAddress(position);
  }

  Future<Position?> _getPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return await _lastKnownOrNull();
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        return await _lastKnownOrNull();
      }
      return await Geolocator.getCurrentPosition().timeout(_fetchTimeout);
    } catch (_) {
      return _lastKnownOrNull();
    }
  }

  Future<Position?> _lastKnownOrNull() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  Future<EmergencyLocation> _withAddress(Position position) async {
    final latLon =
        '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
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
      final displayName = body['display_name'] as String?;
      return EmergencyLocation(
        text: (displayName != null && displayName.isNotEmpty)
            ? displayName
            : latLon,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      return EmergencyLocation(
        text: latLon,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    }
  }
}
