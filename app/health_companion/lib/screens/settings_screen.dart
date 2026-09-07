import 'package:flutter/material.dart';

import 'profile_medical_screen.dart';
import 'settings/appearance_settings_screen.dart';
import 'settings/background_permission_screen.dart';
import 'settings/data_backup_screen.dart';
import 'settings/developer_demo_screen.dart';
import 'settings/medical_emergency_screen.dart';
import 'settings/permissions_screen.dart';
import 'settings/sensor_precedence_screen.dart';
import 'settings/units_settings_screen.dart';
import 'settings/warning_choices_screen.dart';
import 'settings/wearable_settings_screen.dart';

class _SettingsCategory {
  const _SettingsCategory(this.icon, this.title, this.subtitle, this.builder);
  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;
}

final _categories = [
  _SettingsCategory(
    Icons.person_outline,
    'Profile & Medical',
    'Your info, blood type, allergies, conditions, weight, height',
    (_) => const ProfileMedicalScreen(isOnboarding: false),
  ),
  _SettingsCategory(
    Icons.straighten_outlined,
    'Units',
    'Metric, Imperial, or match your device',
    (_) => const UnitsSettingsScreen(),
  ),
  _SettingsCategory(
    Icons.palette_outlined,
    'Appearance',
    'Theme, OLED black, dynamic color',
    (_) => const AppearanceSettingsScreen(),
  ),
  _SettingsCategory(
    Icons.import_export_outlined,
    'Data export & import',
    'Back up or restore all your data',
    (_) => const DataBackupScreen(),
  ),
  _SettingsCategory(
    Icons.watch_outlined,
    'Wearable',
    'Connect and manage devices',
    (_) => const WearableSettingsScreen(),
  ),
  _SettingsCategory(
    Icons.tune_outlined,
    'Sensor precedence',
    'Which source wins when more than one is available',
    (_) => const SensorPrecedenceScreen(),
  ),
  _SettingsCategory(
    Icons.notifications_active_outlined,
    'Warning choices',
    'Which notification categories to receive',
    (_) => const WarningChoicesScreen(),
  ),
  _SettingsCategory(
    Icons.emergency_outlined,
    'Medical emergency',
    'Emergency contact and local hotline number',
    (_) => const MedicalEmergencyScreen(),
  ),
  _SettingsCategory(
    Icons.verified_user_outlined,
    'Permissions',
    'What this app can currently access',
    (_) => const PermissionsScreen(),
  ),
  _SettingsCategory(
    Icons.battery_saver_outlined,
    'Background permission',
    'Keep monitoring running when the screen is off',
    (_) => const BackgroundPermissionScreen(),
  ),
  _SettingsCategory(
    Icons.developer_mode_outlined,
    'Developer / demo',
    'Test mode and full-screen warning previews',
    (_) => const DeveloperDemoScreen(),
  ),
];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final category = _categories[i];
          return Card(
            child: ListTile(
              leading: Icon(category.icon),
              title: Text(category.title),
              subtitle: Text(category.subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: category.builder),
              ),
            ),
          );
        },
      ),
    );
  }
}
