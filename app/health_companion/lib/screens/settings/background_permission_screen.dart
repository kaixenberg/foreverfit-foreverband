import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
    final service = context.read<BatteryOptimizationService>();
    final ignoring = await service.isIgnoringBatteryOptimizations();
    if (mounted) setState(() => _ignoringOptimizations = ignoring);
  }

  @override
  Widget build(BuildContext context) {
    final ignoring = _ignoringOptimizations;
    return Scaffold(
      appBar: AppBar(title: const Text('Background permission')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
