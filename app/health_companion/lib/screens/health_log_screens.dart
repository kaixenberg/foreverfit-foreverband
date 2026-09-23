import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../storage/health_log_store.dart';
import '../theme/app_theme.dart';
import 'medication_edit_screen.dart';
import 'metric_history_screen.dart';

enum MedicationSort { freqMost, freqLeast, nameAZ, nameZA }

extension MedicationSortLabel on MedicationSort {
  String get label => switch (this) {
        MedicationSort.freqMost => 'Most doses/day',
        MedicationSort.freqLeast => 'Fewest doses/day',
        MedicationSort.nameAZ => 'Name A-Z',
        MedicationSort.nameZA => 'Name Z-A',
      };
}

sealed class MedicationFilter {
  const MedicationFilter();
  static const all = _MedicationFilterAll();
  static const active = _MedicationFilterActive();
  static const paused = _MedicationFilterPaused();

  String get label => switch (this) {
        _MedicationFilterAll() => 'All',
        _MedicationFilterActive() => 'Active',
        _MedicationFilterPaused() => 'Paused',
        MedicationFilterType(:final type) => type.label,
      };

  bool matches(Medication medication) => switch (this) {
        _MedicationFilterAll() => true,
        _MedicationFilterActive() => medication.isActive,
        _MedicationFilterPaused() => !medication.isActive,
        MedicationFilterType(:final type) => medication.type == type,
      };
}

class _MedicationFilterAll extends MedicationFilter {
  const _MedicationFilterAll();
}

class _MedicationFilterActive extends MedicationFilter {
  const _MedicationFilterActive();
}

class _MedicationFilterPaused extends MedicationFilter {
  const _MedicationFilterPaused();
}

class MedicationFilterType extends MedicationFilter {
  const MedicationFilterType(this.type);
  final MedicationType type;
}

bool _matchesQuery(Medication medication, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return medication.name.toLowerCase().contains(q) ||
      medication.notes.toLowerCase().contains(q);
}

