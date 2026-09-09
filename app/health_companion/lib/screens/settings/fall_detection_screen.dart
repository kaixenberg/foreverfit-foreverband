import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ml/fall_detector_service.dart';
import '../../storage/app_settings_store.dart';

/// Settings' "Fall detection" section: a master on/off toggle for the
/// in-app fall-detection CNN, and a one-tap demo that previews exactly
/// what a real detected fall looks like — banner, 10s "I'm OK" countdown
/// and all — without needing to actually drop the phone. Doesn't touch
/// background monitoring (Settings' own "Background permission" screen
/// already has that toggle) — this is the foreground, app-open detector.
class FallDetectionScreen extends StatelessWidget {
  const FallDetectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fallDetector = context.watch<FallDetectorService>();
    final appSettings = context.watch<AppSettingsStore>();

    return Scaffold(
      appBar: AppBar(title: const Text('Fall detection')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Fall detection',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Watches your phone\'s own motion for a fall while the app is '
            'open, using an on-device model — nothing leaves your phone. '
            'If a possible fall is detected, you get 10 seconds to tap '
            '"I\'m OK" before help is called.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Detect falls'),
            subtitle: Text(fallDetector.isRunning ? 'On' : 'Off'),
            value: fallDetector.isRunning,
            onChanged: (value) async {
              await appSettings.setFallDetectionEnabled(value);
              if (value) {
                await fallDetector.start();
              } else {
                fallDetector.stop();
              }
            },
          ),
          const SizedBox(height: 8),
          if (fallDetector.lastError != null)
            Text(
              fallDetector.lastError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 8),
          Text(
            'A known, stated tradeoff: the model can also mistake a quick '
            'phone pickup or a short drop for a fall (see ARCHITECTURE.md). '
            'The 10-second dismiss window exists exactly for this — a false '
            'alarm costs one tap, not a real call.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          Text('Try the demo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Shows exactly what a real detected fall looks like — the same '
            'banner and 10-second "I\'m OK" countdown — without needing to '
            'actually drop the phone. Always safe: forced into test mode, '
            'so it can never place a real call even if left to run out.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: !fallDetector.isRunning || fallDetector.alertActive
                ? null
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Simulated fall detected — showing the alert now.',
                        ),
                      ),
                    );
                    fallDetector.triggerFallDemo();
                  },
            child: const Text('Trigger fall detection demo'),
          ),
          if (!fallDetector.isRunning) ...[
            const SizedBox(height: 4),
            Text(
              'Turn on "Detect falls" above to try the demo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
