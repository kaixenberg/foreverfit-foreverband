import 'package:flutter/material.dart';

/// A single-field numeric entry dialog, reused for weight/height/body-fat
/// logging. Returns the entered value, or null if cancelled.
Future<double?> showLogValueDialog({
  required BuildContext context,
  required String title,
  required String unit,
}) {
  final controller = TextEditingController();
  return showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(suffixText: unit),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = double.tryParse(controller.text);
            Navigator.of(context).pop(value);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// A two-field entry dialog for blood pressure (systolic/diastolic
/// arrive together as one reading, unlike every other logged metric
/// here). Returns (systolic, diastolic), or null if cancelled.
Future<(int, int)?> showBloodPressureDialog({required BuildContext context}) {
  final systolicController = TextEditingController();
  final diastolicController = TextEditingController();
  return showDialog<(int, int)>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Log blood pressure'),
      content: Row(
        children: [
          Expanded(
            child: TextField(
              controller: systolicController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Systolic', suffixText: 'mmHg'),
            ),
          ),
          const SizedBox(width: 12),
          const Text('/', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: diastolicController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Diastolic', suffixText: 'mmHg'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final systolic = int.tryParse(systolicController.text);
            final diastolic = int.tryParse(diastolicController.text);
            if (systolic == null || diastolic == null) {
              Navigator.of(context).pop();
              return;
            }
            Navigator.of(context).pop((systolic, diastolic));
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Dose + type entry dialog for insulin — the type (rapid/long-acting/
/// etc.) is a category, not something to chart, so it's captured but
/// only the dose becomes the loggable MetricPoint value.
const insulinTypes = ['Rapid-acting', 'Long-acting', 'Intermediate', 'Mixed'];

Future<(double, String)?> showInsulinDialog({required BuildContext context}) {
  final doseController = TextEditingController();
  var selectedType = insulinTypes.first;
  return showDialog<(double, String)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Log insulin dose'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: doseController,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Dose', suffixText: 'units'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedType,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final type in insulinTypes)
                  DropdownMenuItem(value: type, child: Text(type)),
              ],
              onChanged: (value) =>
                  setState(() => selectedType = value ?? selectedType),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final dose = double.tryParse(doseController.text);
              if (dose == null) {
                Navigator.of(context).pop();
                return;
              }
              Navigator.of(context).pop((dose, selectedType));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
