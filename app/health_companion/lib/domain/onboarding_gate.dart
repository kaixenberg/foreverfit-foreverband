import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/onboarding_screen.dart';
import '../storage/user_profile_store.dart';

/// Outermost of the app's three gates (wraps ImminentWarningGate, which
/// wraps EmergencyCallGate, which wraps DashboardScreen) — onboarding
/// must happen before any disaster/emergency full-screen route could
/// possibly fire. Same `_showing`-guarded addPostFrameCallback pattern
/// as the other gates, keyed on `!onboardingCompleted` — a one-shot
/// condition that stays false forever once OnboardingScreen finishes.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  bool _showing = false;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<UserProfileStore>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow(profile));
    return widget.child;
  }

  void _maybeShow(UserProfileStore profile) {
    if (!mounted || _showing || profile.onboardingCompleted) return;
    _showing = true;
    Navigator.of(context, rootNavigator: true)
        .push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const OnboardingScreen(),
          ),
        )
        .then((_) => _showing = false);
  }
}
