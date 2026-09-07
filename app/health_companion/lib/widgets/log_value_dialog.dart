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
