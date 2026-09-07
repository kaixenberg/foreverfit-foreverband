import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ble/ble_service.dart';
import 'disaster/disaster_service.dart';
import 'disaster/imminent_warning_gate.dart';
import 'domain/emergency_call_gate.dart';
import 'domain/emergency_location.dart';
import 'domain/emergency_summary_builder.dart';
import 'domain/emergency_workflow_service.dart';
import 'domain/insight_watcher_service.dart';
import 'ml/activity_classifier_service.dart';
import 'ml/fall_detector_service.dart';
import 'screens/dashboard_screen.dart';
import 'sensors/phone_motion_service.dart';
import 'services/baseline_service.dart';
import 'services/notification_service.dart';
import 'services/step_counter_service.dart';
import 'services/telephony_service.dart';
import 'services/tts_service.dart';
import 'storage/emergency_contact_store.dart';
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
  final emergencyContactStore = EmergencyContactStore();
  await emergencyContactStore.init();

  runApp(HealthCompanionApp(
    historyStore: historyStore,
    metricsStore: metricsStore,
    healthLogStore: healthLogStore,
    emergencyContactStore: emergencyContactStore,
  ));
}

class HealthCompanionApp extends StatelessWidget {
  const HealthCompanionApp({
    super.key,
    required this.historyStore,
    required this.metricsStore,
    required this.healthLogStore,
    required this.emergencyContactStore,
  });

  final HistoryStore historyStore;
  final MetricsStore metricsStore;
  final HealthLogStore healthLogStore;
  final EmergencyContactStore emergencyContactStore;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<HistoryStore>.value(value: historyStore),
        ChangeNotifierProvider(create: (_) => BleService(historyStore)),
        ChangeNotifierProvider(create: (_) => PhoneMotionService()..start()),
        ChangeNotifierProvider.value(value: healthLogStore),
        ChangeNotifierProvider.value(value: metricsStore),
        ChangeNotifierProvider(
          create: (_) => BaselineService(historyStore: historyStore)..start(),
        ),
        ChangeNotifierProvider.value(value: emergencyContactStore),
        Provider<TelephonyService>(create: (_) => PlatformTelephonyService()),
        Provider<TtsService>(create: (_) => FlutterTtsService()),
        Provider<EmergencyLocationService>(
          create: (_) => GeolocatorEmergencyLocationService(),
        ),
        ChangeNotifierProvider(
          create: (context) {
            final ble = context.read<BleService>();
            final healthLog = context.read<HealthLogStore>();
            final baseline = context.read<BaselineService>();
            return EmergencyWorkflowService(
              telephony: context.read<TelephonyService>(),
              tts: context.read<TtsService>(),
              locationService: context.read<EmergencyLocationService>(),
              contactStore: context.read<EmergencyContactStore>(),
              summaryBuilder: ({required location, required triggerReason}) =>
                  buildEmergencySummary(
                ble: ble,
                historyStore: historyStore,
                healthLog: healthLog,
                baseline: baseline,
                location: location,
                triggerReason: triggerReason,
              ),
            )..init();
          },
        ),
        ChangeNotifierProvider(
          create: (context) => FallDetectorService(
            phoneMotionService: context.read<PhoneMotionService>(),
            emergencyWorkflow: context.read<EmergencyWorkflowService>(),
          )..start(),
        ),
        ChangeNotifierProvider(
          create: (context) => ActivityClassifierService(
            phoneMotionService: context.read<PhoneMotionService>(),
          )..start(),
        ),
        ChangeNotifierProvider(create: (_) => DisasterService()..init()),
        ChangeNotifierProvider(create: (_) => StepCounterService()..start()),
        Provider<NotificationService>(create: (_) => NotificationService()),
        ChangeNotifierProvider(
          create: (context) => InsightWatcherService(
            ble: context.read<BleService>(),
            disaster: context.read<DisasterService>(),
            baseline: context.read<BaselineService>(),
            activityClassifier: context.read<ActivityClassifierService>(),
            healthLog: context.read<HealthLogStore>(),
            metrics: context.read<MetricsStore>(),
            notifications: context.read<NotificationService>(),
          )..start(),
        ),
      ],
      child: MaterialApp(
        title: 'Health Companion',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const ImminentWarningGate(
          child: EmergencyCallGate(child: DashboardScreen()),
        ),
      ),
    );
  }
}
