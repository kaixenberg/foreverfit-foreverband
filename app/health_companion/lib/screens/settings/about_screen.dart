import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../services/app_icon_service.dart';

/// Name, short description, version, and a GitHub placeholder — reads the
/// icon live from the OS the same way LoadingScreen does (see
/// app_icon_service.dart), so this stays in sync with the real launcher
/// icon automatically instead of bundling a third copy of it.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  Uint8List? _iconBytes;
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      AppIconService.loadIconPng(),
      PackageInfo.fromPlatform(),
    ]);
    if (!mounted) return;
    setState(() {
      _iconBytes = results[0] as Uint8List?;
      _packageInfo = results[1] as PackageInfo;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final packageInfo = _packageInfo;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                SizedBox(
                  width: 88,
                  height: 88,
                  child: _iconBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child:
                              Image.memory(_iconBytes!, gaplessPlayback: true),
                        )
                      : Icon(Icons.favorite, size: 64, color: scheme.primary),
                ),
                const SizedBox(height: 12),
                Text('ForeverFit',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  packageInfo == null
                      ? 'Version …'
                      : 'Version ${packageInfo.version}'
                          '${packageInfo.buildNumber.isNotEmpty ? '+${packageInfo.buildNumber}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'A privacy-preserving, offline-first personal health '
                'companion. A wearable streams vitals and environment '
                'sensor data to your phone over Bluetooth, which does all '
                'the processing on-device — fall detection, disaster '
                'warnings, and emergency calling all work without a cloud '
                'dependency. Built for Smart India Hackathon 2026, '
                'Problem ID 26181.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: ListTile(
              leading: Icon(Icons.code),
              title: Text('GitHub'),
              subtitle: Text('Not public yet'),
              enabled: false,
            ),
          ),
        ],
      ),
    );
  }
}
