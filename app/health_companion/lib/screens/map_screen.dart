import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:http_cache_core/http_cache_core.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../disaster/disaster_service.dart';
import '../disaster/india_hazard_data.dart';

/// Default map center when there's no GPS fix yet — geographic center of
/// India, so the map still shows something sensible.
const _indiaCenter = LatLng(20.5937, 78.9629);

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  CacheStore? _cacheStore;

  @override
  void initState() {
    super.initState();
    _initCacheStore();
  }

  Future<void> _initCacheStore() async {
    // Persistent app-support directory, not a temp dir — cached tiles
    // must survive app restarts to be useful offline.
    final dir = await getApplicationSupportDirectory();
    final store =
        FileCacheStore('${dir.path}${Platform.pathSeparator}map_tiles');
    if (mounted) setState(() => _cacheStore = store);
  }

  @override
  Widget build(BuildContext context) {
    final disaster = context.watch<DisasterService>();
    final risk = disaster.risk;
    final position = disaster.lastPosition;
    final center =
        position != null ? LatLng(position.latitude, position.longitude) : _indiaCenter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Disaster Map'),
        actions: [
          IconButton(
            icon: disaster.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: disaster.isLoading ? null : () => disaster.refresh(),
          ),
        ],
      ),
      body: _cacheStore == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (risk != null && risk.hasWarning) _WarningBanner(risk: risk),
                Expanded(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: position != null ? 11 : 4.3,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.health_companion',
                        tileProvider: CachedTileProvider(
                          maxStale: const Duration(days: 30),
                          store: _cacheStore!,
                        ),
                      ),
                      if (position != null)
                        MarkerLayer(markers: [
                          Marker(
                            point: LatLng(position.latitude, position.longitude),
                            width: 36,
                            height: 36,
                            child: const Icon(Icons.my_location,
                                color: Colors.blue, size: 30),
                          ),
                        ]),
                    ],
                  ),
                ),
                if (disaster.lastError != null && risk == null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      disaster.lastError!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  )
                else if (risk != null)
                  _RiskPanel(risk: risk),
              ],
            ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.risk});

  final DisasterRisk risk;

  @override
  Widget build(BuildContext context) {
    final onError = Theme.of(context).colorScheme.onErrorContainer;
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: onError),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              risk.warningMessage ?? 'Elevated risk in your area.',
              style: TextStyle(color: onError, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskPanel extends StatelessWidget {
  const _RiskPanel({required this.risk});

  final DisasterRisk risk;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              risk.stateName ?? 'Unknown location',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _RiskRow(
              icon: Icons.vibration,
              label: 'Earthquake zone',
              value: seismicZoneLabel(risk.hazardProfile.seismicZone),
              freshness: DataFreshness.staticOnly,
            ),
            if (risk.nearbyQuakeCount > 0)
              _RiskRow(
                icon: Icons.warning_amber,
                label: 'Nearby seismic activity (30d, M4+)',
                value: '${risk.nearbyQuakeCount} event(s), '
                    'largest M${risk.nearbyMaxQuakeMagnitude?.toStringAsFixed(1)}',
                freshness: risk.quakeFreshness,
                asOf: risk.quakeAsOf,
              ),
            _RiskRow(
              icon: Icons.cyclone,
              label: 'Cyclone-prone area',
              value: risk.hazardProfile.cycloneProne ? 'Yes' : 'No',
              freshness: DataFreshness.staticOnly,
            ),
            _RiskRow(
              icon: Icons.flood,
              label: 'Flood-prone area',
              value: risk.hazardProfile.floodProne ? 'Yes' : 'No',
              freshness: DataFreshness.staticOnly,
            ),
            if (risk.precipitationProbabilityPercent != null)
              _RiskRow(
                icon: Icons.water_drop,
                label: 'Rain chance today',
                value: '${risk.precipitationProbabilityPercent!.round()}%',
                freshness: risk.weatherFreshness,
                asOf: risk.weatherAsOf,
              ),
            if (risk.windSpeedKmh != null)
              _RiskRow(
                icon: Icons.air,
                label: 'Current wind speed',
                value: '${risk.windSpeedKmh!.round()} km/h',
                freshness: risk.weatherFreshness,
                asOf: risk.weatherAsOf,
              ),
            const Divider(),
            const _StubRow(icon: Icons.masks_outlined, label: 'Air quality'),
          ],
        ),
      ),
    );
  }
}

/// A roadmap item with no data behind it yet (see ARCHITECTURE.md) —
/// visually distinct from _RiskRow so "not built" is never confused with
/// "offline baseline" or "stale cache".
class _StubRow extends StatelessWidget {
  const _StubRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).disabledColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: muted),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: muted))),
          Text('Coming soon', style: TextStyle(color: muted, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

class _RiskRow extends StatelessWidget {
  const _RiskRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.freshness,
    this.asOf,
  });

  final IconData icon;
  final String label;
  final String value;
  final DataFreshness freshness;
  final DateTime? asOf;

  @override
  Widget build(BuildContext context) {
    String freshnessLabel;
    switch (freshness) {
      case DataFreshness.live:
        freshnessLabel = 'live';
        break;
      case DataFreshness.cachedStale:
        freshnessLabel = asOf != null
            ? 'cached from ${_timeAgo(asOf!)}'
            : 'cached';
        break;
      case DataFreshness.staticOnly:
        // Distinct from "couldn't fetch live data" — these fields
        // (seismic zone, cyclone/flood-prone) have no live source at all
        // in this app; they're always from the static state-level table
        // in india_hazard_data.dart, connectivity notwithstanding.
        freshnessLabel = 'reference data';
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(freshnessLabel, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
