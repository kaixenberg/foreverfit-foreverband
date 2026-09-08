import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../background/background_monitoring_service.dart';
import '../../services/battery_optimization_service.dart';

class BackgroundPermissionScreen extends StatefulWidget {
  const BackgroundPermissionScreen({super.key});

  @override
  State<BackgroundPermissionScreen> createState() =>
      _BackgroundPermissionScreenState();
}

class _BackgroundPermissionScreenState extends State<BackgroundPermissionScreen>
    with WidgetsBindingObserver {
  bool? _ignoringOptimizations;
  bool? _monitoringRunning;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final battery = context.read<BatteryOptimizationService>();
    final monitoring = context.read<BackgroundMonitoringService>();
    final ignoring = await battery.isIgnoringBatteryOptimizations();
    final running = await monitoring.isRunning;
    if (mounted) {
      setState(() {
        _ignoringOptimizations = ignoring;
        _monitoringRunning = running;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ignoring = _ignoringOptimizations;
    final running = _monitoringRunning;
    return Scaffold(
      appBar: AppBar(title: const Text('Background permission')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Background fall detection',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Keeps watching for falls even while another app is open or '
            "the screen is off. Android requires a persistent, visible "
            "notification while this runs — it can't be hidden. If a fall "
            'is detected, you get 10 seconds to tap "I\'m OK" before the '
            'app is brought to the foreground to call for help.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Monitor for falls in the background'),
            subtitle: Text(
                running == null ? 'Checking…' : (running ? 'Running' : 'Off')),
            value: running ?? false,
            onChanged: running == null
                ? null
                : (value) async {
                    final monitoring =
                        context.read<BackgroundMonitoringService>();
                    if (value) {
                      await monitoring.start();
                    } else {
                      await monitoring.stop();
                    }
                    await _refresh();
                  },
          ),
          const SizedBox(height: 24),
          Text('Battery optimization',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Lets fall detection, vitals monitoring, and the disaster '
            'warning keep running when the screen is off, instead of '
            'being paused by Android\'s battery-saving (Doze) mode.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(
                ignoring == true ? Icons.check_circle : Icons.error_outline,
                color: ignoring == true
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
              title: Text(switch (ignoring) {
                null => 'Checking…',
                true => 'Exempt from battery optimization',
                false => 'Not exempt — background monitoring may be paused',
              }),
              trailing: ignoring == false
                  ? FilledButton(
                      onPressed: () async {
                        try {
                          await context
                              .read<BatteryOptimizationService>()
                              .requestIgnoreBatteryOptimizations();
                        } on PlatformException {
                          // Some OEM builds refuse the intent outright —
                          // nothing more to do from here.
                        }
                        await _refresh();
                      },
                      child: const Text('Allow'),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Some phone makers (Xiaomi, Huawei, Oppo, OnePlus, Vivo, and "
            "others) run their own battery manager on top of this — even "
            "with this exemption, you may also need to manually allow "
            '"autostart"/"background activity" for this app in your '
            "phone's own battery settings. This app can't do that step "
            "for you.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
