import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ble/ble_service.dart';
import 'disaster/disaster_service.dart';
import 'disaster/imminent_warning_gate.dart';
import 'ml/activity_classifier_service.dart';
import 'ml/fall_detector_service.dart';
import 'screens/dashboard_screen.dart';
import 'sensors/phone_motion_service.dart';
import 'services/baseline_service.dart';
import 'services/step_counter_service.dart';
import 'storage/health_log_store.dart';
import 'storage/history_store.dart';
import 'storage/metrics_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final historyStore = HistoryStore();
  await historyStore.init();
  final metricsStore = MetricsStore();
  await metricsStore.init();
  final healthLogStore = HealthLogStore();
  await healthLogStore.init();

  runApp(HealthCompanionApp(
    historyStore: historyStore,
    metricsStore: metricsStore,
    healthLogStore: healthLogStore,
  ));
}

class HealthCompanionApp extends StatelessWidget {
  const HealthCompanionApp({
    super.key,
    required this.historyStore,
    required this.metricsStore,
    required this.healthLogStore,
  });

  final HistoryStore historyStore;
  final MetricsStore metricsStore;
  final HealthLogStore healthLogStore;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<HistoryStore>.value(value: historyStore),
        ChangeNotifierProvider(create: (_) => BleService(historyStore)),
        ChangeNotifierProvider(create: (_) => PhoneMotionService()..start()),
        ChangeNotifierProvider(
          create: (context) => FallDetectorService(
            phoneMotionService: context.read<PhoneMotionService>(),
          )..start(),
        ),
        ChangeNotifierProvider(
          create: (context) => ActivityClassifierService(
            phoneMotionService: context.read<PhoneMotionService>(),
          )..start(),
        ),
        ChangeNotifierProvider(create: (_) => DisasterService()..init()),
        ChangeNotifierProvider(
          create: (_) => BaselineService(historyStore: historyStore)..start(),
        ),
        ChangeNotifierProvider.value(value: metricsStore),
        ChangeNotifierProvider.value(value: healthLogStore),
        ChangeNotifierProvider(create: (_) => StepCounterService()..start()),
      ],
      child: MaterialApp(
        title: 'Health Companion',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const ImminentWarningGate(child: DashboardScreen()),
      ),
    );
  }
}
