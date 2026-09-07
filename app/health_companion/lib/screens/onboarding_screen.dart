import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'profile_medical_screen.dart';

const _corePermissions = [
  Permission.locationWhenInUse,
  Permission.bluetoothScan,
  Permission.bluetoothConnect,
  Permission.activityRecognition,
  Permission.phone,
  Permission.sms,
  Permission.notification,
];

final _permissionRationale = {
  Permission.locationWhenInUse: (
    'Location',
    'For the disaster-risk map and the location included in an emergency alert.'
  ),
  Permission.bluetoothScan: (
    'Bluetooth',
    'To find and connect your Health Companion wearable.'
  ),
  Permission.bluetoothConnect: (
    'Bluetooth',
    'To stay connected to your wearable once paired.'
  ),
  Permission.activityRecognition: (
    'Activity recognition',
    "For the phone's step counter."
  ),
  Permission.phone: (
    'Phone',
    'To call emergency services/your contact automatically after a detected fall.'
  ),
  Permission.sms: (
    'SMS',
    'For the emergency text fallback if your contact never answers.'
  ),
  Permission.notification: (
    'Notifications',
    'For health/hazard alerts and reminders.'
  ),
};

/// First-launch flow — gated by OnboardingGate on
/// `!UserProfileStore.onboardingCompleted`. Two pages: permissions (with
/// rationale, best-effort — denial never blocks continuing, matching
/// how the rest of the app treats permission denial as graceful
/// degradation, not a hard stop) and profile/medical info.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final Map<Permission, PermissionStatus> _statuses = {};
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _refreshStatuses();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _refreshStatuses() async {
    for (final p in _corePermissions) {
      _statuses[p] = await p.status;
    }
    if (mounted) setState(() {});
  }

  Future<void> _requestAll() async {
    await _corePermissions.request();
    await _refreshStatuses();
  }

  void _goToPage2() {
    _pageController.animateToPage(1,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // mandatory first-launch flow — no back-out until finished
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    _PermissionsPage(
                      statuses: _statuses,
                      onRequestAll: _requestAll,
                      onContinue: _goToPage2,
                    ),
                    const ProfileMedicalScreen(isOnboarding: true),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 2; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _page
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionsPage extends StatelessWidget {
  const _PermissionsPage({
    required this.statuses,
    required this.onRequestAll,
    required this.onContinue,
  });

  final Map<Permission, PermissionStatus> statuses;
  final VoidCallback onRequestAll;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Welcome to Health Companion',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Everything here stays on your device — nothing is uploaded '
          'except through an emergency call, text, or a backup you '
          'export yourself. A few permissions unlock the full feature set:',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (final permission in _permissionRationale.keys)
          _PermissionRow(
            permission: permission,
            status: statuses[permission],
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: onRequestAll,
          child: const Text('Grant permissions'),
        ),
        const SizedBox(height: 8),
        Text(
          "You can change any of these later in Settings, and the app "
          "degrades gracefully if you skip one — it just won't be able "
          "to use that specific feature.",
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: onContinue,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.permission, required this.status});

  final Permission permission;
  final PermissionStatus? status;

  @override
  Widget build(BuildContext context) {
    final (title, reason) = _permissionRationale[permission]!;
    final granted = status?.isGranted ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            granted ? Icons.check_circle : Icons.circle_outlined,
            size: 20,
            color: granted
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(reason, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
