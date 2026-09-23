import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ai_chat/ai_chat_service.dart';
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
import 'services/display_mode_service.dart';
import 'services/medication_reminder_service.dart';
import 'services/notification_service.dart';
import 'services/step_counter_service.dart';
import 'services/telephony_service.dart';
import 'services/tts_service.dart';
import 'storage/ai_chat_history_store.dart';
import 'storage/ai_chat_settings_store.dart';
import 'storage/app_settings_store.dart';
import 'storage/emergency_contact_store.dart';
import 'storage/health_log_store.dart';
import 'storage/history_store.dart';
import 'storage/metrics_store.dart';
import 'storage/user_profile_store.dart';
import 'storage/watch_settings_store.dart';
import 'theme/app_theme.dart';

/// Used by MaterialApp's own `navigatorKey:` — kept available for anything
/// that needs to navigate from outside a widget's own BuildContext (e.g. a
/// notification tap).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// A top-level, not a main()-local — it registers itself as a
/// WidgetsBindingObserver in its own constructor, and needs to live for
/// the whole app lifetime to keep retrying on every resume.
final _displayMode = DisplayModeService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android only defaults new frames to the display's *default* refresh
  // mode (60Hz on most phones) unless an app explicitly asks for a
  // higher one — Flutter's engine happily renders faster, but nothing
  // requests it without this call, so scrolling/animations look capped
  // at 60Hz even on a high-refresh-rate screen. See DisplayModeService's
  // own doc comment for why this doesn't always succeed on every device
  // (a known, currently-unresolved issue on some Xiaomi/HyperOS phones
  // specifically) — kept alive as `_displayMode` (not a local that goes
  // out of scope) since it's also a WidgetsBindingObserver that retries
  // this on every app resume, not just once here at startup.
  await _displayMode.apply();
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
  final watchSettingsStore = WatchSettingsStore();
  await watchSettingsStore.init();
  final aiChatSettingsStore = AiChatSettingsStore();
  await aiChatSettingsStore.init();
  final aiChatHistoryStore = AiChatHistoryStore();
  await aiChatHistoryStore.init();

  runApp(HealthCompanionApp(
    historyStore: historyStore,
    metricsStore: metricsStore,
    healthLogStore: healthLogStore,
    emergencyContactStore: emergencyContactStore,
    userProfileStore: userProfileStore,
    appSettingsStore: appSettingsStore,
    watchSettingsStore: watchSettingsStore,
    aiChatSettingsStore: aiChatSettingsStore,
    aiChatHistoryStore: aiChatHistoryStore,
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
    required this.watchSettingsStore,
    required this.aiChatSettingsStore,
    required this.aiChatHistoryStore,
  });

  final HistoryStore historyStore;
  final MetricsStore metricsStore;
  final HealthLogStore healthLogStore;
  final EmergencyContactStore emergencyContactStore;
  final UserProfileStore userProfileStore;
  final AppSettingsStore appSettingsStore;
  final WatchSettingsStore watchSettingsStore;
  final AiChatSettingsStore aiChatSettingsStore;
  final AiChatHistoryStore aiChatHistoryStore;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<HistoryStore>.value(value: historyStore),
        ChangeNotifierProvider.value(value: watchSettingsStore),
        ChangeNotifierProvider(
          create: (context) =>
              BleService(historyStore, context.read<WatchSettingsStore>()),
        ),
        ChangeNotifierProvider.value(value: aiChatSettingsStore),
        Provider<AiChatHistoryStore>.value(value: aiChatHistoryStore),
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
            final watchSettings = context.read<WatchSettingsStore>();
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
                watchSettings: watchSettings,
                location: location,
                triggerReason: triggerReason,
              ),
            )..init();
          },
        ),
        ChangeNotifierProvider(
          create: (context) {
            final service = FallDetectorService(
              phoneMotionService: context.read<PhoneMotionService>(),
              emergencyWorkflow: context.read<EmergencyWorkflowService>(),
            );
            if (context.read<AppSettingsStore>().fallDetectionEnabled) {
              service.start();
            }
            return service;
          },
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
        // Needs BleService/HealthLogStore/MetricsStore/UserProfileStore/
        // BaselineService/StepCounterService already registered above (it
        // reads a snapshot of the user's own data for the AI assistant's
        // first message each conversation — see health_context_builder.dart).
        ChangeNotifierProvider(
          create: (context) => AiChatService(
            context.read<AiChatSettingsStore>(),
            context.read<AiChatHistoryStore>(),
            ble: context.read<BleService>(),
            historyStore: context.read<HistoryStore>(),
            metrics: context.read<MetricsStore>(),
            healthLog: context.read<HealthLogStore>(),
            baseline: context.read<BaselineService>(),
            userProfile: context.read<UserProfileStore>(),
            stepCounter: context.read<StepCounterService>(),
          )..init(),
        ),
        Provider<NotificationService>(create: (_) => NotificationService()),
        Provider<MedicationReminderService>(
          // lazy: false — nothing in the widget tree ever reads this
          // provider (it's a pure background service, no UI consumer),
          // so with Provider's default lazy:true its create callback
          // (and therefore start()/rescheduleAll()) would simply never
          // run and no reminder would ever get scheduled.
          lazy: false,
          create: (context) => MedicationReminderService(
            healthLog: context.read<HealthLogStore>(),
            notifications: context.read<NotificationService>(),
            appSettings: context.read<AppSettingsStore>(),
          )..start(),
          dispose: (_, service) => service.dispose(),
        ),
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
            watchSettings: context.read<WatchSettingsStore>(),
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

    // Background fall monitoring follows the master "Detect falls" toggle
    // (Settings > Fall detection) — started automatically once onboarding
    // completes, unless the user has turned fall detection off entirely.
    // start()/stop() are themselves no-ops when already in the requested
    // state, so calling them on every build here is safe — same "cheap to
    // re-check, guarded internally" pattern the gates below use.
    //
    // Deliberately does NOT set the app to show over the lock screen as a
    // standing, app-wide setting — MainActivity.kt applies that only for
    // the one Activity launch that follows a genuine escalation (an
    // unanswered fall alert, an imminent disaster, or the developer/demo
    // preview), never for ordinary use of the app.
    if (userProfile.onboardingCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final monitoring = context.read<BackgroundMonitoringService>();
        if (settings.fallDetectionEnabled) {
          monitoring.start();
        } else {
          monitoring.stop();
        }
      });
    }

    return MaterialApp(
      title: 'ForeverFit',
      navigatorKey: rootNavigatorKey,
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
