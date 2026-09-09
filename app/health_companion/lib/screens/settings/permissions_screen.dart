import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

final _trackedPermissions = <Permission, (String, String)>{
  Permission.locationWhenInUse: (
    'Location',
    'Disaster-risk map, BLE scanning, emergency-call location.'
  ),
  Permission.bluetoothScan: ('Bluetooth scan', 'Finding the wearable.'),
  Permission.bluetoothConnect: (
    'Bluetooth connect',
    'Staying connected to the wearable.'
  ),
  Permission.activityRecognition: (
    'Activity recognition',
    "Phone's step counter."
  ),
  Permission.phone: (
    'Phone',
    'Emergency-contact and emergency-services calls.'
  ),
  Permission.sms: ('SMS', 'Emergency SMS fallback.'),
  Permission.notification: (
    'Notifications',
    'Health/hazard alerts and reminders.'
  ),
  Permission.contacts: (
    'Contacts',
    'Optional — picking an emergency contact from your address book.'
  ),
  Permission.microphone: (
    'Microphone',
    'Optional — voice input for the on-device AI assistant.'
  ),
  Permission.camera: (
    'Camera',
    'Optional — taking a photo to send the on-device AI assistant.'
  ),
};

/// Read-only status of every permission this app uses — never calls
/// `.request()`, only `.status`. Refreshes when the app resumes (e.g.
/// after the user grants something in system Settings and comes back).
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  final Map<Permission, PermissionStatus> _statuses = {};

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
    for (final p in _trackedPermissions.keys) {
      _statuses[p] = await p.status;
    }
    if (mounted) setState(() {});
  }

  String _statusLabel(PermissionStatus? status) {
    if (status == null) return 'Checking…';
    if (status.isGranted) return 'Granted';
    if (status.isPermanentlyDenied) return 'Permanently denied';
    if (status.isRestricted) return 'Restricted';
    if (status.isLimited) return 'Limited';
    return 'Not granted';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final entry in _trackedPermissions.entries)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(entry.value.$1),
                subtitle: Text(entry.value.$2),
                trailing: FilledButton.tonal(
                  onPressed: () async {
                    final status = _statuses[entry.key];
                    if (status != null && status.isPermanentlyDenied) {
                      await openAppSettings();
                    } else {
                      await entry.key.request();
                    }
                    await _refresh();
                  },
                  child: Text(_statusLabel(_statuses[entry.key])),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
