import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

/// Flow intensity options for menstrual cycle logging — a category, not
/// something to chart, same reasoning as [insulinTypes].
const cycleFlowLevels = ['Light', 'Medium', 'Heavy'];

/// Period start date (required — the one thing cycle length/prediction
/// is computed from), optional end date, optional flow intensity, and
/// free-text notes. Unlike every other dialog above, the date it refers
/// to usually isn't "now" (periods are often logged a day or more after
/// they start), so this is the one dialog in this file with a date
/// picker at all. Also reused for editing when the initial* params are
/// given. Returns null if cancelled.
Future<({DateTime startDate, DateTime? endDate, String? flow, String? notes})?>
    showCycleEntryDialog({
  required BuildContext context,
  String title = 'Log period',
  DateTime? initialStartDate,
  DateTime? initialEndDate,
  String? initialFlow,
  String? initialNotes,
}) {
  var startDate = initialStartDate ?? DateTime.now();
  var endDate = initialEndDate;
  var flow = initialFlow;
  final notesController = TextEditingController(text: initialNotes ?? '');
  return showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start date'),
                subtitle: Text(DateFormat.yMMMd().format(startDate)),
                trailing: const Icon(Icons.calendar_today_outlined, size: 18),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: startDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => startDate = picked);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('End date'),
                subtitle: Text(endDate == null
                    ? 'Not set — still ongoing or unknown'
                    : DateFormat.yMMMd().format(endDate!)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (endDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Clear end date',
                        onPressed: () => setState(() => endDate = null),
                      ),
                    const Icon(Icons.calendar_today_outlined, size: 18),
                  ],
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: endDate ?? startDate,
                    firstDate: startDate,
                    lastDate: DateTime.now().add(const Duration(days: 14)),
                  );
                  if (picked != null) setState(() => endDate = picked);
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: flow,
                decoration: const InputDecoration(labelText: 'Flow (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Not set')),
                  for (final level in cycleFlowLevels)
                    DropdownMenuItem(value: level, child: Text(level)),
                ],
                onChanged: (value) => setState(() => flow = value),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Notes / symptoms (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop((
              startDate: startDate,
              endDate: endDate,
              flow: flow,
              notes: notesController.text.trim().isEmpty
                  ? null
                  : notesController.text.trim(),
            )),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
