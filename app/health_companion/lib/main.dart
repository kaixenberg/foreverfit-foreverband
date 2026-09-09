import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'background/background_monitoring_service.dart';
import 'ble/ble_service.dart';
import 'disaster/disaster_service.dart';
import 'disaster/imminent_warning_gate.dart';
import 'domain/backup_service.dart';
import 'domain/background_escalation_gate.dart';
import 'domain/emergency_call_gate.dart';
import 'domain/emergency_location.dart';
import 'domain/emergency_summary_builder.dart';
import 'domain/emergency_workflow_service.dart';
import 'domain/insight_watcher_service.dart';
import 'domain/onboarding_gate.dart';
import 'ml/activity_classifier_service.dart';
import 'ml/fall_detector_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/loading_screen.dart';
import 'sensors/phone_motion_service.dart';
import 'services/baseline_service.dart';
import 'services/battery_optimization_service.dart';
import 'services/notification_service.dart';
import 'services/step_counter_service.dart';
import 'services/telephony_service.dart';
import 'services/tts_service.dart';
import 'storage/app_settings_store.dart';
import 'storage/emergency_contact_store.dart';
import 'storage/health_log_store.dart';
import 'storage/history_store.dart';
import 'storage/metrics_store.dart';
import 'storage/user_profile_store.dart';
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
  final userProfileStore = UserProfileStore();
  await userProfileStore.init();
  final appSettingsStore = AppSettingsStore();
  await appSettingsStore.init();

  runApp(HealthCompanionApp(
    historyStore: historyStore,
    metricsStore: metricsStore,
    healthLogStore: healthLogStore,
    emergencyContactStore: emergencyContactStore,
    userProfileStore: userProfileStore,
    appSettingsStore: appSettingsStore,
  ));
}

class HealthCompanionApp extends StatelessWidget {
  const HealthCompanionApp({
    super.key,
    required this.historyStore,
    required this.metricsStore,
    required this.healthLogStore,
    required this.emergencyContactStore,
    required this.userProfileStore,
    required this.appSettingsStore,
  });

  final HistoryStore historyStore;
  final MetricsStore metricsStore;
  final HealthLogStore healthLogStore;
  final EmergencyContactStore emergencyContactStore;
  final UserProfileStore userProfileStore;
  final AppSettingsStore appSettingsStore;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<HistoryStore>.value(value: historyStore),
        ChangeNotifierProvider(create: (_) => BleService(historyStore)),
        ChangeNotifierProvider(create: (_) => PhoneMotionService()..start()),
        ChangeNotifierProvider.value(value: healthLogStore),
        ChangeNotifierProvider.value(value: metricsStore),
        ChangeNotifierProvider.value(value: userProfileStore),
        ChangeNotifierProvider.value(value: appSettingsStore),
        ChangeNotifierProvider(
          create: (_) => BaselineService(historyStore: historyStore)..start(),
        ),
        ChangeNotifierProvider.value(value: emergencyContactStore),
        Provider<TelephonyService>(create: (_) => PlatformTelephonyService()),
        Provider<TtsService>(create: (_) => FlutterTtsService()),
        Provider<EmergencyLocationService>(
          create: (_) => GeolocatorEmergencyLocationService(),
        ),
        Provider<BackupService>(create: (_) => BackupService()),
        Provider<BatteryOptimizationService>(
          create: (_) => BatteryOptimizationService(),
        ),
        Provider<BackgroundMonitoringService>(
          create: (_) => BackgroundMonitoringService(),
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
        ChangeNotifierProvider(
          create: (context) => DisasterService(
            ble: context.read<BleService>(),
            appSettings: context.read<AppSettingsStore>(),
          )..init(),
        ),
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
            appSettings: context.read<AppSettingsStore>(),
          )..start(),
        ),
      ],
      child: const _App(),
    );
  }
}

/// Separated from [HealthCompanionApp] so it can `watch` AppSettingsStore
/// for reactive theme/appearance changes — the providers above are only
/// available to widgets *inside* the MultiProvider they're declared in,
/// so this can't happen in the same build method that constructs them.
class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsStore>();
    final userProfile = context.watch<UserProfileStore>();
    final darkTheme = settings.oledBlack ? AppTheme.oledDark : AppTheme.dark;

    // Fall detection is a safety feature, not an opt-in extra — started
    // automatically once onboarding completes (Settings has an explicit
    // toggle to turn it back off). start() is itself a no-op once
    // already running, so calling it on every build here is safe — same
    // "cheap to re-check, guarded internally" pattern the gates below use.
    //
    // Deliberately does NOT set the app to show over the lock screen as a
    // standing, app-wide setting — MainActivity.kt applies that only for
    // the one Activity launch that follows a genuine escalation (an
    // unanswered fall alert, an imminent disaster, or the developer/demo
    // preview), never for ordinary use of the app.
    if (userProfile.onboardingCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<BackgroundMonitoringService>().start();
      });
    }

    return MaterialApp(
      title: 'Health Companion',
      theme: AppTheme.light,
      darkTheme: darkTheme,
      themeMode: settings.themeMode,
      home: const LoadingScreen(
        child: BackgroundEscalationGate(
          child: OnboardingGate(
            child: ImminentWarningGate(
              child: EmergencyCallGate(child: DashboardScreen()),
            ),
          ),
        ),
      ),
    );
  }
}