/// The medications list — search, sort, filter by type/active-paused,
/// multi-select delete (long-press to start), and per-item mark-dose-
/// taken/edit/pause/delete. Adherence (doses/day) is the one thing about
/// medications that IS a meaningful trend, so it gets the same
/// MetricHistoryScreen chart everything else does, reachable from here
/// rather than being the screen's main focus.
class MedicationsScreen extends StatefulWidget {
  const MedicationsScreen({super.key});

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen> {
  String _query = '';
  MedicationSort _sort = MedicationSort.freqMost;
  MedicationFilter _filter = MedicationFilter.all;
  final Set<String> _selectedKeys = {};

  bool get _selecting => _selectedKeys.isNotEmpty;

  List<Medication> _visibleMedications(List<Medication> all) {
    var result = all.where((m) => _filter.matches(m)).toList();
    if (_query.isNotEmpty) {
      result = result.where((m) => _matchesQuery(m, _query)).toList();
    }
    result.sort((a, b) => switch (_sort) {
          MedicationSort.freqMost =>
            b.schedules.length.compareTo(a.schedules.length),
          MedicationSort.freqLeast =>
            a.schedules.length.compareTo(b.schedules.length),
          MedicationSort.nameAZ =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          MedicationSort.nameZA =>
            b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        });
    return result;
  }

  void _toggleSelected(String key) {
    setState(() {
      if (!_selectedKeys.remove(key)) _selectedKeys.add(key);
    });
  }

  void _selectAll(List<Medication> visible) {
    setState(() {
      if (_selectedKeys.length == visible.length) {
        _selectedKeys.clear();
      } else {
        _selectedKeys
          ..clear()
          ..addAll(visible.map((m) => m.key));
      }
    });
  }

  Future<void> _deleteSelected(HealthLogStore log) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${_selectedKeys.length} medication'
            '${_selectedKeys.length == 1 ? '' : 's'}?'),
        content: const Text('This also cancels any reminders for them.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final key in _selectedKeys) {
      await log.removeMedication(key);
    }
    setState(() => _selectedKeys.clear());
  }

  @override
  Widget build(BuildContext context) {
    final log = context.watch<HealthLogStore>();
    final visible = _visibleMedications(log.medications);

    return Scaffold(
      appBar: _selecting
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(_selectedKeys.clear),
              ),
              title: Text('${_selectedKeys.length} selected'),
              actions: [
                IconButton(
                  icon: Icon(_selectedKeys.length == visible.length
                      ? Icons.deselect
                      : Icons.select_all),
                  tooltip: 'Select all',
                  onPressed: () => _selectAll(visible),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete selected',
                  onPressed: () => _deleteSelected(log),
                ),
              ],
            )
          : AppBar(
              title: const Text('Medications'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.show_chart),
                  tooltip: 'Adherence history',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MetricHistoryScreen(
                        title: 'Doses taken',
                        unit: 'doses',
                        points: log.dosesTakenDailyHistory(),
                        accentColor: AppTheme.accentGreen,
                      ),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Add medication'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const MedicationEditScreen(),
              ),
            ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Text('Doses taken today: ${log.dosesTakenToday}',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // A real M3 SearchBar rather than a bare TextField — it has
            // its own theming (stadium shape, surface color/elevation),
            // not the global inputDecorationTheme every other text field
            // in the app uses, so it doesn't need that theme's 16px
            // rounding pushed wider just for this one boxy-looking field
            // — it already matches the stadium-shaped chips/buttons
            // around it by default.
            child: SearchBar(
              hintText: 'Search medications',
              leading: const Icon(Icons.search),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final filter in [
                  MedicationFilter.all,
                  MedicationFilter.active,
                  MedicationFilter.paused,
                  for (final type in MedicationType.values)
                    MedicationFilterType(type),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(filter.label),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PopupMenuButton<MedicationSort>(
                  initialValue: _sort,
                  onSelected: (value) => setState(() => _sort = value),
                  itemBuilder: (context) => [
                    for (final sort in MedicationSort.values)
                      PopupMenuItem(value: sort, child: Text(sort.label)),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort, size: 18),
                      const SizedBox(width: 4),
                      Text(_sort.label,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      log.medications.isEmpty
                          ? 'No medications added yet.'
                          : 'No medications match your search/filter.',
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final medication in visible)
                        _MedicationCard(
                          medication: medication,
                          selected: _selectedKeys.contains(medication.key),
                          selecting: _selecting,
                          onTap: () => _selecting
                              ? _toggleSelected(medication.key)
                              : showDialog<void>(
                                  context: context,
                                  builder: (_) => MedicationEditScreen(
                                      existing: medication),
                                ),
                          onLongPress: () => _toggleSelected(medication.key),
                          onMarkDoseTaken: () =>
                              log.logDoseTaken(medication.name),
                          onToggleActive: () => log.setMedicationActive(
                              medication.key, !medication.isActive),
                          onDelete: () => log.removeMedication(medication.key),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _MedicationCard extends StatelessWidget {
  const _MedicationCard({
    required this.medication,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onMarkDoseTaken,
    required this.onToggleActive,
    required this.onDelete,
  });

  final Medication medication;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMarkDoseTaken;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  static const _typeIcons = {
    MedicationType.pill: Icons.medication_outlined,
    MedicationType.capsule: Icons.medication_liquid_outlined,
    MedicationType.drops: Icons.water_drop_outlined,
    MedicationType.liquid: Icons.local_drink_outlined,
    MedicationType.injection: Icons.vaccines_outlined,
    MedicationType.topical: Icons.healing_outlined,
    MedicationType.unspecified: Icons.medication_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (medication.dosage.isNotEmpty) medication.dosage,
      medication.type.label,
      if (medication.schedules.isNotEmpty)
        medication.schedules.map((s) => s.label).join(', '),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: medication.isActive
          ? null
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        leading: selecting
            ? Checkbox(value: selected, onChanged: (_) => onTap())
            : Icon(_typeIcons[medication.type]),
        title: Text(medication.name,
            style: medication.isActive
                ? null
                : const TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: Colors.grey,
                  )),
        subtitle: Text(subtitleParts.join(' — ')),
        trailing: selecting
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check),
                    tooltip: 'Mark dose taken',
                    onPressed: onMarkDoseTaken,
                  ),
                  PopupMenuButton<void>(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        onTap: onTap,
                        child: const Text('Edit'),
                      ),
                      PopupMenuItem(
                        onTap: onToggleActive,
                        child: Text(medication.isActive ? 'Pause' : 'Resume'),
                      ),
                      PopupMenuItem(
                        onTap: onDelete,
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
