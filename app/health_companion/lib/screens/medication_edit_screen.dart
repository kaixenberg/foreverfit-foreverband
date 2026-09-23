import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../storage/health_log_store.dart';

/// Add/edit form for a single medication — shown as a floating dialog
/// (`showDialog`, see MedicationsScreen) rather than a full-screen route.
/// Name, type, amount, unit, and at least one dose time are all
/// mandatory; only notes is optional — "Save" stays disabled until all
/// of those are filled in, rather than accepting a save attempt and
/// pointing out what's missing after the fact.
///
/// Active/paused is deliberately NOT exposed here — same as before this
/// overhaul, it's a list-level action (MedicationsScreen's pause/resume
/// menu item), not something you set while composing the medication
/// itself; a new medication always starts active.
class MedicationEditScreen extends StatefulWidget {
  const MedicationEditScreen({super.key, this.existing});

  /// Null when adding a new medication; the medication being edited
  /// otherwise. Its `isActive`/`key` are preserved on save — see
  /// HealthLogStore.saveMedication.
  final Medication? existing;

  @override
  State<MedicationEditScreen> createState() => _MedicationEditScreenState();
}

class _MedicationEditScreenState extends State<MedicationEditScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;
  late MedicationType _type;
  late String _unit;
  late List<MedicationSchedule> _schedules;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '')
      ..addListener(_onFieldChanged);
    _amountController = TextEditingController(text: existing?.amount ?? '')
      ..addListener(_onFieldChanged);
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _type = existing?.type ?? MedicationType.pill;
    // Not just `existing?.unit ?? ...` — a medication saved before the
    // amount/unit split has `unit == ''` (empty, not null; see
    // _medicationFromBox's migration fallback), and an empty string
    // isn't in any type's unit list, which crashes
    // DropdownButtonFormField's "must match exactly one item" assertion.
    // Falls back whenever the existing unit isn't valid for the
    // (possibly just-defaulted) type, not only when it's literally null.
    final units = medicationUnitsByType[_type]!;
    _unit = (existing != null && units.contains(existing.unit))
        ? existing.unit
        : units.first;
    _schedules = List.of(existing?.schedules ?? const []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onFieldChanged() => setState(() {});

  bool get _isValid =>
      _nameController.text.trim().isNotEmpty &&
      _amountController.text.trim().isNotEmpty &&
      _schedules.isNotEmpty;

  void _onTypeChanged(MedicationType type) {
    setState(() {
      _type = type;
      final units = medicationUnitsByType[type]!;
      if (!units.contains(_unit)) _unit = units.first;
    });
  }

  Future<void> _addSchedule() async {
    final picked =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked == null) return;
    setState(() {
      _schedules = List.of(_schedules)
        ..add(MedicationSchedule(hour: picked.hour, minute: picked.minute))
        ..sort(
            (a, b) => a.hour != b.hour ? a.hour - b.hour : a.minute - b.minute);
    });
  }

  void _removeSchedule(MedicationSchedule schedule) {
    setState(() {
      _schedules = List.of(_schedules)..remove(schedule);
    });
  }

  Future<void> _save() async {
    final log = context.read<HealthLogStore>();
    await log.saveMedication(
      key: widget.existing?.key,
      name: _nameController.text.trim(),
      amount: _amountController.text.trim(),
      unit: _unit,
      type: _type,
      isActive: widget.existing?.isActive ?? true,
      notes: _notesController.text.trim(),
      schedules: _schedules,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final units = medicationUnitsByType[_type]!;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isEditing ? 'Edit Medication' : 'Add Medication',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nameController,
                  autofocus: !isEditing,
                  decoration: const InputDecoration(
                    labelText: 'Medication Name',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<MedicationType>(
                  initialValue: _type,
                  decoration: const InputDecoration(
                    labelText: 'Medication Type',
                  ),
                  items: [
                    for (final type in MedicationType.values)
                      DropdownMenuItem(value: type, child: Text(type.label)),
                  ],
                  onChanged: (type) {
                    if (type != null) _onTypeChanged(type);
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(labelText: 'Amount'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _unit,
                        decoration: const InputDecoration(labelText: 'Unit'),
                        items: [
                          for (final unit in units)
                            DropdownMenuItem(value: unit, child: Text(unit)),
                        ],
                        onChanged: (unit) {
                          if (unit != null) setState(() => _unit = unit);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    alignLabelWithHint: true,
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                Text('Schedule',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_schedules.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final schedule in _schedules)
                          InputChip(
                            label: Text(schedule.label),
                            onDeleted: () => _removeSchedule(schedule),
                          ),
                      ],
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _addSchedule,
                    icon: const Icon(Icons.add),
                    label: const Text('Add time'),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _isValid ? _save : null,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
