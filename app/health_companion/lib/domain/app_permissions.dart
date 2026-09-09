import 'package:permission_handler/permission_handler.dart';

/// Every runtime permission this app ever requests — the single source
/// of truth for "which permissions," shared by the loading screen (which
/// requests anything not yet granted on every launch), the onboarding
/// flow (which explains each one before asking), and the Settings
/// Permissions screen (which shows live status for each). Per the
/// standing rule for this project: add a new `Permission.x` here first,
/// then give it rationale text in onboarding_screen.dart and a status row
/// in permissions_screen.dart — special-access permissions (SYSTEM_
/// ALERT_WINDOW, battery-optimization exemption) don't go through
/// permission_handler at all and get their own dedicated screens instead,
/// so they don't belong in this list.
const requestablePermissions = [
  Permission.locationWhenInUse,
  Permission.bluetoothScan,
  Permission.bluetoothConnect,
  Permission.activityRecognition,
  Permission.phone,
  Permission.sms,
  Permission.notification,
  Permission.contacts,
];
