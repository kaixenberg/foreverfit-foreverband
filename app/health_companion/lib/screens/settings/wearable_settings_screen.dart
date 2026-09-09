import 'package:flutter/material.dart';

import '../scan_connect_screen.dart';
import 'watch_settings_screen.dart';

class WearableSettingsScreen extends StatelessWidget {
  const WearableSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wearable')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.watch_outlined),
              title: const Text('ForeverBand wearable'),
              subtitle: const Text('Connect or manage your device'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ScanConnectScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Watch customization'),
              subtitle: const Text('Watch faces, auto-cycle, time/date format'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WatchSettingsScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.watch_outlined),
              title: const Text('Other watches & rings'),
              subtitle: const Text(
                  'Support for third-party wearables — coming soon.'),
              enabled: false,
            ),
          ),
        ],
      ),
    );
  }
}
