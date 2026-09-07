import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../storage/app_settings_store.dart';

class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

  String _label(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Follow system';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsStore>();
    final systemIsDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final effectiveIsDark = settings.themeMode == ThemeMode.dark ||
        (settings.themeMode == ThemeMode.system && systemIsDark);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Theme', style: Theme.of(context).textTheme.titleMedium),
          RadioGroup<ThemeMode>(
            groupValue: settings.themeMode,
            onChanged: (value) {
              if (value != null) settings.setThemeMode(value);
            },
            child: Column(
              children: [
                for (final mode in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    title: Text(_label(mode)),
                    value: mode,
                  ),
              ],
            ),
          ),
          const Divider(height: 32),
          SwitchListTile(
            title: const Text('OLED black'),
            subtitle: Text(effectiveIsDark
                ? 'True black backgrounds — saves battery on OLED screens.'
                : 'Only applies while the theme is dark.'),
            value: settings.oledBlack,
            onChanged: effectiveIsDark ? (v) => settings.setOledBlack(v) : null,
          ),
          const Divider(height: 32),
          SwitchListTile(
            title: const Text('Dynamic color (Material You)'),
            subtitle: const Text(
                'Match your device\'s wallpaper accent color — coming soon.'),
            value: false,
            onChanged: null,
          ),
        ],
      ),
    );
  }
}
