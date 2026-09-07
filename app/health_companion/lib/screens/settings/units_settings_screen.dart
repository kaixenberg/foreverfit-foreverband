import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/units.dart';
import '../../storage/app_settings_store.dart';

class UnitsSettingsScreen extends StatelessWidget {
  const UnitsSettingsScreen({super.key});

  String _label(UnitSystem system) {
    switch (system) {
      case UnitSystem.metric:
        return 'Metric (kg, cm, °C)';
      case UnitSystem.imperial:
        return 'Imperial (lb, in, °F)';
      case UnitSystem.system:
        return 'Use device locale';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('Units')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Your data is always stored in metric — this only changes how '
            'values are shown and how you type new entries. Applies to '
            'weight, height, hydration, temperature, and wind speed.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          RadioGroup<UnitSystem>(
            groupValue: settings.unitSystem,
            onChanged: (value) {
              if (value != null) settings.setUnitSystem(value);
            },
            child: Column(
              children: [
                for (final system in UnitSystem.values)
                  RadioListTile<UnitSystem>(
                    title: Text(_label(system)),
                    value: system,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
