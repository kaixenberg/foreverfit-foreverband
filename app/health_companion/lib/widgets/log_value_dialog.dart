import 'package:flutter/material.dart';

/// Formats a value for pre-filling an edit dialog's text field — fixed to
/// 2 decimal places (enough precision for anything logged here) with
/// trailing zeros/dot trimmed, so editing 72kg shows "72" not "72.00".
String _trimZeros(double value) {
  var text = value.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}

/// A single-field numeric entry dialog, reused for weight/height/body-fat
/// logging, and for editing an existing entry when [initialValue] is
/// given. Returns the entered value, or null if cancelled.
Future<double?> showLogValueDialog({
  required BuildContext context,
  required String title,
  required String unit,
  double? initialValue,
}) {
  final controller = TextEditingController(
    text: initialValue == null ? '' : _trimZeros(initialValue),
  );
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
/// here), also reused for editing when [initialSystolic]/
/// [initialDiastolic] are given. Returns (systolic, diastolic), or null
/// if cancelled.
Future<(int, int)?> showBloodPressureDialog({
  required BuildContext context,
  String title = 'Log blood pressure',
  int? initialSystolic,
  int? initialDiastolic,
}) {
  final systolicController =
      TextEditingController(text: initialSystolic?.toString() ?? '');
  final diastolicController =
      TextEditingController(text: initialDiastolic?.toString() ?? '');
  return showDialog<(int, int)>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
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

/// Also reused for editing when [initialDose]/[initialType] are given.
Future<(double, String)?> showInsulinDialog({
  required BuildContext context,
  String title = 'Log insulin dose',
  double? initialDose,
  String? initialType,
}) {
  final doseController = TextEditingController(
    text: initialDose == null ? '' : _trimZeros(initialDose),
  );
  var selectedType = initialType ?? insulinTypes.first;
  return showDialog<(double, String)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
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
