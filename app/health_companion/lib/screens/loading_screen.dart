import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../domain/app_permissions.dart';
import '../services/app_icon_service.dart';
import '../storage/user_profile_store.dart';

/// Shown while the app checks/requests its runtime permissions, before
/// [child] (the rest of the app) is built at all.
///
/// Skips the permission check entirely on a first launch (onboarding not
/// yet completed) — onboarding has its own dedicated permission page with
/// per-permission rationale, and asking again here first would just be a
/// second, unexplained round of system dialogs before the user has seen
/// why the app wants them. For every launch after that, this is what
/// notices a permission got revoked (in system Settings, or by the OS)
/// and asks for it again, without the user needing to visit Settings
/// themselves.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key, required this.child});

  final Widget child;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  Uint8List? _iconBytes;
  bool _iconLoaded = false;
  bool _permissionsReady = false;

  @override
  void initState() {
    super.initState();
    _loadIcon();
    _ensurePermissions();
  }

  Future<void> _loadIcon() async {
    final bytes = await AppIconService.loadIconPng();
    if (mounted) {
      setState(() {
        _iconBytes = bytes;
        _iconLoaded = true;
      });
    }
  }

  Future<void> _ensurePermissions() async {
    final onboardingCompleted =
        context.read<UserProfileStore>().onboardingCompleted;
    if (onboardingCompleted) {
      for (final permission in requestablePermissions) {
        final status = await permission.status;
        if (!status.isGranted) await permission.request();
      }
    }
    if (mounted) setState(() => _permissionsReady = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionsReady) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: _iconLoaded && _iconBytes != null
                    ? Image.memory(_iconBytes!, gaplessPlayback: true)
                    : Icon(
                        Icons.favorite,
                        size: 72,
                        color: Theme.of(context).colorScheme.primary,
                      ),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Checking permissions…',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }
    return widget.child;
  }
}
