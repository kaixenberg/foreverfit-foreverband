import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_icon_service.dart';

Future<void> _openUrl(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

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
          Card(
            child: ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Source'),
              subtitle: Text(
                'GitLab',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _openUrl(
                'https://gitlab.com/kaixenberg/foreverfit-foreverband',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Credits',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text('By Team ABBOY',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  const _CreditRow(
                    name: 'Smarajit Datta',
                    role: 'Full Stack',
                    link: 'https://gitlab.com/kaixenberg',
                  ),
                  const _CreditRow(name: 'Ankit Gupta', role: 'Backend Design'),
                  const _CreditRow(
                    name: 'Pradipta Bhattacharya, Saptak Chatterjee',
                    role: 'Financial Investment & Idea Management',
                  ),
                  const _CreditRow(
                    name: 'Abhijeet, Anushka Mondal',
                    role: 'Idea Management',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditRow extends StatelessWidget {
  const _CreditRow({required this.name, required this.role, this.link});

  final String name;
  final String role;
  final String? link;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          Text(role, style: Theme.of(context).textTheme.bodySmall),
          if (link != null)
            InkWell(
              onTap: () => _openUrl(link!),
              child: Text(
                'GitLab profile',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
